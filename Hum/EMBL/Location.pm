
package Hum::EMBL::Location;

use Carp;
use strict;

sub new {
    my( $pkg ) = @_;
    
    return bless {
        strand => undef,
        exons => [],
        missing_5_prime => undef,
        missing_3_prime => undef,
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
    
    if ($value) {
        $loc->{'missing_5_prime'} = $value;
    } else {
        return $loc->{'missing_5_prime'};
    }
}
sub missing_3_prime {
    my( $loc, $value ) = @_;
    
    if ($value) {
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

sub parse {
    my( $loc, $s ) = @_;
    
    if ($$s =~ /complement/) {
        $loc->strand('C');
    } else {
        $loc->strand('W');
    }
    
    $loc->missing_5_prime if $loc =~ /</;
    $loc->missing_3_prime if $loc =~ />/;
    
    my( @exons );
    while ($$s =~ /(\d+)\.\.(\d+)/g) {
        push( @exons, [$1, $2] );
    }
    if (@exons) {
        $loc->exons(@exons);
    } elsif (my ($i) = $$s =~ /(\d+)/) {
        # Single base pair
        $loc->exons($i);
    } else {
        confess "Can't parse location string '$$s'";
    }
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
            $text = 'join('. join(',', map "$_->[0]..$_->[1]", @exons) .')';
        } else {
            $text = $exons[0];
            if ($loc->missing_5_prime) {
                $text = "<$text";
            } elsif ($loc->missing_3_prime) {
                $text = ">$text";
            }
        }

        if ($loc->strand eq 'C') {
            $text = "complement($text)";
        }

        my( @lines );
        while ($text =~ /(.{1,58}(,|$))/g) {
            push(@lines, $1);
        }

        return join($joiner, @lines) ."\n";
    }
}

1;

__END__

