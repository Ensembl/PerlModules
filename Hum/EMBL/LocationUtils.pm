
package Hum::EMBL::LocationUtils;

use Carp;
use strict;
use Exporter;
use vars qw( @ISA @EXPORT_OK );
use Hum::EMBL::Location;
@ISA = qw( Exporter );
@EXPORT_OK = qw( simple_location
                 location_from_homol_block
                 location_from_subsequence );

sub numeric_ascend {
    $a->[1] <=> $b->[1];
}

sub numeric_descend {
    $b->[1] <=> $a->[1];
}

sub simple_location {
    my( $start, $end ) = @_;
    
    foreach ($start, $end) {
        confess "Non-integer argument" unless /^\d+$/;
    }
    
    my $loc = Hum::EMBL::Location->new;
    if ($start < $end) {
        $loc->strand('W');
        $loc->exons([$start,$end]);
    } elsif ($start > $end) {
        $loc->strand('C');
        $loc->exons([$end,$start]);
    } elsif ($start == $end) {
        $loc->strand('C');
        $loc->exons($start);
    }
    return $loc;
}

sub location_from_homol_block {
    my( $block, $score, $merge ) = @_;
    $score ||= 200;
        
    # Divide the data up into forward and reverse strand sets
    my( %strand );
    foreach my $r (@$block) {
        my( $score, $g_start, $g_end, $h_start, $h_end ) = @$r;
        my( @coord );
        
        my( $g_dir, $h_dir );
        if ($g_start < $g_end) {
            $g_dir = 1;
            push( @coord, $g_start, $g_end );
        } else {
            $g_dir = 0;
            push( @coord, $g_end, $g_start );
        }
        if ($h_start < $h_end) {
            $h_dir = 1;
            push( @coord, $h_start, $h_end );
        } else {
            $h_dir = 0;
            push( @coord, $h_end, $h_start );
        }
        
        if ($g_dir == $h_dir) {
            push( @{$strand{'W'}}, [$score, @coord] );
        } else {
            push( @{$strand{'C'}}, [$score, @coord] );
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
        my $loc = Hum::EMBL::Location->new;
        $loc->strand($strand);
        $loc->exons(@exons);
        push( @result, $loc );
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

# Frist argument is a feature object
# Second argument is the subsequence tag in the parent Ace sequence
sub location_from_subsequence {
    my( $ft, $sub_tag ) = @_;
    
    # Get the start and end coordinates
    my($start, $end) = map $_->name, $sub_tag->row(1);

    # Fetch the object from the database
    my $g = $sub_tag->fetch;

    # Create the location string
    my(@exons);
    foreach ($g->at('Structure.From.Source_exons[1]')) {
        my ($x, $y) = $_->row;
        push(@exons, [$x->name, $y->name]);
    }
    
    my $loc = 'Hum::EMBL::Location'->new;
    
    if ($start < $end) {
        $loc->strand('W');
        # Sort exons ascending by their starts
        @exons = sort { $a->[0] <=> $b->[0] } @exons;
        foreach my $e (@exons) {
            foreach (@$e) {
                $_ = $start - 1 + $_;
            }
        }
    } elsif ($start > $end) {
        $loc->strand('C');
        # Sort exons descending by their ends
        @exons = sort { $b->[1] <=> $a->[1] } @exons;
        foreach my $e (@exons) {
            my( $x, $y ) = @$e;
            foreach ($x, $y) {
                $_ = $start + 1 - $_;
            }
            $e = [$y, $x];
        }
    } else {
        confess("Can't get order from $start - $end");
    }
    
    $loc->exons(@exons);

    # Add start not found, and codon offset if specified
    my( $s_n_f, $codon_start );
    eval{ ($s_n_f, $codon_start) = map "$_", $g->at('Properties.Start_not_found')->row() };
    if ($s_n_f) {
        $loc->start_not_found;
        $codon_start ||= 1;
    }
    if ($codon_start and $g->at('Properties.Coding.CDS')) {
        unless ($codon_start =~ /^[123]$/) {
            confess("Bad codon start ('$codon_start') in '$g'");
        }
        $ft->addQualifierStrings('codon_start', $codon_start);
    }

    # Add end not found
    if ($g->at('Properties.End_not_found')) {
        $loc->end_not_found;
    }

    # Store the new location
    $ft->location( $loc );
    
    return ($start, $end);
}

1;

__END__

