
package Hum::EMBL::Location;
use Carp;
use strict;
use Exporter;
use vars qw( @ISA @EXPORT_OK );
@ISA = qw( Exporter );
@EXPORT_OK = qw( simple_location );

sub simple_location {
    my( $start, $end ) = @_;
    
    if ($start < $end) {
        return "$start..$end";
    } elsif ($start > $end) {
        return "complement($end..$start)";
    } else {
        confess("Can't get order from $start - $end");
    }
}

sub newFromFeature {
    my( $pkg, $start, $end ) = @_;
    
    if ($start < $end) {
        return( bless [ 'W', "$start..$end" ], $pkg );
    } elsif ($start > $end) {
        return( bless [ 'C', "$end..$start" ], $pkg );
    } else {
        confess("Can't get order from $start - $end");
    }
}

sub newFromSubsequence {
    my( $pkg, $start, $end, @exons ) = @_;
    my( @location, $direction );
    
    if ($start < $end) {
        $direction = 'W';
        # Sort exons ascending by their starts
        @exons = sort { $a->[0] <=> $b->[0] } @exons;
        foreach my $e (@exons) {
            my( $x, $y ) = @$e;
            $x = $start - 1 + $x;
            $y = $start - 1 + $y;
            push( @location, "$x..$y" );
        }
    } elsif ($start > $end) {
        $direction = 'C';
        # Sort exons descending by their ends
        @exons = sort { $b->[1] <=> $a->[1] } @exons;
        foreach my $e (@exons) {
            my( $y, $x ) = @$e;
            $x = $start + 1 - $x;
            $y = $start + 1 - $y;
            push( @location, "$x..$y" );
        }
    } else {
        confess("Can't get order from $start - $end");
    }
    return( bless [ $direction, @location ], $pkg );
}

sub start_not_found {
    my( $loc ) = @_;
    if ($loc->[0] eq 'W') {
        $loc->_five_prime_arrow();
    } else {
        $loc->_three_prime_arrow();
    }
}

sub end_not_found {
    my( $loc ) = @_;
    if ($loc->[0] eq 'W') {
        $loc->_three_prime_arrow();
    } else {
        $loc->_five_prime_arrow();
    }
}

sub _five_prime_arrow {
    my( $loc ) = @_;
    $loc->[1] = "<$loc->[1]";
}

sub _three_prime_arrow {
    my( $loc ) = @_;
    $loc->[$#$loc] = "$loc->[$#$loc]>";
}

sub format {
    my( $location ) = @_;
    my( $direction, @exons ) = @$location;
    my $loc_string;
    if (@exons > 1) {
        $loc_string = 'join('. join( ',', @exons) .')';
    } else {
        $loc_string = $exons[0];
    }
    if ($direction eq 'W') {
        return $loc_string;
    } else {
        return 'complement('. $loc_string .')';
    }
}

1;

__END__

