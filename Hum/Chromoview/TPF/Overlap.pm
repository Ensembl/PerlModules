package Hum::Chromoview::TPF::Overlap;

### Author: jt8@sanger.ac.uk

use strict;
use warnings;
use Hum::TPF::Row;
use Hum::SequenceOverlap;
use Hum::Chromoview::Utils qw(phase_2_status
    concat_js_params
    unixtime2YYYYMMDD
    datetime2unixTime
    get_chromoDB_handle
    authorize
    check_for_crossmatch_errors_by_accSv
    get_latest_overlap_statusdate_of_TPF);
use DateTime;
use POSIX qw(:signal_h);

sub new {
    my ($class, $current_row, $next_row) = @_;
    my $self = {
        '_current_row' => $current_row,
        '_next_row' => $next_row,
    };
    return bless ($self, $class);
}

sub current_row {
    my ($self) = @_;
    return $self->{'_current_row'};
}

sub chromo_dbh {
    my ($self, $chromo_dbh) = @_;
    
    if($chromo_dbh) {
        $self->{'_chromo_dbh'} = $chromo_dbh;
    }
    
    return $self->{'_chromo_dbh'};
}

sub next_row {
    my ($self) = @_;
    return $self->{'_next_row'};
}

sub sequence_overlap {
    my ($self) = @_;
    
    if(!exists($self->{'_sequence_overlap'})) {
        $self->_build_sequence_overlap;
    }
    
    return $self->{'_sequence_overlap'};
}

sub current_row_seq_info {
    my ($self) = @_;
    
    if(!exists($self->{'_current_row_seq_info'})) {
        $self->{'_current_row_seq_info'} = eval{$self->current_row->row->SequenceInfo;};
    }
    
    return $self->{'_current_row_seq_info'};
}

sub next_row_seq_info {
    my ($self) = @_;
    
    if(!exists($self->{'_next_row_seq_info'})) {
        $self->{'_next_row_seq_info'} = eval{$self->next_row->row->SequenceInfo;};
    }
    
    return $self->{'_next_row_seq_info'};
}

sub overlap_variation {
    my ($self) = @_;
    return (
        $self->sequence_overlap->percent_insertion
        + $self->sequence_overlap->percent_deletion
        + $self->sequence_overlap->percent_substitution
    );
}

sub overlap_length {
    my ($self) = @_;
    
    if(!exists($self->{'_overlap_length'})) {
    	$self->{'_overlap_length'} = $self->sequence_overlap->overlap_length;
    	if($self->current_row->contained_status eq 'CONTAINED') {
    		$self->{'_overlap_length'} = $self->current_row->sequence_length;
    	}
    	elsif($self->current_row->contained_status eq 'CONTAINER' or $self->current_row->contained_status eq 'CONTAINER_START') {
    		$self->{'_overlap_length'} = eval {$self->next_row_seq_info->sequence_length} ? $self->next_row_seq_info->sequence_length : '-';
    	}
    }
	return $self->{'_overlap_length'};
}

sub overlap_position {
    
    my ($self) = @_;
    
    my $overlap_position;
    if(defined($self->sequence_overlap)) {
    	my $a_overlap_end  = $self->sequence_overlap->a_Position->is_3prime == 1 ? "3'" : "5'";
    	my $b_overlap_end  = $self->sequence_overlap->b_Position->is_3prime == 1 ? "3'" : "5'";

    	my $a_dovetail_len = $self->sequence_overlap->a_Position->dovetail_length || '-';
    	my $b_dovetail_len = $self->sequence_overlap->b_Position->dovetail_length || '-';

    	my $dovetail_a = $a_dovetail_len ne '-' ? 'has_dovetail' : '';
    	my $dovetail_b = $b_dovetail_len ne '-' ? 'has_dovetail' : '';

    	my $overlapPos_a = $self->sequence_overlap->a_Position->position;
    	my $overlapPos_b = $self->sequence_overlap->b_Position->position;

		$overlap_position = qq{$a_overlap_end / $b_overlap_end <br> $overlapPos_a / $overlapPos_b <br> <span class="$dovetail_a">$a_dovetail_len</span> / <span class="$dovetail_b">$b_dovetail_len</span>};
    }
    elsif (my $crossmatch_error = $self->check_for_crossmatch_errors_by_accSv_with_timeout) { # and $i != $row_sum ){
        	$overlap_position = qq{<span class='crossmatch'> $crossmatch_error </span>};
	}
    return $overlap_position;
}

sub overlap_date_program_origin {
    my ($self) = @_;
    
   	my $ovPro = $self->sequence_overlap->program;
	if(length($ovPro) > 10) {
		substr($ovPro, 10, 500, '...');
	}
	$ovPro = qq{<span class='program'> $ovPro </span>} if $ovPro ne 'find_overlaps';
	my $dpo = join("<br>", $self->sequence_overlap->statusdate, $ovPro, $self->sequence_overlap->operator);

    
    return $dpo;
}

sub check_for_crossmatch_errors_by_accSv_with_timeout {
	my ($self) = @_;
	
	# POSIX code is intended to prevent possible problems with timing-out.
	my $mask = POSIX::SigSet->new( SIGALRM ); # signals to mask in the handler
    my $action = POSIX::SigAction->new(
        sub { die "connect timeout\n" },        # the handler code ref
        $mask,
        # not using (perl 5.8.2 and later) 'safe' switch or sa_flags
    );
    my $oldaction = POSIX::SigAction->new();
    sigaction( SIGALRM, $action, $oldaction );
	
	my $crossmatch_error;
	# Time out after 5 seconds
	eval {
		eval {
			alarm 5;
			$crossmatch_error = $self->check_for_crossmatch_errors_by_accSv($self->current_row->acc_sv);
		};
		alarm 0;
		die "$@" if $@;

	};
    sigaction( SIGALRM, $oldaction );  # restore original signal handler
	
	if($@) {
		warn $@;
		return;
	}
	else {
		return $crossmatch_error;
	}
}

sub overlap_quality {
    my ($self) = @_;
    my $overlap_alignment_link = join( '/',
        '../HumPub_OverlapAlignment',
        $self->current_row->acc_sv,
        $self->next_row->acc_sv
    );
    
    my $overlap_variation = $self->overlap_variation;
    if($overlap_variation > 0.4) {
        $overlap_variation = qq{<span class='bad_variation'>$overlap_variation</span>};
    }
    
    return qq{<a target='top' href="$overlap_alignment_link">} . $self->overlap_length . "</a><BR>" . $overlap_variation . "<BR>" . $self->sequence_overlap->status_description;
}

sub _build_sequence_overlap {
       my ($self) = @_;

	#--------------------------------
	# fetch overlap info from oracle
	#--------------------------------

    $self->{'_sequence_overlap'} = undef;

	if ( defined($self->current_row_seq_info) and defined($self->next_row_seq_info) ){

    	my $inf_a = $self->current_row_seq_info;
    	$inf_a->drop_Sequence;
    	my $inf_b = $self->next_row_seq_info;
    	$inf_b->drop_Sequence;

		if($self->current_row->contained_status eq 'NOT_CONTAINED') {
			$self->{'_sequence_overlap'} = Hum::SequenceOverlap->fetch_by_SequenceInfo_pair($inf_a, $inf_b);
		}
		elsif($self->current_row->contained_status =~ /^CONTAINER/ or $self->current_row->contained_status =~ /^CONTAINED/) {
			my @overlaps = Hum::SequenceOverlap->fetch_contained_by_SequenceInfo_pair($inf_a, $inf_b);
			# warn "Overlaps retrieved " . scalar @overlaps . " for $accession and " . $next_r->accession . "\n";
			if(scalar @overlaps > 0) {
				# If this is a container, we need the overlap at the start of the contained clone,
				# which will depend upon the strand
				if($self->current_row->contained_status =~ /^CONTAINER/) {
					@overlaps = sort {$a->a_Position->position <=> $b->a_Position->position} @overlaps;
					if($self->current_row->container_strand == 1) {
						$self->{'_sequence_overlap'} = $overlaps[0];
					}
					else {
						$self->{'_sequence_overlap'} = $overlaps[-1];
					}
				}
				# Conversely, if this is a contained clone, we need the overlap at the end of the contained clone
				if($self->current_row->contained_status =~ /^CONTAINED/) {
					@overlaps = sort {$a->b_Position->position <=> $b->b_Position->position} @overlaps;
					if($self->current_row->container_strand == 1) {
						$self->{'_sequence_overlap'} = $overlaps[-1];
					}
					else {
						$self->{'_sequence_overlap'} = $overlaps[0];
					}
				}
				
			}
		}
	}
	
	return;
    
}

sub certificate_html {
	my ($self) = @_;
	
	if(!exists($self->{'_certificate_html'})) {
    	
    	my $img_url = "/research/areas/bioinformatics/grc/gfx/";
    	if(defined($self->certificate_code)) {
        	if($self->certificate_code eq 'Y') {
        		my $mouseover_text = 'Certificate approved';
        		$self->{'_certificate_html'} = qq{<img src='$img_url/purple_light.png' alt='$mouseover_text' title='$mouseover_text'>};
        	}
        	elsif($self->certificate_code eq 'N') {
        		my $mouseover_text = 'Certificate rejected';
        		$self->{'_certificate_html'} = qq{<img src='$img_url/blue_light.png' alt='$mouseover_text' title='$mouseover_text'>};
        	}
        	elsif($self->certificate_code eq 'U') {
        		my $mouseover_text = 'Certificate submitted, not yet approved';
        		$self->{'_certificate_html'} = qq{<img src='$img_url/black_light.png' alt='$mouseover_text' title='$mouseover_text'>};
        	}
    	}
    	else {
    	    $self->{'_certificate_html'} = '';
    	}

	}
	
	return $self->{'_certificate_html'};
}

sub certificate_code {
	my ($self) = @_;

    if(!exists($self->{'_certificate_code'})) {
	
	   $self->{'_certificate_code'} = undef;
	   
    	if(defined($self->chromo_dbh)) {
    		my $certificate_query_handle = $self->chromo_dbh->prepare(q{select TC.code From seq_region SR, dna_align_feature DAF , tpf_best_alignment TBA, tpf_certificate TC WHERE SR.seq_region_id=DAF.seq_region_id AND SR.name=? AND DAF.hit_name=? AND DAF.dna_align_feature_id=TBA.daf_id AND DAF.dna_align_feature_id=TC.dna_align_feature_id});
    		my $certificate_result = $certificate_query_handle->execute($self->next_row->acc_sv, $self->current_row->acc_sv);
    		my @fields = $certificate_query_handle->fetchrow_array;
    		if(scalar @fields == 1) {
    			$self->{'_certificate_code'} = $fields[0];
    		}
    		else {
    			$certificate_result = $certificate_query_handle->execute($self->current_row->acc_sv, $self->next_row->acc_sv);
    			@fields = $certificate_query_handle->fetchrow_array;
    			if(scalar @fields == 1) {
    				$self->{'_certificate_code'} = $fields[0];
    			}
    		}
    	}
    	else {
    	    warn "No connection to chromoDB\n";
    	}
    }
	
	return $self->{'_certificate_code'};
}

sub data_for_chromoview {
    my ($self) = @_;
    
    return {
        'overlap_position' => $self->overlap_position,
        'overlap_quality' => $self->overlap_quality,
        'overlap_date_program_origin' => $self->overlap_date_program_origin,
        'certificate_icon' => $self->certificate_html,
    };
}

1;

__END__

=head1 AUTHOR

James Torrance email B<jt8@sanger.ac.uk>
