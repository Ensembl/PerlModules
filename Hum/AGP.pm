
### Hum::AGP

package Hum::AGP;

use strict;
use Carp;
use Hum::AGP::Row::Clone;
use Hum::AGP::Row::Gap;
use Hum::SequenceOverlap;

sub new {
    my( $pkg ) = @_;

    return bless {
        '_rows' => [],
        }, $pkg;
}

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

sub allow_unfinished {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_allow_unfinished'} = $flag ? 1 : 0;
    }
    return $self->{'_allow_unfinished'};
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

sub add_Row {
    my( $self, $row ) = @_;
    
    push(@{$self->{'_rows'}}, $row);
}

sub process_TPF {
    my( $self, $tpf ) = @_;

    my @rows = $tpf->fetch_all_Rows;
    my $contig = [];
    my $min_phase  = $self->min_htgs_phase;
    unless ($min_phase) {
        if ($self->allow_unfinished) {
            $min_phase = 1;
        } else {
            $min_phase = 2;
        }
    }
    for (my $i = 0; $i < @rows; $i++) {
        my $row = $rows[$i];
        if ($row->is_gap) {
            $self->_process_contig($contig) if @$contig;
            $contig = [];
            my $gap = $self->new_Gap;
            $gap->chr_length($row->gap_length || $self->unknown_gap_length);
            $gap->set_remark_from_Gap($row);
        } else {
            my $inf = $row->SequenceInfo;
            my $phase = $inf ? $inf->htgs_phase : 0;
            if ($phase >= $min_phase) {
                push(@$contig, $row);
            } else {
                printf STDERR "Skipping HTGS_PHASE$phase sequence '%s'\n",
                    $row->sanger_clone_name;
                $self->_process_contig($contig) if @$contig;
                $contig = [];
                my $gap = $self->new_Gap;
                $gap->chr_length(50_000);
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
    }
    $self->_process_contig($contig) if @$contig;
}

sub _process_contig {
    my( $self, $contig ) = @_;
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
            $cl->strand($strand || 1);
            
            $self->insert_missing_overlap_pad;
            $strand = undef;
            $cl = $self->new_Clone_from_tpf_Clone($contig->[$i]);
            next;
        }
        
        my $pa = $over->a_Position;
        my $pb = $over->b_Position;
        
        my $miss_join = 0;
        if ($pa->is_3prime) {
            if ($strand and $was_3prime) {
                $self->insert_missing_overlap_pad;
                $strand = undef;
                $miss_join = 3;
            }
            $cl->seq_end($pa->position);
        } else {
            if ($strand and ! $was_3prime) {
                $self->insert_missing_overlap_pad;
                $strand = undef;
                $miss_join = 5;
            }
            $cl->seq_start($pa->position);
        }
        
        # Report miss-join errors
        if ($miss_join) {
            printf STDERR "Double %d-prime join to '%s'\n",
                $miss_join, $cl->accession_sv;
        }
        
        unless ($strand) {
            # Not set for first pair, or following miss-join
            $strand = $pa->is_3prime ? 1 : -1;
        }
        $cl->strand($strand);
        
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
    $cl->strand($strand || 1);
}

sub insert_missing_overlap_pad {
    my( $self ) = @_;
    
    my $gap = $self->new_Gap;
    $gap->chr_length($self->missing_overlap_pad);
    $gap->remark("clone\tno");
}

sub _chr_end {
    my( $self, $_chr_end ) = @_;
    
    if (defined $_chr_end) {
        $self->{'__chr_end'} = $_chr_end;
    }
    return $self->{'__chr_end'};
}

sub string {
    my( $self ) = @_;
    
    my $str = '';
    my $chr_end = 0;
    my $row_num = 0;
    my $name = $self->chr_name;
    foreach my $row ($self->fetch_all_Rows) {
        my $new_end = $chr_end + $row->chr_length;
        $str .= join("\t",
            $name,
            $chr_end + 1,
            $new_end,
            ++$row_num,
            $row->elements) . "\n";
        $chr_end = $new_end;
    }
    return $str;
}

1;

__END__

=head1 NAME - Hum::AGP

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

