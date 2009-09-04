
package Hum::EMBL::Location;

use Carp;
use strict;
use warnings;

sub new {
    my( $pkg ) = @_;
    
    return bless {
        strand => undef,
        exons => [],
        missing_5_prime => 0,
        missing_3_prime => 0,
    }, $pkg;
}

# Storage methods
sub strand {
    my( $loc, $value ) = @_;
    
    if ($value) {
        $loc->{'strand'} = $value;
    } else {
        return $loc->{'strand'};
    }
}
sub missing_5_prime {
    my( $loc, $value ) = @_;
    
    if (defined $value) {
        $loc->{'missing_5_prime'} = $value;
    } else {
        return $loc->{'missing_5_prime'};
    }
}
sub missing_3_prime {
    my( $loc, $value ) = @_;
    
    if (defined $value) {
        $loc->{'missing_3_prime'} = $value;
    } else {
        return $loc->{'missing_3_prime'};
    }
}
sub exons {
    my( $loc, @exons ) = @_;
    
    if (@exons) {
        $loc->{'exons'} = [@exons];
    } else {
        return @{$loc->{'exons'}};
    }
}

sub start_not_found {
    my( $loc ) = @_;
    
    if ($loc->strand eq 'W') {
        $loc->missing_5_prime(1);
    } elsif ($loc->strand eq 'C') {
        $loc->missing_3_prime(1);
    } else {
        confess "Direction not specified";
    }
}
sub end_not_found {
    my( $loc ) = @_;
    
    if ($loc->strand eq 'W') {
        $loc->missing_3_prime(1);
    } elsif ($loc->strand eq 'C') {
        $loc->missing_5_prime(1);
    } else {
        confess "Direction not specified";
    }
}

sub start {
    my( $loc ) = @_;
    
    return $loc->strand eq 'W' ? $loc->five_prime : $loc->three_prime;
}
sub end {
    my( $loc ) = @_;
    
    return $loc->strand eq 'W' ? $loc->three_prime : $loc->five_prime;
}

sub length {
    my( $loc ) = @_;
    
    return $loc->three_prime - $loc->five_prime + 1;
}

sub five_prime {
    my( $loc ) = @_;
    
    if (my $x = $loc->{'exons'}[0]) {
        return ref($x) ? $x->[0] : $x;
    } else {
        confess "No start position";
    }
}
sub three_prime {
    my( $loc ) = @_;
    
    if (my $x = $loc->{'exons'}[-1]) {
        return ref($x) ? $x->[1] : $x;
    } else {
        confess "No end position";
    }
}

sub parse {
    my( $loc, $s ) = @_;
    
    # If the location contains multiple complement
    # tags, then the order of the exons will need
    # to be reversed
    my $C_count = 0;
    while ($$s =~ /complement/g) {
        $C_count++;
    }
    if ($C_count) {
        $loc->strand('C');
    } else {
        $loc->strand('W');
    }
    
    $loc->missing_5_prime(1) if $$s =~ /</;
    $loc->missing_3_prime(1) if $$s =~ />/;
    
    my( @exons );
    while ($$s =~ /(\d+)\.\.>?(\d+)/g) {
        push( @exons, [$1, $2] );
    }
    if (@exons) {
        if ($C_count > 1) {
            @exons = reverse @exons;
        }
        $loc->exons(@exons);
    } elsif (my ($i) = $$s =~ /(\d+)/) {
        # Single base pair
        $loc->exons($i);
    } else {
        confess "Can't parse location string '$$s'";
    }
}

# Generates a unique string for a location
sub hash_key {
    my( $loc ) = @_;
    
    my( @key );
    if (ref($loc->{'exons'}[0])) {
        @key = map @$_, @{$loc->{'exons'}};
    } else {
        @key = @{$loc->{'exons'}};
    }
    
    return join '_', ($loc->{'strand'}, @key,
        $loc->{'missing_5_prime'},
        $loc->{'missing_3_prime'});
}

BEGIN {
    my $joiner = "\nFT". ' ' x 19;

    sub compose {
        my( $loc ) = @_;

        my( @exons ) = $loc->exons;

        my( $text );
        if (ref $exons[0]) {
            if ($loc->missing_5_prime) {
                my $i = $exons[0][0];
                $exons[0][0] = "<$i";
            }
            if ($loc->missing_3_prime) {
                my $i = $exons[$#exons][1];
                $exons[$#exons][1] = ">$i";
            }
            
            if (@exons == 1) {
                $text = "$exons[0][0]..$exons[0][1]";
            } else {
                $text = 'join('. join(',', map "$_->[0]..$_->[1]", @exons) .')';
            }
        } else {
            $text = $exons[0];
            if ($loc->missing_5_prime) {
                $text = "<$text";
            } elsif ($loc->missing_3_prime) {
                $text = ">$text";
            }
        }

        my $strand = $loc->strand;
        if ($strand eq 'C') {
            $text = "complement($text)";
        } else {
            confess "Strand='$strand'"
                unless $strand eq 'W';
        }

        my( @lines );
        while ($text =~ /(.{1,58}(,|$))/g) {
            push(@lines, $1);
        }

        return join($joiner, @lines) ."\n";
    }
}

sub add_location_qualifier {
    my( $loc, $qualifier ) = @_;
    
    $loc->{'_location_qualifers'} ||= [];
    push(@{$loc->{'_location_qualifers'}}, $qualifier);
}

sub location_qualifiers {
    my( $loc ) = @_;
    
    if (my $q = $loc->{'_location_qualifers'}) {
        return @$q;
    } else {
        return;
    }
}

1;

__END__

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>

