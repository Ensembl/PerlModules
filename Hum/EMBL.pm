
package Hum::EMBL;

use strict;
use Carp;
use Hum::EMBL::Line;

sub new {
    my $pkg = shift;
    
    confess "Odd number of agruments" if @_ % 2;
    
    if (@_) {
        my %handler = @_;
        return bless \%handler, $pkg;
    } else {
        return $pkg->defaultHandler;
    }
}

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

sub defaultHandler {
    my( $pkg ) = @_;
    
    return bless {

             ID => 'Hum::EMBL::ID',
             AC => 'Hum::EMBL::AC',
             SV => 'Hum::EMBL::SV',
             NI => 'Hum::EMBL::NI',
             DT => 'Hum::EMBL::DT',
             DE => 'Hum::EMBL::DE',
             KW => 'Hum::EMBL::KW',
             OS => 'Hum::EMBL::Organism',
             OC => 'Hum::EMBL::Organism',
             OG => 'Hum::EMBL::OG',
             RN => 'Hum::EMBL::Reference',
             RC => 'Hum::EMBL::Reference',
             RP => 'Hum::EMBL::Reference',
             RX => 'Hum::EMBL::Reference',
             RA => 'Hum::EMBL::Reference',
             RT => 'Hum::EMBL::Reference',
             RL => 'Hum::EMBL::Reference',
             DR => 'Hum::EMBL::DR',
             FH => 'Hum::EMBL::FH',
             FT => 'Hum::EMBL::FT',
             CC => 'Hum::EMBL::CC',
             XX => 'Hum::EMBL::XX',
             SQ => 'Hum::EMBL::Sequence',
           '  ' => 'Hum::EMBL::Sequence',
           '//' => 'Hum::EMBL::End',

    }, $pkg;
}

sub class {
    my( $handler, $prefix ) = @_;
    
    return $handler->{$prefix};
}

sub parse {
    my( $handler, $fh ) = @_;
    
    my( $current, @group, @obj );
    while (<$fh>) {
    
        # Get prefix and trim whitespace from the right
        my ($prefix) = /^(.{2,5})/;
        $prefix =~ s/(..+?)\s+$/$1/;
        
        # This ignores lines which aren't registered in the handler
        if (my $class = $handler->class( $prefix )) {
                
            $current ||= $class; # Needed for first line
            
            if ($current eq $class) {
                # Add to the group if belongs to same class
                push( @group, $_ );
            } else {
                # Make new line object(s) if current line belongs to a
                # different class, and add to the list of objects.
                my @line = $current->store(@group);
                warn $@ if $@;
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
        my $entry = Hum::EMBL::Entry->new();
        $entry->handler( $handler );
        $entry->lines( \@obj );
        return $entry;
    } else {
        return;
    }
}

###############################################################################

package Hum::EMBL::Entry;

use strict;
use Carp;
use Hum::EMBL::Line;

sub compose {
    my( $entry ) = @_;
    
    my( @compose );
    foreach my $line ($entry->lines()) {
        push( @compose, $line->toString() );
    }
    return @compose;
}


sub new {
    my( $pkg ) = @_;
    
    my $entry = bless {
        _handler => undef,
        _lines    => [],
    }, $pkg;
}

sub lines {
    my( $entry, $lines ) = @_;
    
    if ($lines) {
        foreach (@$lines) { $_->entry($entry); }
        $entry->{'_lines'} = $lines;
    } else {
        return @{$entry->{'_lines'}};
    }
}

{
    my %seen;

    sub handler {
        my( $entry, $handler ) = @_;

        if ($handler) {
        
            unless ($seen{$handler}) {
                my $entry_pack = ref($entry);

                # Generate access methods for each line type package,
                # giving them the same name as the package.
                my %packages = map {$_, 1} values %$handler;
                foreach my $class (keys %packages) {
                    my ($name) = $class =~ /([^:]+)$/;

                    # Don't redefine existing subroutines
                    my $func = "${entry_pack}::$name";
                    if (defined( &$func )) {
                        confess "sub '$func' already defined";
                    } else {
                        no strict 'refs';
                        *$func = sub {
                            my( $entry ) = @_;

                            my @lines = grep { ref($_) eq $class } $entry->lines();

                            if (wantarray) {
                                return @lines;
                            } else {
                                confess "No line types from '$class' class in entry" unless @lines;
                                return $lines[0];
                            }
                        }
                    }

                    # Define functions so can say $entry->newCC
                    my $newFunc = "${entry_pack}::new$name";
                    if (defined( &$newFunc )) {
                        confess "sub '$newFunc' already defined";
                    } else {
                        no strict 'refs';
                        *$newFunc = sub {
                            my $pkg = shift;
                            return $class->new(@_);
                        }
                    }
                }
                $seen{$handler} = 1;
            }

            $entry->{'_handler'} = $handler;
        } else {
            return $entry->{'_handler'};
        }
    }
}

1;
