
package Hum::EMBL::LocationUtils;

use Carp;
use strict;
use warnings;
use Exporter;
use vars qw( @ISA @EXPORT_OK );
use Hum::EMBL::Location;
@ISA = qw( Exporter );
@EXPORT_OK = qw( simple_location
                 location_from_homol_block
                 locations_from_subsequence );

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
        $loc->strand('W');
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
sub locations_from_subsequence {
    my( $sub_tag ) = @_;
    
    # Get the start and end coordinates
    my($start, $end) = map $_->name, $sub_tag->row(1);
    confess "Missing coordinate for '$sub_tag' : start='$start', end='$end'"
        unless $start and $end;

    # Fetch the object from the database
    my $g = $sub_tag->fetch;

    # Create the location string
    my( @exons );
    foreach ($g->at('Structure.From.Source_exons[1]')) {
        my ($x, $y) = $_->row;
        push(@exons, [$x->name, $y->name]);
    }
    confess "No exons found for '$sub_tag'" unless @exons;
    
    # Is it coding?
    my $CDS = $g->at('Properties.Coding.CDS');
    
    # Get the CDS coordinates if it is a new-style combined CDS-mRNA
    my @cds_coords = map $_->name, $CDS->row(1) if $CDS;
    my( @cds_exons );
    if (@cds_coords == 2) {
        @cds_exons = CDS_exons_from_mRNA_exons(@cds_coords, @exons);
        
        # Check for CDS with no UTR (in which case we
        # don't make an mRNA Location).
        if (@cds_exons == @exons
            and $cds_exons[0][0]           == $exons[0][0]
            and $cds_exons[$#cds_exons][1] == $exons[$#exons][1])
        {
            @cds_exons = ();
        }
    }
    elsif (@cds_coords) {
        confess("In '$sub_tag' expecting 2 CDS coordinates, got: (",
            join(', ', map "'$_'", @cds_coords),
            ")");
    }
    
    my( $cds_loc, $mrna_loc );
    if (@cds_exons) {
        # New style combined object generates both CDS and mRNA
        $cds_loc  = location_from_ace_coordinates($start, $end, @cds_exons);
        $mrna_loc = location_from_ace_coordinates($start, $end, @exons);
    }
    elsif ($CDS) {
        # CDS is set, so make CDS
        $cds_loc  = location_from_ace_coordinates($start, $end, @exons);
    }
    else {
        # Not coding so make mRNA
        $mrna_loc = location_from_ace_coordinates($start, $end, @exons);
    }

    # Add start not found, and codon offset if specified
    my $s_n_f = $g->at('Properties.Start_not_found');
    my( $codon_start );
    if ($s_n_f) {
         $cds_loc->start_not_found if $cds_loc;
        $mrna_loc->start_not_found if $mrna_loc;
        ($codon_start) = map $_->name, $s_n_f->row(1);
        $codon_start ||= 1;
    }

    # Will the FT object need a codon_start qualifier?
    if ($codon_start and $cds_loc) {
        unless ($codon_start =~ /^[123]$/) {
            confess("Bad codon start ('$codon_start') in '$g'");
        }
            
        my $q = 'Hum::EMBL::Qualifier'->new;
        $q->name('codon_start');
        $q->value($codon_start);
        $cds_loc->add_location_qualifier($q);
    }

    # Add end not found
    if ($g->at('Properties.End_not_found')) {
         $cds_loc->end_not_found if $cds_loc;
        $mrna_loc->end_not_found if $mrna_loc;
    }
    
    return ($mrna_loc, $cds_loc);
}

sub location_from_ace_coordinates {
    my( $start, $end, @exons ) = @_;

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
    return $loc;
}

sub CDS_exons_from_mRNA_exons {
    my $cds_start = shift;
    my $cds_end   = shift;
    
    # Make a copy of all the coordinate pairs given
    my @mrna_exons = map [@$_], @_
        or confess "No mrna_exons given";
    
    my $cds_pos = 0;    # Position in transcript (sum of previous exon lengths)
    my $in_translation_zone = 0;
    my( @cds_exons );
    foreach my $ex (@mrna_exons) {
        my $ex_length = $ex->[1] - $ex->[0] + 1;
        my $new_cds_pos = $cds_pos + $ex_length;

        if ( ! $in_translation_zone and $new_cds_pos >= $cds_start) {
            # Translation starts in this exon
            $in_translation_zone = 1;
            $ex->[0] += $cds_start - $cds_pos - 1;
        }
        
        # Add the exon to the list if it is translated
        push(@cds_exons, $ex) if $in_translation_zone;
        
        if ($in_translation_zone and $new_cds_pos >= $cds_end) {
            # Translation ends in this exon
            $in_translation_zone = 0;
            $ex->[1] -= $cds_pos + $ex_length - $cds_end;
        }
        
        # Exit the loop if we're beyond the translated region
        last if @cds_exons and ! $in_translation_zone;
        $cds_pos = $new_cds_pos;
    }
    
    return @cds_exons;
}

1;

__END__

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>

