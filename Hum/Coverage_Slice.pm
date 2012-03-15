package Hum::Coverage_Slice;
use strict;
use warnings;
use Moose;
use Carp;
use Bio::EnsEMBL::Slice;
use Bio::EnsEMBL::Feature;
use List::Util qw(max min);

=head2 Hum::Coverage_Slice module

	Describes a slice with features on it.
	Has various methods concerned with calculating the coverage of the slice by the features.

=cut

has 'slice' => (
	is  => 'ro',
	isa => 'Bio::EnsEMBL::Slice',
	required => 1,
);

has 'features' => (
	is  => 'ro',
	isa => 'ArrayRef[Bio::EnsEMBL::Feature]',
	required => 1,
);

# The minimum depth that counts as "covered"
has 'depth_threshold' => (
	is  => 'ro',
	isa => 'Int',
	default => 1,
);

# The distance between covered regions to be permitted before they are merged
has 'merge_distance' => (
	is  => 'ro',
	isa => 'Int',
	default => 0,
);

# Regions where coverage is above depth_threshold
has 'deep_regions' => (
	is  => 'ro',
	isa => 'ArrayRef',
	lazy_build => 1,
);

# Opposite of deep regions
has 'nondeep_regions' => (
	is  => 'ro',
	isa => 'ArrayRef',
	lazy_build => 1,
);

# Maximum permitted coverage for features by deep-regions
# Only used for get_shallow_features
has 'deep_region_coverage_threshold' => (
	is  => 'rw',
	isa => 'Num',
	default => 50,
);

# Shallow length that will 'rescue' features in deep-regions
# Only used for get_shallow_features
has 'shallow_length_threshold' => (
	is  => 'rw',
	isa => 'Num',
	default => 20000,
);

# Determine the regions with coverage above depth_threshold
sub _build_deep_regions {
	my ($self) = @_;

	# Turn the features into a set of start and end positions
	my @termini;
	FEATURE: foreach my $feature (@{$self->features}) {
		
		# Reject any malformed features
		if(
			$feature->start > $feature->end
			or $feature->end < 1
			or $feature->start > $self->slice->length
		) { next FEATURE; }
		
		my %start_position = (
			TERMINUS => "START",
			POSITION => $feature->start,
		);
		
		my %end_position = (
			TERMINUS => "END",
			POSITION => $feature->end,
		);
		
		push(@termini, \%start_position, \%end_position);
	}

	# Sort termini into order
	@termini = sort { _sort_termini() } @termini;
	
	my $depth = 0;
	my %current_deep_region;
	my @deep_regions;

	# Find deep regions
	foreach my $terminus (@termini) {
		if($terminus->{TERMINUS} eq "START") {
			$depth++;

			# If we've crossed the depth-threshold, mark the start of a deep region
			if($depth == $self->depth_threshold) {
				$current_deep_region{START} = $terminus->{POSITION};
				if($current_deep_region{START} < 1) {$current_deep_region{START} = 1;}
			}
		}
		else {
			$depth--;
			
			# If we've crossed below the depth-threshold, mark the end of a deep region
			if($depth == $self->depth_threshold-1) {
				$current_deep_region{END} = $terminus->{POSITION};
				if($current_deep_region{END} > $self->slice->length) {$current_deep_region{END} = $self->slice->length;}
				
				# Store this deep region
				my %current_deep_region_copy = %current_deep_region;
				push(@deep_regions, \%current_deep_region_copy);
				%current_deep_region = ();
				
			}
		}
	}

	# Now consolidate any deep-regions that follow immediately on from one another
	my @merged_deep_regions;
	for(my $i = 0; $i < scalar @deep_regions; $i++) {
		# Add the current deep-region to the array
		push(@merged_deep_regions, $deep_regions[$i]);
		# If the next regions are continuous with this one, merge them
		my $j = 0;
		# Keep going through subsequent regions until you find one you can't merge
		while (
			exists($deep_regions[$i+$j+1])
			and $deep_regions[$i]->{END} + $self->merge_distance + 1 >= $deep_regions[$i+$j+1]->{START}
		) {
			# Merge regions
			$deep_regions[$i]->{END} = $deep_regions[$i+$j+1]->{END};
			$j++;
		}
		# Skip the regions you have merged
		$i += $j;
	}

	return \@merged_deep_regions;	
}

sub _sort_termini {
	
	# Where positions are identical, we need to sort STARTs before ENDs
	if($a->{POSITION} == $b->{POSITION}) {
		if ($a->{TERMINUS} eq "START" and $b->{TERMINUS} eq "END") {
			return -1;
		}
		elsif ($a->{TERMINUS} eq "END" and $b->{TERMINUS} eq "START") {
			return 1;
		}
		else {
			return 0;
		}
	}
	# Otherwise, do a comparison of the positions
	else {
		return $a->{POSITION} <=> $b->{POSITION};
	}
}

=head2 get_coverage_of_slice_by_features_as_length

	Get length of regions with coverage depth >= depth-threshold

=cut

sub get_coverage_of_slice_by_features_as_length {
	my ($self) = @_;

	# Add up the lengths of all deep regions
	my $deep_length = 0;
	foreach my $deep_region (@{$self->deep_regions}) {
		$deep_length += ($deep_region->{END} - $deep_region->{START} + 1);
	}

	return $deep_length;
}

=head2 get_coverage_of_slice_by_features_as_percentage

	Get percentage of slice composed of regions with coverage depth >= depth-threshold

=cut

sub get_coverage_of_slice_by_features_as_percentage {
	my ($self) = @_;
	
	my $deep_length = $self->get_coverage_of_slice_by_features_as_length(); 
	my $deep_coverage = ($deep_length / $self->slice->length) * 100;
	
	return $deep_coverage;
}

=head2 get_shallow_features

	Get features which are mostly not in "deep regions".
	This has a specific use in loading lastz alignments where we want to avoid repeat-heavy regions-
	it probably won't be useful elsewhere!

=cut

sub get_shallow_features {
	my ($self) = @_;
	
	my @shallow_features;

	for my $feature (@{$self->features}) {
		
		my $total_deep_region_overlap_length = 0;
		foreach my $deep_region (@{$self->deep_regions}) {
			my $deep_region_overlap_start = max($deep_region->{START}, $feature->start);
			my $deep_region_overlap_end = min($deep_region->{END}, $feature->end);
			my $deep_region_overlap_length = $deep_region_overlap_end - $deep_region_overlap_start + 1;
			if($deep_region_overlap_length > 0) {
				$total_deep_region_overlap_length += $deep_region_overlap_length;
			}
		}
		
		my $feature_length = $feature->hend - $feature->hstart + 1;
		my $deep_region_coverage = ($total_deep_region_overlap_length / $feature_length) * 100;
		my $shallow_length = $feature_length - $total_deep_region_overlap_length;
		
		# If (for a given feature) less than a certain percentage is in deep-regions (deep_region_coverage_threshold)
		# or more than a certain length (shallow_length_threshold) is outside them
		# then we return the feature.
		if($deep_region_coverage < $self->deep_region_coverage_threshold or $shallow_length > $self->shallow_length_threshold) {
			push(@shallow_features, $feature);
		}
	}
	
	return @shallow_features;
}

=head2 _build_nondeep_regions

	Gets the opposite of the deep regions.
	Note that this is different from "get_shallow_features"; the latter returns features,
	whereas this returns regions of the slice that are not covered by any feature.

=cut

sub _build_nondeep_regions {
	my ($self) = @_;

	my @nondeep_regions = ();

	my @deep_regions = @{$self->deep_regions};
	if(scalar @deep_regions == 0) {
		push(@nondeep_regions, {START=>1, END=>$self->slice->length});
		return \@nondeep_regions;
	}
	
	if($deep_regions[0]->{START} > 1) {
		$nondeep_regions[0]->{START} = 1;
		$nondeep_regions[0]->{END} = $deep_regions[0]->{START} - 1;
	}
	
	for(my $i = 0; $i < scalar @deep_regions - 2 ; $i++) {
		my %nondeep_region;
		$nondeep_region{START} = $deep_regions[$i]->{END} + 1;
		$nondeep_region{END} = $deep_regions[$i+1]->{START} - 1;
		push(@nondeep_regions, \%nondeep_region);
	}

	if($deep_regions[-1]->{END} < $self->slice->length) {
		my %nondeep_region;
		$nondeep_region{START} = $deep_regions[-1]->{END} + 1;
		$nondeep_region{END} = $self->slice->length;
		push(@nondeep_regions, \%nondeep_region);
	}
	
	return \@nondeep_regions;
}

sub percent_id_sort {
	my ($self, $feature_a, $feature_b) = @_;
	return $feature_b->percent_id <=> $feature_a->percent_id
}

sub dust_sort_priority {
	my ($self, $feature) = @_;

	my %priority_for_name = (
		trf => 2,
		dust => 1,
	);
	
	my $priority;
	
	if(exists($priority_for_name{$feature->repeat_consensus->name})) {
		$priority = $priority_for_name{$feature->repeat_consensus->name};
	}
	else {
		$priority = 0;
	}
	
	return $priority;
}

sub dust_sort {
	my ($self, $feature_a, $feature_b) = @_;
	
	my $priority_a = $self->dust_sort_priority($feature_a);
	my $priority_b = $self->dust_sort_priority($feature_b);

	# If the priorities of the repeat-types are the same, favour the longer repeat
	if($priority_a == $priority_b) {
		return $feature_b->length <=> $feature_a->length;
	}
	else {
		return $priority_b <=> $priority_a;
	}
}

=head2 get_feature_exposure

	Get the "exposure" of features
	This is currently designed to give the # of bases that each feature has "exposed", prioritising (by default) by percent_id
	This won't work for any feature not returning percent_id, but it could be made more general.
	Alternatively, an explicit "sort function" can be sent. Currently, this is only "Dust", which prioritises Dust.
	Returns a hash indexed on dbID of features.
	
	If "$restrict_features_to_slice_coordinates" is set, this prevents any feature starting before the slice or extending past it

=cut

sub get_feature_exposure {
	my ($self, $sort_function, $restrict_features_to_slice_coordinates) = @_;
	
	if(!defined($sort_function)) {
		$sort_function = 'percent_id_sort';
	}
	
	# Turn the features into a set of start and end positions
	my @termini;
	foreach my $feature (@{$self->features}) {

		my ($start, $end);
		
		if($restrict_features_to_slice_coordinates) {
			$start = max($feature->start, 1);
			$end = min($feature->end, $self->slice->length);
		}
		else {
			$start = $feature->start;
			$end = $feature->end;
		}
		
		my %start_position = (
			TERMINUS => "START",
			POSITION => $start,
			FEATURE => $feature,
		);
		
		my %end_position = (
			TERMINUS => "END",
			POSITION => $end,
			FEATURE => $feature,
		);
		
		push(@termini, \%start_position, \%end_position);
	}

	# Sort termini into order
	@termini = sort { _sort_termini() } @termini;
	
	my $depth = 0;
	my %current_features_by_dbID;
	my %exposure_termini_for_dbID;
	my $current_exposure_termini_ref;
	my @sorted_dbIDs;	# DBIDs in order of percent_id
	my $currently_exposed_dbID;

	# Find regions of exposure
	foreach my $terminus (@termini) {
		if($terminus->{TERMINUS} eq "START") {
			# Add this region to the current regions
			$current_features_by_dbID{$terminus->{FEATURE}->dbID} = $terminus->{FEATURE};
			
			# Sort current dbIDs by percent ID
			@sorted_dbIDs = sort {
				$self->$sort_function($current_features_by_dbID{$a}, $current_features_by_dbID{$b})
			} keys %current_features_by_dbID;
			
			# Is this the end of a feature's exposure region?
			if(!defined($currently_exposed_dbID) or $sorted_dbIDs[0] != $currently_exposed_dbID) {
				# Record the start and end of the current exposure
				if(defined($currently_exposed_dbID)) {
					$current_exposure_termini_ref->{END} = $terminus->{POSITION} - 1;
					push( @{$exposure_termini_for_dbID{$currently_exposed_dbID}}, $current_exposure_termini_ref );
				}
				
				$currently_exposed_dbID = $sorted_dbIDs[0];
				$current_exposure_termini_ref = {
					START => $terminus->{POSITION},
				};
			}
		}
		# Or if this is an end...
		else {
			# Remove this region from the current regions
			delete($current_features_by_dbID{$terminus->{FEATURE}->dbID});
			
			# If the feature that has ended is the current exposure, record its end
			if($currently_exposed_dbID == $terminus->{FEATURE}->dbID) {
				$current_exposure_termini_ref->{END} = $terminus->{POSITION};
				push( @{$exposure_termini_for_dbID{$currently_exposed_dbID}}, $current_exposure_termini_ref );
				
				# If there are any features remaining, sort them, and mark the best as exposed
				@sorted_dbIDs = sort {
					$self->$sort_function($current_features_by_dbID{$a}, $current_features_by_dbID{$b})
				} keys %current_features_by_dbID;
				if(scalar @sorted_dbIDs > 0) {
					$currently_exposed_dbID = $sorted_dbIDs[0];
					$current_exposure_termini_ref = {
						START => $terminus->{POSITION} + 1,
					};
				}
				# Otherwise, undefine the current exposed ref
				else {
					$current_exposure_termini_ref = undef;
					$currently_exposed_dbID = undef;
				}
			}
		}
	}

	# Convert exposure start and end points into lengths
	my %exposure_for_dbID;
	foreach my $dbID (keys %exposure_termini_for_dbID) {
		foreach my $exposure ( @{$exposure_termini_for_dbID{$dbID}} ) {
			# It is possible for the END to precede the START
			# if two high-id alignments follow immediately after another
			# with a low-id alignment overlapping the join
			# Ignore these!
			if($exposure->{END} >= $exposure->{START}) {
				# Otherwise, record the length
				$exposure_for_dbID{$dbID} += $exposure->{END} - $exposure->{START} + 1;
			}
		}
	}
	
	return \%exposure_for_dbID;
}

no Moose;
__PACKAGE__->meta->make_immutable;

__END__

=head1 AUTHOR

James Torrance <jt8@sanger.ac.uk>

