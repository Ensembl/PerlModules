
### Hum::Ace::CloneSeq

package Hum::Ace::CloneSeq;

use strict;
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

sub ace_method {
    my( $self, $ace_method ) = @_;
    
    if ($ace_method) {
        $self->{'_ace_method'} = $ace_method;
    }
    return $self->{'_ace_method'} || confess "ace_method not set";
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

1;

__END__

=head1 NAME - Hum::Ace::CloneSeq

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

