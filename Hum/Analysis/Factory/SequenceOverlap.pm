
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
        print $over_fh $self->sequence_length_header($seq_a, $seq_b);
        print $over_fh
            $feat->pretty_header,
            $feat->pretty_string, "\n",
            $feat->pretty_alignment_string;
    }
    
    # Convert into a SequenceOverlap object that
    # can be written into the tracking database.

    return $self->make_SequenceOverlap($sinf_a, $sinf_b, $feat);
}

sub sequence_length_header {
    my( $self, @seqs ) = @_;
    
    my $str = "\n";
    foreach my $seq (@seqs) {
        $str .= sprintf "%22s  %10d bp\n", $seq->name, $seq->sequence_length;
    }
    $str .= "\n";
    return $str;
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

    # Record the length of any unmatched sequence at
    # the end of either sequence beyond the match.
    if ($pos_a->is_3prime) {
        $pos_a->dovetail_length($sa->sequence_length - $feat->seq_end);
    } else {
        $pos_a->dovetail_length($feat->seq_start - 1);
    }
    if ($pos_b->is_3prime) {
        $pos_b->dovetail_length($sb->sequence_length - $feat->hit_end);
    } else {
        $pos_b->dovetail_length($feat->hit_start - 1);
    }

    # Check that the positions calculated aren't
    # off the end of the sequences.
    $overlap->validate_Positions;
    $overlap->best_match_pair($feat);
    $overlap->other_match_pairs($self->other_matches);

    return $overlap;
}

sub is_three_prime_hit {
    my( $self, $feat, $length, $type ) = @_;

    my( $start_dist, $end_dist ) = $end_distances{$type}->($feat, $length);
    return $start_dist < $end_dist ? 0 : 1;
}

{
    ### In the future we this Factory object could contain
    ### a list of overlap detection factories.  This would
    ### be more elegant, and we could use search algorithms
    ### other than cross_match as long a the Factories return
    ### the same kind of objects.

    my @param_sets = (
            # These are the defaults for cross_match, which we try first.
            {
                'bandwidth'             => 14,
                'gap_extension_penalty' => -3,
            },

            # This is better at finding short overlaps that contain
            # an insertion in one sequence in one piece.
            {
                'bandwidth'             => 14,
                'gap_extension_penalty' => -1,
            },

            # This is better at finding very long overlaps in one piece.
            {
                'bandwidth'             => 60,
                'gap_extension_penalty' => -1,
            },
        );

    sub find_end_overlap {
        my( $self, $query, $subject ) = @_;

        my $factory = $self->crossmatch_factory;
        my( $seq_end, $hit_end );

        foreach my $param (@param_sets) {
            print STDERR "Running cross_match with:\n";
            foreach my $setting (sort keys %$param) {
                my $value = $param->{$setting};
                print STDERR "  $setting = $value\n";
                $factory->$setting($param->{$setting});
            }
            ($seq_end, $hit_end) = $self->get_end_features($query, $subject);
            if ($seq_end == $hit_end) {
                # We have found the overlap in one piece
                print STDERR "Found single feature\n";
                last;
            }
        }

        if ($seq_end == $hit_end) {
          # so that we know which matches are not the best one
          $self->filter_matches($seq_end);
          return $seq_end;
        } else {
            #print STDERR "Creating merged feature\n";
            #return $self->merge_features($seq_end, $hit_end);

            # New strategy: we no longer merge features
            my $best = $self->choose_best_feature($query, $subject, $seq_end, $hit_end);
            print STDERR "Chose best feature:\n", $best->pretty_string;

            # so that we know which matches are not the best one
            $self->filter_matches($best);
            return $best;
        }
    }
}

sub all_matches {
  my( $self, $all_matches ) = @_;

  if ($all_matches) {
    $self->{'_all_matches'} = $all_matches;
  }
  return $self->{'_all_matches'};
}

sub other_matches {
  my( $self, $other_matches ) = @_;

  if ($other_matches) {
    $self->{'_other_matches'} = $other_matches;
  }
  return $self->{'_other_matches'};
}

sub filter_matches {
  my ($self, $match) = @_;

  my @other_matches = @{$self->all_matches};
  for(my $i=0; $i<scalar @other_matches; $i++ ){
    splice(@other_matches, $i, 1) if $other_matches[$i] eq $match;
  }

  $self->other_matches(\@other_matches);
}

sub get_end_features {
    my( $self, $query, $subject ) = @_;

    my $parser = $self->crossmatch_factory->run($query, $subject);

    my( @matches );
    while (my $m = $parser->next_Feature) {
      push(@matches, $m);
    }
    # want to store all matches later in database
    $self->all_matches(\@matches);

    confess "No matches found" unless @matches;

    if (my $matches_fh = $self->matches_file) {
        print $matches_fh $self->sequence_length_header($query, $subject);
        print $matches_fh $matches[0]->pretty_header, "\n";
        print $matches_fh map($_->pretty_string, @matches), "\n";
    }

    my $seq_end = $self->closest_end_best_pid(  $query->sequence_length, $end_distances{'seq'}, @matches);
    my $hit_end = $self->closest_end_best_pid($subject->sequence_length, $end_distances{'hit'}, @matches);
    
    $self->warn_match($query, $subject, $seq_end, $hit_end);
    
    unless ($seq_end and $hit_end) {
        confess "No end overlap found\n";
    }
    
    return($seq_end, $hit_end);
}

sub crossmatch_factory {
    my( $self ) = @_;
    
    my( $factory );
    unless ($factory = $self->{'_crossmatch_factory'}) {
        $factory = $self->{'_crossmatch_factory'}
            = Hum::Analysis::Factory::CrossMatch->new;
        $factory->show_alignments(
            $self->matches_file or
            $self->overlap_alignment_file ? 1 : 0);
        $factory->show_all_matches(1);
    }
    return $factory;
}

sub warn_match {
    my( $self, $query, $subject, $seq_end, $hit_end ) = @_;

    printf STDERR "%s (%d) vs %s (%d)\n",
          $query->name,   $query->sequence_length,
        $subject->name, $subject->sequence_length;
    
    my @feat = ($seq_end);
    push(@feat, $hit_end) unless $seq_end == $hit_end;
    
    foreach my $feat (@feat) {
        print STDERR $feat->pretty_string;
    }
    
}

sub choose_best_feature {
    my ($self, $seq, $hit, $seq_end, $hit_end) = @_;

    # Return the feature with the highest percent identity
    if ($seq_end->percent_identity > $hit_end->percent_identity) {
        return $seq_end;
    }
    elsif ($hit_end->percent_identity > $seq_end->percent_identity) {
        return $hit_end;
    }
    
    # They have the same percent identity.
    # Return the match nearest an end.
    my $seq_dist = $self->distance_to_closest_end($seq, $seq_end, 'seq');
    my $hit_dist = $self->distance_to_closest_end($hit, $hit_end, 'hit');
    
    if ($seq_dist < $hit_dist) {
        return $seq_end;
    }
    elsif ($hit_dist < $seq_dist) {
        return $hit_end;
    }
    
    # They are equidistant from the closest end
    # Choose the longest
    my $seq_length = $seq_end->seq_length;
    my $hit_length = $hit_end->hit_length;
    
    if ($seq_length > $hit_length) {
        return $seq_end;
    }
    elsif ($hit_length > $seq_length) {
        return $hit_end;
    }
    
    # They are the same length!
    # Return the hit nearest the end of the query sequence
    return $seq_end;
}

sub distance_to_closest_end {
    my( $self, $seq, $feat, $type ) = @_;
    
    my $length = $seq->sequence_length;
    my ($start_dist, $end_dist) = $end_distances{$type}->($feat, $length);
    return $start_dist < $end_dist ? $start_dist : $end_dist;
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
    
    # Check that we haven't got a massive difference
    # in the gaps between the two sequences.
    my $seqlen = $new_feat->seq_length;
    my $hitlen = $new_feat->hit_length;
    warn "Feature seq_length = $seqlen\n";
    warn "Feature hit_length = $hitlen\n";
    
    # Add the length of the gap or overlap between the
    # two features into the percent_insertion figure.
    my ($gap_name, $gap_length) = $self->gap_between_features($seq, $hit);
    my( $gap_info );
    my $ins_count = $new_feat->seq_length * ($seq->percent_insertion / 100);
    if ($gap_length < 0) {
        # It is an overlap
        $ins_count += $gap_length * -1;
        $gap_info = sprintf "OVERLAP in %s of length %d bp", $gap_name, $gap_length * -1;
    } else {
        # There is a gap
        $ins_count += $gap_length;
        $gap_info = sprintf "GAP in %s of length %d bp", $gap_name, $gap_length;
    }
    warn "$gap_info\n";
    
    my $percent = 100 * ($ins_count / $new_feat->seq_length);
    $new_feat->percent_insertion($percent);
    
    if ($seq->alignment_string) {
        my @sort = sort {$a->seq_start <=> $b->seq_start} ($seq, $hit);
        $new_feat->alignment_string(
            $sort[0]->alignment_string
            . "\n"
            . " " x 12 . ">" x 10 . "  $gap_info  " . "<" x 10
            . "\n\n"
            . $sort[1]->alignment_string
            );
    }
    
    return $new_feat;
}

# Actually returns the biggest gap or smallest overlap
# If the gap is negative, then it is an overlap
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
    
    my( $gap, $name );
    if ($seq_gap > $hit_gap) {
        $name = $fa->seq_name;
        $gap = $seq_gap;
    } else {
        $name = $fa->hit_name;
        $gap = $hit_gap;
    }

    return($name, $gap);
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

