
### Hum::Analysis::Factory::SequenceOverlap

package Hum::Analysis::Factory::SequenceOverlap;

use strict;
use Carp;
use Hum::Analysis::Factory::CrossMatch;
use Hum::SequenceOverlap;
use Symbol 'gensym';

my( %end_distances );

foreach my $name_meths (
    [qw{ seq seq_start seq_end }],
    [qw{ hit hit_start hit_end }])
{
    my( $type, $start_method, $end_method ) = @$name_meths;
    $end_distances{$type} = sub {
            my( $feat, $length ) = @_;
            my $distance_from_start = $feat->$start_method() - 1;
            my $distance_to_end = $length - $feat->$end_method();
            return($distance_from_start, $distance_to_end);
        }
}

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub matches_file {
    my( $self, $file ) = @_;
    
    if ($file) {
        $self->{'_matches_file'} = $self->_open_file($file);
    }
    return $self->{'_matches_file'};
}

sub overlap_alignment_file {
    my( $self, $file ) = @_;
    
    if ($file) {
        $self->{'_overlap_alignment_file'} = $self->_open_file($file);
    }
    return $self->{'_overlap_alignment_file'};
}

sub _open_file {
    my( $self, $file ) = @_;
    
    my $type = ref($file);
    unless ($type and $type eq 'GLOB') {
        my $fh = gensym();
        open $fh, "> $file"
            or die "Can't write to '$file' : $!";
        $file = $fh;
    }
    return $file;
}

sub find_SequenceOverlap {
    my( $self, $sinf_a, $sinf_b ) = @_;
    
    my $seq_a = $sinf_a->Sequence;
    my $seq_b = $sinf_b->Sequence;
    unless ($seq_a and $seq_b) {
        confess "Didn't get Sequence for both a ('$seq_a') and b ('$seq_b')";
    }
    
    # Run cross_match and find overlap
    my $feat = $self->find_end_overlap($seq_a, $seq_b);
    
    return unless $feat;
    
    if (my $over_fh = $self->overlap_alignment_file) {
        print $over_fh
            $feat->pretty_header,
            $feat->pretty_string,
            $feat->alignment_string;
    }
    
    # Convert into a SequenceOverlap object that
    # can be written into the tracking database.
    return $self->make_SequenceOverlap($sinf_a, $sinf_b, $feat);
}

sub make_SequenceOverlap {
    my ($self, $sa, $sb, $feat) = @_;

    my $overlap = Hum::SequenceOverlap->new;
    # Copy the percent sub, ins, del
    foreach my $meth (qw{ percent_substitution percent_insertion percent_deletion }) {
        $overlap->$meth($feat->$meth());
    }
    $overlap->source_name('CrossMatch');
    
    my ($pos_a, $pos_b) = $overlap->make_new_Position_objects;
    $pos_a->SequenceInfo($sa);
    $pos_b->SequenceInfo($sb);
    $pos_a->is_3prime($self->is_three_prime_hit($feat, $sa->sequence_length, 'seq'));
    $pos_b->is_3prime($self->is_three_prime_hit($feat, $sb->sequence_length, 'hit'));
    
    if ($feat->hit_length > $feat->seq_length) {
        # More unusual "upstairs" overlap which is only chosen
        # where the length of overlap on the hit is longer
        $overlap->overlap_length($feat->hit_length);
        if ($pos_a->is_3prime) {
            $pos_a->position($feat->seq_start - 1);
        } else {
            $pos_a->position($feat->seq_end + 1);
        }
        if ($pos_b->is_3prime) {
            $pos_b->position($feat->hit_end);
        } else {
            $pos_b->position($feat->hit_start);
        }
    } else {
        # The usual "downstairs" overlap (ie: most clones
        # in the golden path begin at 2001 or 101).
        $overlap->overlap_length($feat->seq_length);
        if ($pos_a->is_3prime) {
            $pos_a->position($feat->seq_end);
        } else {
            $pos_a->position($feat->seq_start);
        }        
        if ($pos_b->is_3prime) {
            $pos_b->position($feat->hit_start - 1);
        } else {
            $pos_b->position($feat->hit_end + 1);
        }
    }
    
    # Check that the positions calculated aren't
    # off the end of the sequences.
    $overlap->validate_Positions;
    
    return $overlap;
}

sub is_three_prime_hit {
    my( $self, $feat, $length, $type ) = @_;
    
    my( $start_dist, $end_dist ) = $end_distances{$type}->($feat, $length);
    return $start_dist < $end_dist ? 0 : 1;
}

sub find_end_overlap {
    my( $self, $query, $subject ) = @_;
    
    my $matches_fh = $self->matches_file;
    
    my $factory = Hum::Analysis::Factory::CrossMatch->new;
    $factory->show_alignments($matches_fh or $self->overlap_alignment_file ? 1 : 0);
    $factory->show_all_matches(1);
    my $parser = $factory->run($query, $subject);
    
    my( @matches );
    while (my $m = $parser->next_Feature) {
        push(@matches, $m);
    }
    
    if ($matches_fh) {
        print $matches_fh "\n";
        foreach my $seq ($query, $subject) {
            printf $matches_fh "%22s  %10d bp\n", $seq->name, $seq->sequence_length;
        }
        print $matches_fh "\n", $matches[0]->pretty_header, "\n";
        print $matches_fh map $_->pretty_string, @matches;
    }
    
    # I don't think we need to sort
    #@matches = sort {
    #    $a->seq_start  <=> $b->seq_start  ||
    #    $a->seq_end    <=> $b->seq_end    ||
    #    $a->seq_strand <=> $b->seq_strand
    #    } @matches;
    
    my $seq_end = $self->closest_end_best_pid(  $query->sequence_length, $end_distances{'seq'}, @matches);
    my $hit_end = $self->closest_end_best_pid($subject->sequence_length, $end_distances{'hit'}, @matches);
    
    $self->warn_match($query, $subject, $seq_end, $hit_end);
    
    unless ($seq_end and $hit_end) {
        confess "No end overlap found\n";
    }
    elsif ($seq_end == $hit_end) {
        return $seq_end;
    } else {
        # If the end features overlap on either sequence
        # then choose the feature that is closest to the
        # ends of both sequences.
        if ($seq_end->seq_overlaps($hit_end) or $seq_end->hit_overlaps($hit_end)) {
            return $self->choose_feature_lowest_end_distance(
                $query->sequence_length, $seq_end,
              $subject->sequence_length, $hit_end,
              );
        } else {
            # There is a gap between feartures, so merge them
            # to produce a single feature.
            return $self->merge_features($seq_end, $hit_end);
        }
    }
}

sub choose_feature_lowest_end_distance {
    my( $self, $seq_length, $seq_end, $hit_length, $hit_end ) = @_;
    
    my $seq_distance = $self->min_end_distance($seq_end, $seq_length, $hit_length);
    my $hit_distance = $self->min_end_distance($hit_end, $seq_length, $hit_length);
    return $seq_distance < $hit_distance ? $seq_end : $hit_end;
}

sub min_end_distance {
    my( $self, $feat, $seq_length, $hit_length ) = @_;
    
    my @seq_dist = $end_distances{'seq'}->($feat, $seq_length);
    my @hit_dist = $end_distances{'hit'}->($feat, $hit_length);
    
    my $min_seq = $seq_dist[0] < $seq_dist[1] ? $seq_dist[0] : $seq_dist[1];
    my $min_hit = $hit_dist[0] < $hit_dist[1] ? $hit_dist[0] : $hit_dist[1];
    return $min_seq + $min_hit;
}

sub warn_match {
    my( $self, $query, $subject, $seq_end, $hit_end ) = @_;
    
    printf STDERR "%s (%d) vs %s (%d)\n",
          $query->name,   $query->sequence_length,
        $subject->name, $subject->sequence_length;
    
    my @feat = ($seq_end);
    push(@feat, $hit_end) unless $seq_end == $hit_end;
    
    foreach my $feat (@feat) {
        printf(STDERR "  %7.3f%% %16s %6d %6d %16s %6d %6d     %3s\n",
            $feat->percent_identity,
            $feat->seq_name,
            $feat->seq_start,
            $feat->seq_end,
            $feat->hit_name,
            $feat->hit_start,
            $feat->hit_end,
            ($feat->hit_strand == 1 ? 'Fwd' : 'Rev'),
            );
    }
    
}

sub merge_features {
    my( $self, $seq, $hit ) = @_;
    
    if ($seq->hit_strand != $hit->hit_strand) {
        confess "Features are on opposite strands of hit";
    }

    my $new_feat = ref($seq)->new;
    $new_feat->seq_name($seq->seq_name);
    $new_feat->hit_name($seq->hit_name);
    $new_feat->hit_strand($seq->hit_strand);
    
    # Choose the smallest start and largest end coordinates
    # from either the sequence or hit feature.
    $new_feat->seq_start($seq->seq_start < $hit->seq_start ? $seq->seq_start : $hit->seq_start);
    $new_feat->seq_end  ($seq->seq_end   > $hit->seq_end   ? $seq->seq_end   : $hit->seq_end  );
    $new_feat->hit_start($seq->hit_start < $hit->hit_start ? $seq->hit_start : $hit->hit_start);
    $new_feat->hit_end  ($seq->hit_end   > $hit->hit_end   ? $seq->hit_end   : $hit->hit_end  );
    
    foreach my $perc (qw{ percent_substitution percent_insertion percent_deletion }) {
        my $seq_count = $seq->seq_length * ($seq->$perc() / 100);
        my $hit_count = $hit->seq_length * ($hit->$perc() / 100);
        my $percent = 100 * (($seq_count + $hit_count) / ($seq->seq_length + $hit->seq_length));
        $new_feat->$perc($percent);
    }
    
    # Add the length of the gap between the two features
    # into the percent_insertion figure.
    my ($gap_type, $gap_length) = $self->gap_between_features($seq, $hit);
    warn "GAP: $gap_type, $gap_length\n";
    my $ins_count = $new_feat->seq_length * ($seq->percent_insertion / 100);
    $ins_count += $gap_length;
    my $percent = 100 * ($ins_count / $new_feat->seq_length);
    $new_feat->percent_insertion($percent);
    
    if ($seq->alignment_string) {
        my @sort = sort {$a->seq_start <=> $b->seq_start} ($seq, $hit);
        $new_feat->alignment_string(
            $sort[0]->alignment_string
            . "\n"
            . " " x 12 . ">" x 20 . "  GAP OF LENGTH $gap_length  " . "<" x 20
            . "\n\n"
            . $sort[1]->alignment_string
            );
    }
    
    return $new_feat;
}

sub gap_between_features {
    my( $self, $fa, $fb ) = @_;
    
    if ($fa->seq_start > $fb->seq_start) {
        ($fa, $fb) = ($fb, $fa);
    }
    my $seq_gap = $fb->seq_start - $fa->seq_end - 1;

    if ($fa->hit_start > $fb->hit_start) {
        ($fa, $fb) = ($fb, $fa);
    }
    my $hit_gap = $fb->hit_start - $fa->hit_end - 1;

    my( $gap, $type );
    if ($seq_gap > $hit_gap) {
        $type = 'seq';
        $gap = $seq_gap;
    } else {
        $type = 'hit';
        $gap = $hit_gap;
    }

    if ($gap > 0) {
        return($type, $gap);
    } else {
        return;
    }
}

sub closest_end_best_pid {
    my( $self, $length, $ends_method, @matches ) = @_;
    
    my( $closest, $closest_distance );
    foreach my $feat (@matches) {
        my ($distance_from_start, $distance_to_end) = $ends_method->($feat, $length);
        #warn "d.start = $distance_from_start  d.end = $distance_to_end\n";
        #my $distance_from_start = $feat->$start_method() - 1;
        #my $distance_to_end = $length - $feat->$end_method();
        my $this_distance = $distance_from_start < $distance_to_end ? $distance_from_start : $distance_to_end;
        if ($closest) {
            if ($this_distance > $closest_distance) {
                next;
            }
            elsif ($this_distance == $closest_distance
              and $feat->percent_identity < $closest->percent_identity)
            {
                next;
            }
        }
        $closest_distance = $this_distance;
        $closest = $feat;
    }
    return $closest;
}


1;

__END__

=head1 NAME - Hum::Analysis::Factory::SequenceOverlap

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

