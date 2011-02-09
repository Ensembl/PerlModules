
### Hum::Analysis::Factory::SequenceOverlap

package Hum::Analysis::Factory::SequenceOverlap;

use strict;
use warnings;
use Carp;
use Hum::Analysis::Factory::CrossMatch;
use Hum::Analysis::Factory::Epic;
use Hum::SequenceOverlap;
use Hum::Chromoview::Utils qw(store_failed_overlap_pairs);

my (%end_distances);

foreach my $name_meths (
    [qw{ seq seq_start seq_end }],
    [qw{ hit hit_start hit_end }])
{
    my ($type, $start_method, $end_method) = @$name_meths;
    $end_distances{$type} = sub {
        my ($feat, $length) = @_;
        my $distance_from_start = $feat->$start_method() - 1;
        my $distance_to_end     = $length - $feat->$end_method();
        return ($distance_from_start, $distance_to_end);
      };
}

sub new {
    my ($pkg) = @_;

    return bless {}, $pkg;
}

sub contained {
    my ($self, $contained) = @_;

    if ($contained) {
        $self->{'_contained'} = $contained;
    }
    if(!exists($self->{'_contained'})) {
    	return 0;
    }
    else {
    	return $self->{'_contained'};
    }
}

sub algorithm {
    my ($self, $algorithm) = @_;

    if ($algorithm) {
        $self->{'_algorithm'} = $algorithm;
    }
    return $self->{'_algorithm'};
}

sub _open_file {
    my ($self, $file) = @_;

    my $type = ref($file);
    unless ($type and $type eq 'GLOB') {
        open my $fh, "> $file"
          or die "Can't write to '$file' : $!";
        $file = $fh;
    }
    return $file;
}

sub find_SequenceOverlap {
    my ($self, $sinf_a, $sinf_b) = @_;
    
    my $seq_a = $sinf_a->Sequence;
    my $seq_b = $sinf_b->Sequence;
    unless ($seq_a and $seq_b) {
        confess sprintf "Didn't get Sequence for both a ('%s') and b ('%s')",
          $sinf_a->accession_sv,
          $sinf_b->accession_sv;
    }

    my (
        $feat,              # Overlap feature
        $other_features,    # Other features found by algorithm
    );
    eval {
        if ($self->algorithm eq 'CrossMatch') {

            # Run cross_match and find overlap
            ($feat, $other_features) = $self->find_end_overlap_crossmatch($seq_a, $seq_b);
        }
        elsif ($self->algorithm eq 'epic') {

            # epic only returns one feature
            $feat = $self->find_overlap_epic($seq_a, $seq_b);
        }
        else {
            die sprintf("Unknown algorithm '%s'", $self->algorithm);
        }
    };
    if ($@) {
        my $errmsg = $@;
        warn $errmsg;
        Hum::Chromoview::Utils::store_failed_overlap_pairs($seq_a->name, $seq_b->name, $errmsg);
        return;
    }
    return unless $feat;

	#### COMMENTED OUT CODE FOR HANDLING CONTAINED CLONES
	# If this is a contained clone, convert into multiple SequenceOverlaps
	#if($self->contained) {
	#    my (@so);
	#    eval { @so = $self->make_contained_SequenceOverlap($sinf_a, $sinf_b, $feat, $other_features); };
	#    if ($@) {
	#        my $errmsg = $@;
	#        warn $errmsg;
	#        Hum::Chromoview::Utils::store_failed_overlap_pairs($seq_a->name, $seq_b->name, $errmsg);
	#        return;
	#    }
	#    else {
	#        return @so;
	#    }
	#}
	# Otherwise, process as a single overlap
	#else {
	    # Convert into a SequenceOverlap object that
	    # can be written into the tracking database.
	    my ($so);
	    eval { $so = $self->make_SequenceOverlap($sinf_a, $sinf_b, $feat, $other_features); };
	    if ($@) {
	        my $errmsg = $@;
	        warn $errmsg;
	        Hum::Chromoview::Utils::store_failed_overlap_pairs($seq_a->name, $seq_b->name, $errmsg);
	        return;
	    }
	    else {
	        return $so;
	    }
	#}
}

sub sequence_length_header {
    my ($self, @seqs) = @_;

    my $str = "\n";
    foreach my $seq (@seqs) {
        $str .= sprintf "%22s  %10d bp\n", $seq->name, $seq->sequence_length;
    }
    $str .= "\n";
    return $str;
}

sub make_SequenceOverlap {
    my ($self, $sa, $sb, $feat, $other_features) = @_;

    my $overlap = Hum::SequenceOverlap->new;
    $overlap->best_match_pair($feat);
    $overlap->other_match_pairs($other_features);

    # Copy the percent sub, ins, del
    foreach my $meth (qw{ percent_substitution percent_insertion percent_deletion }) {
        $overlap->$meth($feat->$meth());
    }
    $overlap->source_name($feat->algorithm);

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
        }
        else {
            $pos_a->position($feat->seq_end + 1);
        }
        if ($pos_b->is_3prime) {
            $pos_b->position($feat->hit_end);
        }
        else {
            $pos_b->position($feat->hit_start);
        }
    }
    else {

        # The usual "downstairs" overlap (ie: most clones
        # in the golden path begin at 2001 or 101).
        $overlap->overlap_length($feat->seq_length);
        if ($pos_a->is_3prime) {
            $pos_a->position($feat->seq_end);
        }
        else {
            $pos_a->position($feat->seq_start);
        }
        if ($pos_b->is_3prime) {
            $pos_b->position($feat->hit_start - 1);
        }
        else {
            $pos_b->position($feat->hit_end + 1);
        }
    }

    # Record the length of any unmatched sequence at
    # the end of either sequence beyond the match.
    if ($pos_a->is_3prime) {
        $pos_a->dovetail_length($sa->sequence_length - $feat->seq_end);
    }
    else {
        $pos_a->dovetail_length($feat->seq_start - 1);
    }
    if ($pos_b->is_3prime) {
        $pos_b->dovetail_length($sb->sequence_length - $feat->hit_end);
    }
    else {
        $pos_b->dovetail_length($feat->hit_start - 1);
    }

    # Check that the positions calculated aren't
    # off the end of the sequences.
    $overlap->validate_Positions;

    return $overlap;
}

### This procedure is not presently called. It needs further development
#sub make_contained_SequenceOverlap {
#    my ($self, $sa, $sb, $feat, $other_features) = @_;
#
#    my $overlap_a = Hum::SequenceOverlap->new;
#    my $overlap_b = Hum::SequenceOverlap->new;
#    
#	# Set up overlap parameters that are the same for both
#    foreach my $overlap ($overlap_a, $overlap_b) {
#	    $overlap->best_match_pair($feat);
#	    $overlap->other_match_pairs($other_features);
#	
#	    # Copy the percent sub, ins, del
#	    foreach my $meth (qw{ percent_substitution percent_insertion percent_deletion }) {
#	        $overlap->$meth($feat->$meth());
#	    }
#	    $overlap->source_name($feat->algorithm);
#    }
#
#### CORRECT THE BELOW!!! YOU MAY NEED INFO ABOUT CLONE ORIENTATION IF YOU WANT TO MAKE THIS WORK!!!
####	 ... or do I? Can this be done in a way that doesn't care about that?
#		either the strand is +ve, in which case the point with the lower seq-value is 3'/5' (container/contained), then the later is 3'/5' (container/contained)
#		or it's -ve, in which case the same is 3'/3', then the later is 5'/5'
#		Mind out though: it seems that both hit_strand and seq_strand exist, and both can have either value, so need to look at parser more closely.
#    my ($pos_a, $pos_b) = $overlap_a->make_new_Position_objects;
#    $pos_a->SequenceInfo($sa);
#    $pos_b->SequenceInfo($sb);
#    $pos_a->is_3prime($self->is_three_prime_hit($feat, $sa->sequence_length, 'seq'));
#    $pos_b->is_3prime($self->is_three_prime_hit($feat, $sb->sequence_length, 'hit'));
#
#	# The first overlap is always an "upstairs" overlap
#    $overlap->overlap_length($feat->hit_length);
#    if ($pos_a->is_3prime) {
#        $pos_a->position($feat->seq_start - 1);
#    }
#    else {
#        $pos_a->position($feat->seq_end + 1);
#    }
#    if ($pos_b->is_3prime) {
#        $pos_b->position($feat->hit_end);
#    }
#    else {
#        $pos_b->position($feat->hit_start);
#    }
#
#	### NOW ADD IN SECOND OVERLAP
#
#    # Record the length of any unmatched sequence at
#    # the end of either sequence beyond the match.
#    if ($pos_a->is_3prime) {
#        $pos_a->dovetail_length($sa->sequence_length - $feat->seq_end);
#    }
#    else {
#        $pos_a->dovetail_length($feat->seq_start - 1);
#    }
#    if ($pos_b->is_3prime) {
#        $pos_b->dovetail_length($sb->sequence_length - $feat->hit_end);
#    }
#    else {
#        $pos_b->dovetail_length($feat->hit_start - 1);
#    }
#
#    # Check that the positions calculated aren't
#    # off the end of the sequences.
#    $overlap->validate_Positions;
#
#    return $overlap;
#}

sub is_three_prime_hit {
    my ($self, $feat, $length, $type) = @_;

    my ($start_dist, $end_dist) = $end_distances{$type}->($feat, $length);
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

    sub find_end_overlap_crossmatch {
        my ($self, $query, $subject) = @_;

        my $factory = $self->crossmatch_factory;

        my ($seq_end, $hit_end, $other_features);
        foreach my $param (@param_sets) {
            print STDERR "Running cross_match with:\n";
            foreach my $setting (sort keys %$param) {
                my $value = $param->{$setting};
                print STDERR "  $setting = $value\n";
                $factory->$setting($param->{$setting});
            }
            ($seq_end, $hit_end, $other_features) = $self->get_end_features($query, $subject);

            if (!$seq_end and !$hit_end) {
                return;
            }
            elsif ($seq_end == $hit_end) {

                # We have found the overlap in one piece
                print STDERR "Found single feature\n";
                last;
            }
        }

        if ($seq_end == $hit_end) {

            # Remove end hit from the list of features
            $self->filter_matches($seq_end, $other_features);
            return ($seq_end, $other_features);
        }
        else {

            #print STDERR "Creating merged feature\n";
            #return $self->merge_features($seq_end, $hit_end);

            # New strategy: we no longer merge features
            my $best = $self->choose_best_feature($query, $subject, $seq_end, $hit_end);
            print STDERR "Chose best feature:\n", $best->pretty_string;

            # Remove best hit from the list of features
            $self->filter_matches($best, $other_features);
            return ($best, $other_features);
        }
    }
}

sub filter_matches {
    my ($self, $match, $other_features) = @_;

    for (my $i = 0; $i < @$other_features; $i++) {
        if ($other_features->[$i] == $match) {
            splice(@$other_features, $i, 1);
            last;
        }
    }
}

sub get_end_features {
    my ($self, $query, $subject) = @_;

    my $parser = $self->crossmatch_factory->run($query, $subject);
    my $matches = [];
    while (my $m = $parser->next_Feature) {
        push(@$matches, $m);
        $m->seq_Sequence($query);
        $m->hit_Sequence($subject);
    }

    die "No matches found by cross_match\n" unless @$matches;

    my $seq_end = $self->closest_end_best_pid($query->sequence_length,   $end_distances{'seq'}, @$matches);
    my $hit_end = $self->closest_end_best_pid($subject->sequence_length, $end_distances{'hit'}, @$matches);

    $self->warn_match($query, $subject, $seq_end, $hit_end);

    unless ($seq_end and $hit_end) {
        die "No end overlap found\n";
    }

    return ($seq_end, $hit_end, $matches);
}

sub epic_factory {
    my ($self) = @_;

    my $factory = $self->{'_epic_factory'} ||= Hum::Analysis::Factory::Epic->new;
    # if($self->contained) {$factory->set_contained_mode}
    return $factory;
}

sub find_overlap_epic {
    my ($self, $query, $subject) = @_;

    my $parser = $self->epic_factory->run($query, $subject);
    if (my $feat = $parser->next_Feature) {
        $feat->seq_Sequence($query);
        $feat->hit_Sequence($subject);
        return $feat;
    }
    else {
        die "No match found by epic\n";
    }
}

sub crossmatch_factory {
    my ($self) = @_;

    my ($factory);
    unless ($factory = $self->{'_crossmatch_factory'}) {
        $factory = $self->{'_crossmatch_factory'} = Hum::Analysis::Factory::CrossMatch->new;
        $factory->show_alignments(1);
        $factory->show_all_matches(1);
    }
    return $factory;
}

sub warn_match {
    my ($self, $query, $subject, $seq_end, $hit_end) = @_;

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
    my ($self, $seq, $feat, $type) = @_;

    my $length = $seq->sequence_length;
    my ($start_dist, $end_dist) = $end_distances{$type}->($feat, $length);
    return $start_dist < $end_dist ? $start_dist : $end_dist;
}

sub merge_features {
    my ($self, $seq, $hit) = @_;

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
    $new_feat->seq_end($seq->seq_end > $hit->seq_end       ? $seq->seq_end   : $hit->seq_end);
    $new_feat->hit_start($seq->hit_start < $hit->hit_start ? $seq->hit_start : $hit->hit_start);
    $new_feat->hit_end($seq->hit_end > $hit->hit_end       ? $seq->hit_end   : $hit->hit_end);

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
    my ($gap_info);
    my $ins_count = $new_feat->seq_length * ($seq->percent_insertion / 100);
    if ($gap_length < 0) {

        # It is an overlap
        $ins_count += $gap_length * -1;
        $gap_info = sprintf "OVERLAP in %s of length %d bp", $gap_name, $gap_length * -1;
    }
    else {

        # There is a gap
        $ins_count += $gap_length;
        $gap_info = sprintf "GAP in %s of length %d bp", $gap_name, $gap_length;
    }
    warn "$gap_info\n";

    my $percent = 100 * ($ins_count / $new_feat->seq_length);
    $new_feat->percent_insertion($percent);

    if ($seq->alignment_string) {
        my @sort = sort { $a->seq_start <=> $b->seq_start } ($seq, $hit);
        $new_feat->alignment_string($sort[0]->alignment_string . "\n"
              . " " x 12
              . ">" x 10
              . "  $gap_info  "
              . "<" x 10 . "\n\n"
              . $sort[1]->alignment_string);
    }

    return $new_feat;
}

# Actually returns the biggest gap or smallest overlap
# If the gap is negative, then it is an overlap
sub gap_between_features {
    my ($self, $fa, $fb) = @_;

    if ($fa->seq_start > $fb->seq_start) {
        ($fa, $fb) = ($fb, $fa);
    }
    my $seq_gap = $fb->seq_start - $fa->seq_end - 1;

    if ($fa->hit_start > $fb->hit_start) {
        ($fa, $fb) = ($fb, $fa);
    }
    my $hit_gap = $fb->hit_start - $fa->hit_end - 1;

    my ($gap, $name);
    if ($seq_gap > $hit_gap) {
        $name = $fa->seq_name;
        $gap  = $seq_gap;
    }
    else {
        $name = $fa->hit_name;
        $gap  = $hit_gap;
    }

    return ($name, $gap);
}

sub closest_end_best_pid {
    my ($self, $length, $ends_method, @matches) = @_;

    my ($closest, $closest_distance);
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
            elsif ( $this_distance == $closest_distance
                and $feat->percent_identity < $closest->percent_identity)
            {
                next;
            }
        }
        $closest_distance = $this_distance;
        $closest          = $feat;
    }
    return $closest;
}

1;

__END__

=head1 NAME - Hum::Analysis::Factory::SequenceOverlap

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

