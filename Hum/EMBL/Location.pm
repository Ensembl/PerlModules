
package Hum::EMBL::Location;
use Carp;
use strict;
use Exporter;
use vars qw( @ISA @EXPORT_OK );
@ISA = qw( Exporter );
@EXPORT_OK = qw( simple_location locationFromHomolBlock );

sub new {
    my( $pkg, $strand, @exons ) = @_;
    
    my $loc = bless [], $pkg;
    
    if ($strand) {
        $loc->strand($strand);
    }
    if (@exons) {
        $loc->exons(@exons);
    }
    
    return $loc;
}

sub strand {
    my( $loc, $strand ) = @_;
    
    if ($strand) {
        confess "strand must be 'W' or 'C', not '$strand'"
            unless $strand =~ /^[WC]$/;
        $loc->[0] = $strand;
    } else {
        return $loc->[0];
    }
}

sub exons {
    my( $loc, @exons ) = @_;
    
    if (@exons) {
        foreach (@exons) {
            confess "Bad exon string '$_'" unless /^\d+\.\.\d+$/;
        }
        @$loc = ($loc->[0], @exons);
    } else {
        return @$loc[1..$#$loc];
    }
}

sub numeric_ascend {
    $a->[1] <=> $b->[1];
}

sub numeric_descend {
    $b->[1] <=> $a->[1];
}

sub locationFromHomolBlock {
    my( $block, $score, $merge ) = @_;
    $score ||= 200;
        
    # Divide the data up into forward and reverse strand sets
    my( %strand );
    foreach my $r (@$block) {
        my( $score, $g_start, $g_end, $h_start, $h_end ) = @$r;
        
        if ($g_start < $g_end) {
            push( @{$strand{'W'}}, [$score, $g_start, $g_end, $h_start, $h_end] );
        } else {
            push( @{$strand{'C'}}, [$score, $g_end, $g_start, $h_start, $h_end] );
        }
    }
    
    my( @set );
    
    # Divide each strand's set into hit blocks
    foreach my $str (keys %strand) {    
        my( @bits );
        my $pos = undef;
        my $dir = undef;
        
        # Need to sort matches in opposite directions for different strands
        my( $sort_func );
        if ($str eq 'W') {
            $sort_func = \*numeric_ascend;
        } else {
            $sort_func = \*numeric_descend;
        }
        
        foreach my $r (sort $sort_func @{$strand{$str}}) {            
            # Get the direction of the match in the database hit
            my $d = $r->[3] < $r->[4] ? 1 : 0;
            $dir = $d unless defined $dir;
            
            # The end of the match is in a different field,
            # depending upon the direction.
            my $p = $d ? $r->[4] : $r->[3];
            $pos = $p unless defined $pos;
            
            # Data belongs in a new set if the direction is
            # different to $dir or the position doesn't follow
            # on from the previous position ($pos).
            if (             ($d != $dir)
                or (  $d and ($p < $pos))
                or (! $d and ($p > $pos)) ) {
                push( @set, [$str, @bits] );
                @bits = ();
                $dir = $d; # Set the new direction
            }
            $pos = $p; # Record the new end
            push( @bits, $r );
        }
        push( @set, [$str, @bits] );
    }
    
    my( @result );
    foreach my $s (@set) {
        my( $strand, @data ) = @$s;
        
        # Skip this set if its score isn't significant
        my( $sum );
        map { $sum += $_->[0] } @data;
        next unless $sum >= $score;
        
        @data = sort numeric_ascend @data;
        
        # Make a location string
        my @exons = map [ $_->[1], $_->[2] ], @data;
        @exons = merge_ranges($merge, @exons);
        my $loc = Hum::EMBL::Location->new($strand, map "$_->[0]..$_->[1]", @exons);
        my $str = $loc->format_location();
        
        # Get the start and end of the feature
        my $start = @data[0]->[1];
        my $end   = @data[$#data]->[2];
        push( @result, [$start, $end, $str] );
    }
    return @result;
}

sub merge_ranges {
    my $merge = shift;
    my @ranges = sort {$a->[0] <=> $b->[0]} @_;
    
    $merge ||= 0;
    
    my($start, $end, @fused);

    $start = $ranges[0]->[0];
    foreach my $ra (@ranges) {
        my( $s, $e ) = @$ra;
        
        # Make a new range, unless this one almost
        # overlaps the previous.
        if (defined($end) and not (($s - $merge) <= $end)) {
            push(@fused, [$start, $end]);
            $start = $s;
        }
        $end   = $e;
    }
    return(@fused, [$start, $end]);
}

sub simple_location {
    my( $start, $end ) = @_;
    
    foreach ($start, $end) {
        confess "Non-integer argument" unless /^\d+$/;
    }
    
    if ($start < $end) {
        return "$start..$end";
    } elsif ($start > $end) {
        return "complement($end..$start)";
    } elsif ($start == $end) {
        return $start;
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
    $loc->[$#$loc] =~ s/(\d+)\.\.(\d+)/$1\.\.>$2/;
}

sub format_location {
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

