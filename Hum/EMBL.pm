
package Hum::EMBL;

use strict;
use Carp;
use Hum::EMBL::Line;

=pod

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

=cut


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
    );
    
    sub import {
        my $pkg = shift;

        if (@_) {
            confess "Odd number of agruments" if @_ % 2;
            %_handler = @_;
        }

        # Generate access methods for each line type package,
        # giving them the same name as the package.
        my %packages = map {$_, 1} values %_handler;
        foreach my $class (keys %packages) {
            my ($name) = $class =~ /([^:]+)$/;

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
    
    sub new {
        my( $proto ) = @_;
        my($class, $handler);

        if(ref($proto)) {
            # $proto is an object
            $class = ref($proto);
            $handler = \%{$proto->{'handler'}};
        } else {
            # $proto is a package name
            $class = $proto;
            $handler = {%_handler};
        }

        return bless {
            handler => $handler,
            _lines  => [],
        }, $class;
    }    
}

sub parse {
    my( $embl, $fh ) = @_;
    
    my $entry = $embl->new();
    
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
        # Break at end of entries
        last if $prefix eq '//';
    }

    # Store the last line group
    if (@group) {    
        my @last = $current->store(@group);
        push( @obj, @last ) if @last;
    }
    
    # Return an new Entry object if we've got Line objects
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
    foreach my $line ($embl->lines()) {
        push( @compose, $line->getString() );
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

sub addLine {
    my( $embl, $line ) = @_;
    
    if ($line) {
        push @{$embl->{'_lines'}}, $line;
    } else {
        confess "No line provided to addLine()";
    }
}


1;

__END__
