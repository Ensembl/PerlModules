
package Hum::EMBL;

use strict;
use warnings;
use Carp qw{ cluck confess };
use Digest::MD5;
use Symbol 'gensym';

use Hum::EMBL::Line;    # Contains most of the line handling packages
use Hum::StringHandle;
use Hum::Sequence::DNA;
use Hum::Sequence::Peptide;

BEGIN {

    my %_handler = (
         ID => 'Hum::EMBL::Line::ID',
         AC => 'Hum::EMBL::Line::AC',
         SV => 'Hum::EMBL::Line::SV',
         NI => 'Hum::EMBL::Line::NI',
         DT => 'Hum::EMBL::Line::DT',
         DE => 'Hum::EMBL::Line::DE',
         KW => 'Hum::EMBL::Line::KW',
         OS => 'Hum::EMBL::Line::Organism',
         OC => 'Hum::EMBL::Line::Organism',
         OG => 'Hum::EMBL::Line::OG',
         RN => 'Hum::EMBL::Line::Reference',
         RC => 'Hum::EMBL::Line::Reference',
         RG => 'Hum::EMBL::Line::Reference',
         RP => 'Hum::EMBL::Line::Reference',
         RX => 'Hum::EMBL::Line::Reference',
         RA => 'Hum::EMBL::Line::Reference',
         RT => 'Hum::EMBL::Line::Reference',
         RL => 'Hum::EMBL::Line::Reference',
         DR => 'Hum::EMBL::Line::DR',
         FH => 'Hum::EMBL::Line::FH',
         FT => 'Hum::EMBL::Line::FT',
         CC => 'Hum::EMBL::Line::CC',
         CO => 'Hum::EMBL::Line::CO',
         XX => 'Hum::EMBL::Line::XX',
         SQ => 'Hum::EMBL::Line::Sequence',
       '  ' => 'Hum::EMBL::Line::Sequence',
       '//' => 'Hum::EMBL::Line::End',
    );
    
    my( %_registered_class );
    
    sub import {
        my $pkg = shift;

        if (@_) {
            confess "Odd number of agruments" if @_ % 2;
            for (my $i = 0; $i < @_; $i += 2) {
                $_handler{$_[$i]} = $_[$i+1]
            }
        }

        # Generate access methods for each line type package,
        # giving them the same name as the package.
        my %packages = map {$_, 1} values %_handler;
        CLASS: foreach my $class (keys %packages) {
        
            # Load line modules not in Hum/EMBL/Line.pm (yagni?)
            unless (__symbols_in_package($class)) {
                my $file = "$class.pm";
                $file =~ s{::}{/}g;
                require $file;
            }
        
            my ($name) = $class =~ /([^:]+)$/;

            # Don't try and regenerate access methods if we
            # already done so for this class
            if (my $reg_class = $_registered_class{$name}) {
                confess("Can't make methods under '$name' for class '$class':\n",
                    "$name is already registered with '$reg_class'")
                    unless $class eq $reg_class;
                next CLASS;
            } else {
                $_registered_class{$name} = $class;
            }

            # Don't redefine existing subroutines
            my $func = "${pkg}::$name";
            if (defined( &$func )) {
                confess "sub '$func' already defined";
            } else {
                no strict 'refs';
                *$func = sub {
                    my( $embl ) = @_;

                    confess("Not an object '$embl'") unless ref($embl);
                    my @lines = grep { ref($_) eq $class } $embl->lines();

                    if (wantarray) {
                        return @lines;
                    } else {
                        confess "No line types from '$class' class in entry" unless @lines;
                        return $lines[0];
                    }
                };
            }

            # Define functions so can say $embl->newCC
            my $newFunc = "${pkg}::new$name";
            if (defined( &$newFunc )) {
                confess "sub '$newFunc' already defined";
            } else {
                no strict 'refs';
                *$newFunc = sub {
                    my $embl = shift;

                    my $line = $class->new(@_);
                    $embl->addLine( $line );
                    return $line;
                };
            }
        }
    }
    
    sub default_handler {
        my $pkg = shift;
        $pkg->import(@_);
    }
    
    sub new {
        my $proto = shift;
        
        my($class, %handler);

        if (ref($proto)) {
            # $proto is an object
            $class = ref($proto);
            %handler = %{$proto->{'handler'}};
        } else {
            # $proto is a package name
            $class = $proto;
            if (@_) {
                confess "Odd number of arguments to new()" if @_ % 2;
                %handler = @_;
            } else {
                %handler = %_handler;
            }
        }
        
        return bless {
            handler => \%handler,
            _lines  => [],
        }, $class;
    }    
}


# Returns count (in scalar context) or list of the symbols in the
# package
sub __symbols_in_package {
    my ($class) = @_;
    my $symbol_table = "${class}::";
    no strict 'refs';
    return keys %{$symbol_table};
}


sub parse {
    my( $embl, $arg ) = @_;
    
    my $type = ref($arg);
    my( $fh );
    if ($type eq 'GLOB') {
        $fh = $arg;
    } elsif ($type eq 'SCALAR') {
        # A bit of magic which makes a string
        # behave like a filehandle
        $fh = Hum::StringHandle->new($arg);
    } else {
        $fh = gensym();
        open $fh, $arg or confess("Can't open file '$arg' : $!")
    }
    
    my $entry = $embl->new();
    
    local $/ = "\n";
    my( $current, @group, @obj );
    while (<$fh>) {
    
        # Get prefix and trim whitespace from the right
        my ($prefix) = substr($_, 0, 5) =~ /^(..+?)\s*$/;
        
        # This ignores lines which aren't registered in the handler
        ### FIXME - this will merge blocks separated by unregistered line types ###
        if (my $class = $entry->{'handler'}{$prefix}) {
            $current ||= $class; # Needed for first line
            if ($current eq $class) {
                # Add to the group if belongs to same class
                push( @group, $_ );
            } else {
                # Make new line object(s) if current line belongs to a
                # different class, and add to the list of objects.
                my @line = $current->store(@group);
                push( @obj, @line ) if @line;

                # Set $current to new class, and save line
                # in @group
                $current = $class;
                @group = ($_);
            }

        }
        #else {
        #    warn "Ignoring : $_";
        #}

        # Break at end of entries
        last if $prefix eq '//';
    }

    # Store the last line group
    if (@group) {    
        my @last = $current->store(@group);
        push( @obj, @last ) if @last;
    }
    
    # Return a new Entry object if we've got Line objects
    if (@obj) {
        $entry->lines( \@obj );
        return $entry;
    } else {
        return;
    }
}

sub compose {
    my( $embl ) = @_;
    
    my( @compose );
    foreach my $line ($embl->lines) {
        push( @compose, $line->compose );
    }
    return @compose;
}

sub lines {
    my( $embl, $lines ) = @_;
    
    if ($lines) {
        $embl->{'_lines'} = $lines;
    } else {
        return @{$embl->{'_lines'}};
    }
}

sub md5_checksum {
    my( $embl ) = @_;

    my $md5 = Digest::MD5->new;
    foreach my $line ($embl->lines) {
        # Each Line type can decide what it puts
        # in the string for the checksum.
        $md5->add($line->string_for_checksum);
    }
    return $md5->b64digest;
}

sub region_start_end {

  # start/end of annotated region
  my $embl = shift;

  my $se = [];
  foreach my $line ($embl->lines) {

    if ( ref($line) eq "Hum::EMBL::Line::FT" and $line->key eq 'misc_feature' ){
      my @lns = split(/\n/, $line->compose);
      if ($lns[1] =~ /annotated region of clone/) {
        $lns[0] =~ /^FT   \S+\s+(.+)$/;
        my ($start, $end) = split(/\.\./, $1);
        push( @$se, $start, $end);
      }
      return $se;
    }
  }
}

sub addLine {
    my( $embl, $line ) = @_;

    if ($line) {
        push @{$embl->{'_lines'}}, $line;
    } else {
        confess "No line provided to addLine()";
    }
}

sub bio_primary_seq {
    my( $embl ) = @_;

    return $embl->_make_bio_seq('Bio::PrimarySeq');
}

sub bio_seq {
    my( $embl ) = @_;
    
    return $embl->_make_bio_seq('Bio::Seq');
}

sub _make_bio_seq {
    my ($embl, $class) = @_;
    
    require $class;
    
    my $id_line = $embl->ID;
    my $acc = $id_line->accession;
    my $sv  = $id_line->version;
    my $seq = $embl->Sequence->seq;

    my $name = $sv ? "$acc.$sv" : $acc;

    return $class->new(
        -id        => $name,
        -accession => $acc,
        -moltype   => 'dna',
        -seq       => $seq,
    );
}

sub hum_sequence {
    my( $embl ) = @_;
    
    my $id_line = $embl->ID;
    my $acc = $id_line->accession;
    my $sv  = $id_line->version;
    my $name = $sv ? "$acc.$sv" : $acc;

    my @desc_list = $embl->DE->list;
    my $desc = join('  ', @desc_list);

    my $seq = Hum::Sequence::DNA->new;
    $seq->name($name);
    $seq->description($desc);
    $seq->sequence_string($embl->Sequence->seq);

    return $seq;
}

1;

__END__


=head1 NAME - Hum::EMBL

=head1 SYNOPSIS


    use Hum::EMBL;
    
    # Parse the entries supplied to the script.
    # Equivalent to the "while (<>)" construct.
    my $parser = 'Hum::EMBL'->new;
    while (my $embl = $parser->parse(\*ARGV)) {
        # Get the accession number
        my $acc = $embl->AC->primary;
        
        # Loop over the CDS objects in the feature table
        foreach my $feat ($embl->FT) {
            if ($feat->key eq 'CDS') {
                # do something...
            }
        }
    }

=head1 DESCRIPTION

This module is for parsing and generating files
in the EMBL nucleotide database format
(B<http://www.ebi.ac.uk/embl/Documentation/index.html>).

It uses ideas from Matthew Pocock and Ewan
Birney's B<Embl.pm> module.  In particular each
EMBL line prefix is associated with a package,
which contains parsing, formatting, and data
access functions.

The cardinality of EMBL line types in standard
EMBL files are as follows:

     ID - identification             (begins each entry; 1 per entry)
     AC - accession number           (>=1 per entry)
     SV - new sequence identifier    (>=1 per entry)
     NI - old sequence identifier    (>=1 per entry)
     DT - date                       (2 per entry)
     DE - description                (>=1 per entry)
     KW - keyword                    (>=1 per entry)
     OS - organism species           (>=1 per entry)
     OC - organism classification    (>=1 per entry)
     OG - organelle                  (0 or 1 per entry)
     RN - reference number           (>=1 per entry)
     RC - reference comment          (>=0 per entry)
     RP - reference positions        (>=1 per entry)
     RX - reference cross-reference  (>=0 per entry)
     RA - reference author(s)        (>=1 per entry)
     RT - reference title            (>=1 per entry)
     RL - reference location         (>=1 per entry)
     DR - database cross-reference   (>=0 per entry)
     FH - feature table header       (0 or 2 per entry)
     FT - feature table data         (>=0 per entry)
     CC - comments or notes          (>=0 per entry)
     XX - spacer line                (many per entry)
     SQ - sequence header            (1 per entry)
     bb - (blanks) sequence data     (>=1 per entry)
     // - termination line           (ends each entry; 1 per entry)

The default mapping between EMBL line prefixes
and packages which you get with:

    use Hum::EMBL;

is as follows:

         ID => 'Hum::EMBL::Line::ID',
         AC => 'Hum::EMBL::Line::AC',
         SV => 'Hum::EMBL::Line::SV',
         NI => 'Hum::EMBL::Line::NI',
         DT => 'Hum::EMBL::Line::DT',
         DE => 'Hum::EMBL::Line::DE',
         KW => 'Hum::EMBL::Line::KW',
         OS => 'Hum::EMBL::Line::Organism',
         OC => 'Hum::EMBL::Line::Organism',
         OG => 'Hum::EMBL::Line::OG',
         RN => 'Hum::EMBL::Line::Reference',
         RC => 'Hum::EMBL::Line::Reference',
         RP => 'Hum::EMBL::Line::Reference',
         RX => 'Hum::EMBL::Line::Reference',
         RA => 'Hum::EMBL::Line::Reference',
         RT => 'Hum::EMBL::Line::Reference',
         RL => 'Hum::EMBL::Line::Reference',
         DR => 'Hum::EMBL::Line::DR',
         FH => 'Hum::EMBL::Line::FH',
         FT => 'Hum::EMBL::Line::FT',
         CC => 'Hum::EMBL::Line::CC',
         XX => 'Hum::EMBL::Line::XX',
         SQ => 'Hum::EMBL::Line::Sequence',
       '  ' => 'Hum::EMBL::Line::Sequence',
       '//' => 'Hum::EMBL::Line::End',


Consecutive lines in the EMBL file which map to
the same package are (usually) stored as a single
line object.  'FT' lines are an exception,
because they are split into separate feature
objects.

The method you call to access all the line
objects from a particular package is named from
the last element of the package name (see
above).  For example:

    my @refs = $embl->Reference;

In scalar context you get the first line object
of this type:

    my $first_ref = $embl->Reference;

This is useful for accessing a data element from
a line object, which you know will have a
cardinality of 1 in the file, in a single step:

    my $accession = $embl->AC->primary;

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

