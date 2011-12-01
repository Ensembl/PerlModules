### Hum::AGP

package Hum::AGP;

use strict;
use warnings;
use Carp;

=head1 NAME - Hum::AGP

=head1 METHODS

=cut

use Hum::AGP::Row::Clone;
use Hum::AGP::Row::Gap;
use Hum::SequenceOverlap;

sub new {
    my( $pkg ) = @_;

    return bless {
        '_rows' => [],
        }, $pkg;
}


=head2 min_htgs_phase

Get/set the minimum High Throughput Genome Sequencing phase to let
through.

=cut

sub min_htgs_phase {
    my( $self, $min_htgs_phase ) = @_;

    if ($min_htgs_phase) {
        confess "bad HTGS_PHASE '$min_htgs_phase'"
            unless $min_htgs_phase =~ /^\d+$/;
        confess "Can't set min_htgs_phase to more than '3' (trying to set to '$min_htgs_phase')"
            if $min_htgs_phase > 3;
        $self->{'_min_htgs_phase'} = $min_htgs_phase;
    }
    return $self->{'_min_htgs_phase'};
}


=head2 effective_min_htgs_phase

Get the minimum C<SEQUENCE.ID_HTGSPHASE> to allow, taking into account
L</min_htgs_phase> and L</allow_unfinished>.

=cut

# Trades some inefficiency for min_htgs_phase being a pure accessor.
sub effective_min_htgs_phase {
    my ($self) = @_;
    my $min_phase  = $self->min_htgs_phase;
    unless ($min_phase) {
        if ($self->allow_unfinished) {
            $min_phase = 1;
        } else {
            $min_phase = 2;
        }
    }
    return $min_phase;
}

sub allow_unfinished {
    my( $self, $flag ) = @_;

    if (defined $flag) {
        $self->{'_allow_unfinished'} = $flag ? 1 : 0;
    }
    return $self->{'_allow_unfinished'};
}

sub allow_dovetails {
    my( $self, $flag ) = @_;

    if (defined $flag) {
        $self->{'_allow_dovetails'} = $flag ? 1 : 0;
    }
    return $self->{'_allow_dovetails'};
}


=head2 accept_visited_project_statuses

Get/set a list of C<project_status.status> ID values.  A project is
acceptable if its status history includes any of these.

Set to C<undef> to not check project_status.  This is the default.

Returns a copy of the list, or C<undef> if no check should be
performed.

=cut

sub accept_visited_project_statuses {
    my $self = shift;
    if (@_) {
	my $ary = shift;
	confess "accept_visited_project_statuses: Expected an ARRAY ref but got $ary"
	  if defined $ary && ref($ary) ne 'ARRAY';
	$self->{'_accept_visited_project_statuses'} = $ary;
    }
    my $list = $self->{'_accept_visited_project_statuses'};
    return $list ? [ @$list ] : ();
}


sub missing_overlap_pad {
    my( $self, $overlap_pad ) = @_;

    if ($overlap_pad) {
        $self->{'_overlap_pad'} = $overlap_pad;
    }
    return $self->{'_overlap_pad'} || 5000;
}

sub unknown_gap_length {
    my( $self, $unknown_gap_length ) = @_;

    if ($unknown_gap_length) {
        $self->{'_unknown_gap_length'} = $unknown_gap_length;
    }
    return $self->{'_unknown_gap_length'} || 50_000;
}

sub new_Clone {
    my( $self ) = @_;

    my $clone = Hum::AGP::Row::Clone->new;
    $self->add_Row($clone);
    return $clone;
}

sub new_Clone_from_tpf_Clone {
    my( $self, $tpf_cl ) = @_;

    my $inf = $tpf_cl->SequenceInfo;
    my $acc = $inf->accession;
    my $sv  = $inf->sequence_version;

    my $cl = $self->new_Clone;
    $cl->seq_start(1);
    $cl->seq_end($inf->sequence_length);
    $cl->htgs_phase($inf->htgs_phase);
    $cl->accession_sv("$acc.$sv");
    $cl->remark($tpf_cl->remark);
    
    if($cl->remark) {
	    if($cl->remark =~ /MINUS/) {
	    	$cl->strand(-1);
	    }
	    elsif($cl->remark =~ /PLUS/) {
	    	$cl->strand(1);
	    }
    }
    
    return $cl;
}

sub new_Gap {
    my( $self ) = @_;

    my $gap = Hum::AGP::Row::Gap->new;
    $self->add_Row($gap);
    return $gap;
}

sub chr_name {
    my( $self, $chr_name ) = @_;

    if ($chr_name) {
        $self->{'_chr_name'} = $chr_name;
    }
    return $self->{'_chr_name'} || confess "chr_name not set";
}


sub fetch_all_Rows {
    my( $self ) = @_;

    return @{$self->{'_rows'}};
}

sub last_Row {
  my ($self) = @_;

  my $r = $self->{'_rows'};
  return $r->[$#$r];
}

sub add_Row {
    my( $self, $row ) = @_;

    push(@{$self->{'_rows'}}, $row);
}

sub verbose {
  my( $self, $val ) = @_;

  # print STDERR messages
  if (defined $val) {
    $self->{'_verbose'} = $val;
  }
  $val = $self->{'_verbose'};
  return defined($val) ? $val : 1;
}

sub process_TPF {
    my( $self, $tpf ) = @_;

    my $verbose = $self->verbose;

    my @rows = $tpf->fetch_non_contained_Rows;
    my $contig = [];

    for (my $i = 0; $i < @rows; $i++) {
        my $row = $rows[$i];
        if ($row->is_gap) {
            $self->_process_contig($contig, $row) if @$contig;
            $contig = [];
            my $gap = $self->new_Gap;
            $gap->chr_length($row->gap_length || $self->unknown_gap_length);
            $gap->set_remark_from_Gap($row);
        } else {
	    my ($skip_gap, $skip_why);

            my $inf = $row->SequenceInfo;
            my $phase = $inf ? $inf->htgs_phase : 0;
            if ($phase < $self->effective_min_htgs_phase) {
		$skip_gap = 50_000;
		$skip_why = sprintf("Skipping HTGS_PHASE%d sequence '%s'\n",
				    $phase, $row->sanger_clone_name);
	    }
	    elsif (my $statuses = $self->accept_visited_project_statuses) {
		# We must do project-QC-like checks
		unless ($row->project_status_history_includes(@$statuses)) {
		    $skip_gap = 50_000;
		    $skip_why = sprintf("Skipping sequence '%s', project_status does not include (%s)\n",
					$row->sanger_clone_name, join " ", @$statuses);
		}
	    }

	    unless ($skip_gap) {
		# accept the row
                push(@$contig, $row);
		next;
            }

	    printf STDERR $skip_why if $verbose;
	    $self->_process_contig($contig) if @$contig;
	    $contig = [];
	    my $gap = $self->new_Gap;
	    $gap->chr_length($skip_gap);
	    my $is_linked = 'yes';
	    if ($i == 0 or $i == $#rows  # We're the first or last row or
		or $rows[$i - 1]->is_gap # the previous row was a gap or
		or $rows[$i + 1]->is_gap # the next row is a gap.
	       )
	      {
		  $is_linked = 'no';
	      }
	    $gap->remark("clone\t$is_linked");
        }
    }

    $self->_process_contig($contig) if @$contig;
}

sub _process_contig {
    my( $self, $contig, $row) = @_;

    my $verbose = $self->verbose;

    # $cl is a Hum::AGP::Row::Clone
    my $cl = $self->new_Clone_from_tpf_Clone($contig->[0]);

    my( $was_3prime, $strand );
    for (my $i = 1; $i < @$contig; $i++) {
        my $inf_a = $contig->[$i - 1]->SequenceInfo;
        my $inf_b = $contig->[$i    ]->SequenceInfo;
        my $over = Hum::SequenceOverlap
            ->fetch_by_SequenceInfo_pair($inf_a, $inf_b);

        # Add gap if no overlap
        unless ($over) {
            # Set strand for current clone
            if(!defined($cl->strand)) {
	            $cl->strand($strand || 1);
            }
			$self->check_for_contained_clones($cl, $contig->[$i-1]);
            $self->insert_missing_overlap_pad->remark('No overlap in database');
            $strand = undef;
            $cl = $self->new_Clone_from_tpf_Clone($contig->[$i]);
            next;
        }

        my $pa = $over->a_Position;
        my $pb = $over->b_Position;

        my $miss_join = 0;
        if ($pa->is_3prime) {
            if ($strand and $was_3prime) {
                $self->insert_missing_overlap_pad->remark('Bad overlap - double 3 prime join');
                $strand = undef;
                $miss_join = 3;
            }
        } else {
            if ($strand and ! $was_3prime) {
                $self->insert_missing_overlap_pad->remark('Bad overlap - double 5 prime join');
                $strand = undef;
                $miss_join = 5;
            }
        }

        # Report miss-join errors
        if ($miss_join) {
          my $join_err = sprintf "Double %d-prime join to '%s'\n",
            $miss_join, $cl->accession_sv;
          printf STDERR $join_err if $verbose;
          $cl->join_error($join_err);
        }
        elsif (!($self->allow_dovetails)) {
          if (my $dovetail = $pa->dovetail_length || $pb->dovetail_length) {
            ### Should if overlap has been manually ail;
            printf STDERR "Dovetail of length '$dovetail' in overlap\n" if $verbose;
            $self->insert_missing_overlap_pad->remark("Bad overlap - dovetail of length $dovetail");
            if(!defined($cl->strand)) {
	            $cl->strand($strand || 1);
            }
			$cl = $self->check_for_contained_clones($cl, $contig->[$i-1]);
            $strand = undef;
            if ($pa->is_3prime) {
              $cl->seq_end($inf_a->sequence_length);
            } else {
              $cl->seq_start(1);
            }
            $cl = $self->new_Clone_from_tpf_Clone($contig->[$i]);
            next;
          }
        }

        unless ($strand) {
            # Not set for first pair, or following miss-join
            $strand = $pa->is_3prime ? 1 : -1;
        }
        
        # If a clone has a strand specified by the TPF, this takes priority
        if(defined($cl->strand)) {
	        $strand = $cl->strand;
        }
        else {
        	$cl->strand($strand);
        }

        $cl = $self->check_for_contained_clones($cl, $contig->[$i-1]);

        if ($pa->is_3prime) {
        	$cl->seq_end($pa->position);
        }
        else {
        	$cl->seq_start($pa->position);
        }

        # Flip the strand if this is a
        # head to head or tail to tail join.
        $strand *= $pa->is_3prime == $pb->is_3prime ? -1 : 1;

        # Move $cl pointer to next clone
        $cl = $self->new_Clone_from_tpf_Clone($contig->[$i]);
        if ($pb->is_3prime) {
            $was_3prime = 1;
            $cl->seq_end($pb->position);
        } else {
            $was_3prime = 0;
            $cl->seq_start($pb->position);
        }
    }
    if(!defined($cl->strand)) {
    	$cl->strand($strand || 1);
    }
	$self->check_for_contained_clones($cl, $contig->[-1]);
}

sub _process_contained_contig {
    my( $self, $container_clone, $container_tpf_clone) = @_;

    my $verbose = $self->verbose;

	# Establish what the contained clones are and how they relate to one another
	my @contained_clones = $container_tpf_clone->get_contained_clones;
	
	# PROVISIONALLY, LEAVE THIS
	# The subsequent section deals with the possibility that the contained clones
	# might be in an order other than that in the TPF
	# This is tricky to implement, so I'm going to leave it for now.
	# Provisionally, I'll assume that they're in the order designated in the TPF
	if(0) {
		# Check the contained clones pairwise for any overlap between them
		my %overlaps_between_contained_clones;
		for my $i (0..$#contained_clones) {
			for my $j ($i+1 .. $#contained_clones) {
		        my $inf_a = $contained_clones[$i]->SequenceInfo;
		        my $inf_b = $contained_clones[$j]->SequenceInfo;
	    	    my $over = Hum::SequenceOverlap
	        	    ->fetch_by_SequenceInfo_pair($inf_a, $inf_b);
				if($over) {
					my @accessions = sort {$a cmp $b} ($contained_clones[$i]->accession, $contained_clones[$j]->accession);
					$overlaps_between_contained_clones{$accessions[0]}{$accessions[1]} = $over;
				}
			}
		}
		
		# Get all overlaps between the container clone and the contained clones
		# Then sort the contained clones in order of these overlaps
		# Note that this will be in reverse order if the strand is -1
		my %overlaps_between_contained_clones_and_container;
		my @contained_clones_overlapping_container;
		my @contained_clones_not_overlapping_container;
		foreach my $contained_clone (@contained_clones) {
			my @overlaps = Hum::SequenceOverlap
	           ->fetch_contained_by_SequenceInfo_pair($container_tpf_clone->SequenceInfo, $contained_clone->SequenceInfo);
	
			if(scalar @overlaps > 0) {
	   			@overlaps = sort {$a->a_Position->position <=> $b->a_Position->position} @overlaps;
				$overlaps_between_contained_clones_and_container{$contained_clone->accession} = \@overlaps;
				push(@contained_clones_overlapping_container, $contained_clone);
			}
			else {
				push(@contained_clones_not_overlapping_container, $contained_clone);
			}
		}
		
		# Now sort contained clones according to the order of their overlaps
		# Note that this only sorts those clones which have overlaps with the container clone;
		# any contained clones which overlap other contained clones at both ends are set aside
		my @sorted_contained_clones = sort {
			$overlaps_between_contained_clones_and_container{$a->accession}->[0]->a_Position->position
			<=>
			$overlaps_between_contained_clones_and_container{$b->accession}->[0]->a_Position->position
		} @contained_clones_overlapping_container;
	
		if($container_clone->strand == -1) {
			@sorted_contained_clones = reverse @sorted_contained_clones;
		}
	
		# Now splice in those clones which overlap other contained clones
		## COME BACK TO IMPLEMENTING THIS!!!
	}	
	# END SKIPPED SECTION

	# Now go through the contained clones and process them one by one
	my $clone = $container_clone;
	my $contained_clone_overlap;
	CONTAINED_CLONE: for my $i (0 .. $#contained_clones) {

		# Get overlaps (if any) between the present clone and the container
		my @overlaps = Hum::SequenceOverlap
           ->fetch_contained_by_SequenceInfo_pair($container_tpf_clone->SequenceInfo, $contained_clones[$i]->SequenceInfo);						
		
		# The overlap that we use depends upon the strand of the container clone
		if($container_clone->strand == 1) {
			@overlaps = sort {$a->a_Position->position <=> $b->a_Position->position} @overlaps;
		}
		else {
			@overlaps = sort {$b->a_Position->position <=> $a->a_Position->position} @overlaps;
		}
		
		# Initially check for an overlap between the two successive clones
		# This will have been obtained in a previous loop
		my $first_overlap;
		if(defined($contained_clone_overlap)) {
			$first_overlap = $contained_clone_overlap;
			$contained_clone_overlap = undef;
		}

		if(!defined($first_overlap)) {
			# Otherwise, use the overlap with the container
			# Note that this also copes with the scenario where only one overlap with
			# the container clone exists
			if(scalar @overlaps == 0) {
				my $join_err = "Cannot find overlap between container clone " . $container_tpf_clone->accession;
				for my $j ($i .. $#contained_clones) {
					$join_err .= " and contained clone " . $contained_clones[$j]->accession;
				}
				$join_err .= "\n";
				$clone->join_error($join_err);
				print STDERR $join_err if $verbose;
				last CONTAINED_CLONE;
			}
			$first_overlap = $overlaps[0];
		}
		# If there is neither an overlap between the contained clones
		# or between them and their container, throw a wobbly
		if(!defined($first_overlap)) {
			my $join_err = "Cannot find overlap between container clone " . $container_tpf_clone->accession;
			for my $j ($i .. $#contained_clones) {
				$join_err .= " and contained clone " . $contained_clones[$j]->accession;
			}
			$join_err .= "\n";
			$clone->join_error($join_err);
			print STDERR $join_err if $verbose;
			last CONTAINED_CLONE;
		}
		
		# Use the first overlap to specify the ending of the current clone
		my $pa = $first_overlap->a_Position;
        if ($pa->is_3prime and $clone->strand == 1) {
            $clone->seq_end($pa->position);
		}
		elsif (!$pa->is_3prime and $clone->strand == -1) {
            $clone->seq_start($pa->position);
        }
        # If the 5'/3' settings of the overlap are inconsistent with the clone orientation,
        # then throw an error
        else {
        	my $join_err = "Orientation and overlap information are inconsistent for container clone " . $container_tpf_clone->accession;
			for my $j ($i .. $#contained_clones) {
				$join_err .= " and contained clone " . $contained_clones[$j]->accession;
			}
			$join_err .= "\n";
			$clone->join_error($join_err);
			print STDERR $join_err if $verbose;
			last CONTAINED_CLONE;
        }
        
        # Now move on to the start of the next clone
        my $pb = $first_overlap->b_Position;
		$clone = $self->new_Clone_from_tpf_Clone($contained_clones[$i]);
		
		# Now specify the position and orientation of the second clone
		if($pb->is_3prime) {
			$clone->seq_end($pb->position);
			$clone->strand(-1);
		}
		else {
			$clone->seq_start($pb->position);
			$clone->strand(1);
		}

		# Does this clone have an overlap with the subsequent contained clone?
		if($i < $#contained_clones) {
			$contained_clone_overlap = Hum::SequenceOverlap
	            ->fetch_by_SequenceInfo_pair($contained_clones[$i]->SequenceInfo, $contained_clones[$i+1]->SequenceInfo);
		}

		# If there's no overlap with a subsequent contained clone,
		# create a pseudo-clone corresponding to the container clone,
		# and use it as the "clone"
		if(!defined($contained_clone_overlap)) {
			# Use the last of the overlaps with the container
			if(scalar @overlaps == 0) {
				croak "Cannot find overlap between container clone " . $container_tpf_clone->accession . " and contained clone " . $contained_clones[$i]->accession . "\n";
			}
			
			# Finish up the contained clone
			$clone = $self->check_for_contained_clones($clone, $contained_clones[$i]);
			if($clone->strand == 1) {
				$clone->seq_end($overlaps[-1]->b_Position->position);
			}
			else {
				$clone->seq_start($overlaps[-1]->b_Position->position);
			}
			
			# Return to the container
			$clone = $self->new_Clone_from_tpf_Clone($container_tpf_clone);
			$clone->strand($container_clone->strand);
			if($clone->strand == 1) {
				$clone->seq_start($overlaps[-1]->a_Position->position);
			}
			else {
				$clone->seq_end($overlaps[-1]->a_Position->position);
			}
		}
		
	}

	return $clone;

}

sub check_for_contained_clones {
	my ($self, $clone, $tpf_clone) = @_;

	my @contained_clones = $tpf_clone->get_contained_clones;
	if(scalar @contained_clones > 0) {	
		return $self->_process_contained_contig($clone, $tpf_clone);
	}
	else {
		return $clone;
	}
}

sub insert_missing_overlap_pad {
    my( $self ) = @_;

    my $gap = $self->new_Gap;
    $gap->chr_length($self->missing_overlap_pad);
    return $gap;
}

sub _chr_end {
    my( $self, $_chr_end ) = @_;

    if (defined $_chr_end) {
        $self->{'__chr_end'} = $_chr_end;
    }
    return $self->{'__chr_end'};
}

sub catch_errors {

  my( $self, $catch_err ) = @_;

  if ( $catch_err ) {
    $self->{'_catch_errors'} = $catch_err;
  }
  return $self->{'_catch_errors'};
}

sub string {
    my( $self ) = @_;

    my $str = '';
    my $chr_end = 0;
    my $row_num = 0;
    my $name = $self->chr_name;
    my $catch_err = $self->catch_errors;

    foreach my $row ($self->fetch_all_Rows) {
      my $new_end;
      my $gap_str = 0;

      if ( $catch_err ){
        my ($chr_length);
        eval{$chr_length = $row->chr_length};

        if ( $@ ){
          #die $row->accession_sv;
          $gap_str = 1;
          $row->error_message($@);
        }
        $chr_length = 0 unless $chr_length;
        $new_end = $chr_end + $chr_length;
      }
      else {
        $new_end = $chr_end + $row->chr_length;
      }

      $str .= join("\t",
                   $name,
                   $chr_end + 1,
                   $new_end,
                   ++$row_num,
                   $row->elements) . "\n";

      if ( $catch_err ){
        # add a gap (5000 bps) after a problematic clone
        if ($gap_str){
          $chr_end = $new_end;
          $new_end = $chr_end + 5000;
          $str .= join("\t",
                       $name,
                       $chr_end + 1,
                       $new_end,
                       ++$row_num,
                       'N', 5000, 'contig', 'no') . "\n";
        }
      }

      $chr_end = $new_end;
    }

    return $str;
}

1;

__END__

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

