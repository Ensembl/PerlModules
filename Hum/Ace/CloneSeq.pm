
### Hum::Ace::CloneSeq

package Hum::Ace::CloneSeq;

use strict;
use Hum::Sequence::DNA;
use Carp;

sub new {
    my( $pkg ) = shift;
    
    return bless {
        '_SubSeq_list'  => [],
        }, $pkg;
}

sub sequence_name {
    my( $self, $sequence_name ) = @_;
    
    if ($sequence_name) {
        $self->{'_sequence_name'} = $sequence_name;
    }
    return $self->{'_sequence_name'} || confess "sequence_name not set";
}

sub ace_name {
    my( $self, $ace_name ) = @_;
    
    if ($ace_name) {
        $self->{'_ace_name'} = $ace_name;
    }
    return $self->{'_ace_name'} || confess "ace_name not set";
}

sub accession {
    my( $self, $accession ) = @_;
    
    if ($accession) {
        $self->{'_accession'} = $accession;
    }
    return $self->{'_accession'} || confess "accession not set";
}

sub golden_start {
    my( $self, $golden_start ) = @_;
    
    if ($golden_start) {
        $self->{'_golden_start'} = $golden_start;
    }
    return $self->{'_golden_start'} || confess "golden_start not set";
}

sub golden_end {
    my( $self, $golden_end ) = @_;
    
    if ($golden_end) {
        $self->{'_golden_end'} = $golden_end;
    }
    return $self->{'_golden_end'} || confess "golden_end not set";
}

sub golden_strand {
    my( $self, $golden_strand ) = @_;
    
    if (defined $golden_strand) {
        confess "Illegal golden_strand '$golden_strand'; must be '1' or '-1'"
            unless $golden_strand =~ /^-?1$/;
        $self->{'_golden_strand'} = $golden_strand
    }
    return $self->{'_golden_strand'} || confess "golden_strand not set";
}

sub add_SubSeq {
    my( $self, $SubSeq ) = @_;
    
    confess "'$SubSeq' is not a 'Hum::Ace::SubSeq'"
        unless $SubSeq->isa('Hum::Ace::SubSeq');
    push(@{$self->{'_SubSeq_list'}}, $SubSeq);
}

sub replace_SubSeq {
    my( $self, $sub, $old_name ) = @_;
    
    my $name = $old_name || $sub->name;
    my $ss_list = $self->{'_SubSeq_list'}
        or confess "No SubSeq list";
    for (my $i = 0; $i < @$ss_list; $i++) {
        my $this = $ss_list->[$i];
        if ($this->name eq $name) {
            splice(@$ss_list, $i, 1, $sub);
            return 1;
        }
    }
    confess "No such SubSeq to replace '$name'";
}

sub delete_SubSeq {
    my( $self, $name ) = @_;
    
    my $ss_list = $self->{'_SubSeq_list'}
        or confess "No SubSeq list";
    for (my $i = 0; $i < @$ss_list; $i++) {
        my $this = $ss_list->[$i];
        if ($this->name eq $name) {
            splice(@$ss_list, $i, 1);
            return 1;
        }
    }
    confess "No such SubSeq to delete '$name'";
}

sub get_all_SubSeqs {
    my( $self ) = @_;
    
    return @{$self->{'_SubSeq_list'}};
}

sub EnsEMBL_Contig {
    my( $self, $ens_contig ) = @_;
    
    if ($ens_contig) {
        my $class = 'Bio::EnsEMBL::DB::RawContigI';
        confess "'$ens_contig' is not a '$class' object"
            unless $ens_contig->isa($class);
        $self->{'_EnsEMBL_Contig'} = $ens_contig;
    }
    return $self->{'_EnsEMBL_Contig'};
}

sub new_SubSeq_from_ace_subseq_tag {
    my( $self, $ace_trans ) = @_;
    
    # Make a SubSeq object
    my $sub = Hum::Ace::SubSeq->new;
    
    $sub->process_ace_transcript($ace_trans);
    
    # Deal with exons not entirely contained in the golden path
    my $golden_start = $self->golden_start;
    my $golden_end   = $self->golden_end;
    #warn "gs=$golden_start  ge=$golden_end\n";
    foreach my $exon ($sub->get_all_Exons) {
        my $start = $exon->start;
        my $end   = $exon->end;
        
        if ($end < $golden_start or $start > $golden_end) {
            # Delete exons which are outside the golden path
            $sub->delete_Exon($exon);
        } else {
            # Trim exons to golden path
            if ($start < $golden_start) {
                $exon->start($golden_start);
                if ($sub->strand == 1) {
                    $exon->unset_phase;
                }
            }
            if ($end > $golden_end) {
                $exon->end($golden_end);
                if ($sub->strand == -1) {
                    $exon->unset_phase;
                }
            }
        }
    }
    
    $sub->validate;
    return $sub;    # May have zero Exons
}

#sub new_from_ace_handle_name {
#    my( $pkg, $ace, $ace_name ) = @_;
#
    #my $db = $ace->db;

    #my $self = $pkg->new;
    #$self->ace_name($ace_name);
    ## Get the DNA
    #my $seq = $self->store_Sequence_from_ace_handle($ace);

#    # These raw_queries are much faster than
#    # fetching the whole Genome_Sequence object!
#    $ace->raw_query("find Sequence $self_name");
#    my $sub_list = $ace->raw_query('show -a Subsequence');
#    $sub_list =~ s/\0//g;   # Remove any nulls
#    
#    while ($sub_list =~ /^Subsequence\s+"([^"]+)"\s+(\d+)\s+(\d+)/mg) {
#        my($name, $start, $end) = ($1, $2, $3);
#        eval{
#            my $t_seq = $ace->fetch(Sequence => $name)
#                or die "No such Subsequence '$name'\n";
#            my $sub = Hum::Ace::SubSeq
#                ->new_from_name_start_end_transcript_seq(
#                    $name, $start, $end, $t_seq,
#                    );
#            $sub->clone_Sequence($seq);
#            
#            # Flag that the sequence is in the db
#            $sub->is_archival(1);
#            
#            if (my $mt = $t_seq->at('Method[1]')) {
#                if (my $meth = $self->get_GeneMethod($mt->name)) {
#                    $sub->GeneMethod($meth);
#                }
#            }
#            
#            # Is there a Locus attached?
#            if (my $locus_tag = $t_seq->at('Visible.Locus[1]')) {
#                my $locus = $self->get_Locus($locus_tag->name);
#                $sub->Locus($locus);
#            } else {
#                #warn "No Locus attached to SubSeq '$name'\n";
#            }
#            
#            $self->add_SubSeq($sub);
#        };
#        if ($@) {
#            confess($@, "Error fetching '$name' ($start - $end):\n");
#        }
#    }
#    return $self;
#}

sub Sequence {
    my( $self, $seq ) = @_;
    
    if ($seq) {
        $self->{'_sequence_dna_object'} = $seq;
    }
    return $self->{'_sequence_dna_object'};
}

sub store_Sequence_from_ace_handle {
    my( $self, $ace ) = @_;
    
    my $seq = $self->new_Sequence_from_ace_handle($ace);
    $self->Sequence($seq);
}

sub new_Sequence_from_ace_handle {
    my( $self, $ace ) = @_;
    
    my $name = $self->ace_name;
    my $dna_obj = $ace->fetch(DNA => $name);
    if ($dna_obj) {
        my $dna_str = $dna_obj->fetch->at;
        #warn "Got DNA string ", length($dna_str), " long";
        my $seq = Hum::Sequence::DNA->new;
        $seq->name($name);
        $seq->sequence_string($dna_str);
        return $seq;
    } else {
        confess "No DNA object '$name'";
    }
}

1;

__END__

=head1 NAME - Hum::Ace::CloneSeq

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

