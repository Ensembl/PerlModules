
### Hum::Ace::CloneSeq

package Hum::Ace::CloneSeq;

use strict;
use Carp;

use Hum::Sequence::DNA;
use Hum::Ace::Locus;
use Hum::Ace::GeneMethod;
use Hum::Ace::SubSeq;
use Hum::Ace::AceText;

sub new {
    my( $pkg ) = shift;
    
    return bless {
        '_SubSeq_list'  => [],
        }, $pkg;
}

sub new_from_name_and_db_handle {
    my( $pkg, $name, $db ) = @_;
    
    my $self = $pkg->new;
    $self->ace_name($name);
    $self->express_data_fetch($db);
    return $self;
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

sub trim_SubSeq_to_golden_path {
    my( $self, $sub ) = @_;
    
    # Deal with exons not entirely contained in the golden path
    my $golden_start = $self->golden_start;
    my $golden_end   = $self->golden_end;
    my $strand = $sub->strand;
    #warn "gs=$golden_start  ge=$golden_end\n";
    my @ex_list = $sub->get_all_Exons;
    if ($strand == -1) {
        @ex_list = reverse(@ex_list);
    }

    my $trim = 0;
    foreach (my $i = 0; $i < @ex_list; $i++) {
        my $exon = $ex_list[$i];
        my $start = $exon->start;
        my $end   = $exon->end;
        
        if ($end < $golden_start or $start > $golden_end) {
            #printf STDERR "Trimmed exon  %10d  %-10d  %s\n",
            #    $exon->start, $exon->end, $self->ace_name;
            #print STDERR "i=$i  #ex_list=$#ex_list\n";
            # Delete exons which are outside the golden path
            $sub->delete_Exon($exon);
            $sub->start_not_found(0) if $i == 0;
        } else {
            # Trim exons to golden path
            if ($start < $golden_start) {
                $exon->start($golden_start);
                if ($strand == 1) {
                    $sub->start_not_found(0);
                    $exon->unset_phase;
                }
            }
            if ($end > $golden_end) {
                $exon->end($golden_end);
                if ($strand == -1) {
                    $sub->start_not_found(0);
                    $exon->unset_phase;
                }
            }
        }
    }
    
    return $sub;    # May have zero Exons
}

sub set_golden_start_end_from_NonGolden_Features {
    my( $self, $ace ) = @_;
    
    my $seq = $self->Sequence or confess "Sequence not set";
    my $length = $seq->sequence_length;
    
    my $clone_name = $self->ace_name;
    $ace->raw_query("find Sequence $clone_name");
    my $feat_list = $ace->raw_query('show -a Feature');
    my $txt = Hum::Ace::AceText->new($feat_list);
    my( $g_start, $g_end );
    foreach my $f ($txt->get_values('Feature."?NonGolden')) {
        my ($start, $end) = @$f;
        if ($start == 1) {
            $g_start = $end + 1;
            $self->golden_start($g_start);
        }
        elsif ($end == $length) {
            $g_end = $start - 1;
            $self->golden_end($g_end);
        }
    }
    $self->golden_start(1) unless $g_start;
    $self->golden_end($length) unless $g_end;
}

sub express_data_fetch {
    my( $self, $ace ) = @_;

    my $clone_name = $self->ace_name;
    
    # Get the DNA
    my $seq = $self->store_Sequence_from_ace_handle($ace);
    
    # Get start and end on golden path
    $self->set_golden_start_end_from_NonGolden_Features($ace);

    # These raw_queries are much faster than
    # fetching the whole Genome_Sequence object!
    $ace->raw_query("find Sequence $clone_name");
    my $sub_list = $ace->raw_query('show -a Subsequence');
    my $txt = Hum::Ace::AceText->new($sub_list);
    
    my( $err, %name_method, %name_locus );
    foreach my $sub_txt ($txt->get_values('Subsequence')) {
        eval{
            my($name, $start, $end) = @$sub_txt;
            my $t_seq = $ace->fetch(Sequence => $name)
                or die "No such Subsequence '$name'\n";
            my $sub = Hum::Ace::SubSeq
                ->new_from_name_start_end_transcript_seq(
                    $name, $start, $end, $t_seq,
                    );
            $sub->clone_Sequence($seq);

            # Adding PolyA depends on having the clone Sequence first
            $sub->add_all_PolyA_from_ace($t_seq);

            # Flag that the sequence is in the db
            $sub->is_archival(1);

            # Is there a Method attached?
            if (my $meth_tag = $t_seq->at('Method[1]')) {
                my $meth_name = $meth_tag->name;
                my $meth = $name_method{$meth_name};
                unless ($meth) {
                    $meth = Hum::Ace::GeneMethod->new_from_ace_tag($meth_tag);
                    $name_method{$meth_name} = $meth;
                }
                $sub->GeneMethod($meth);
            }

            # Is there a Locus attached?
            if (my $locus_tag = $t_seq->at('Visible.Locus[1]')) {
                my $locus_name = $locus_tag->name;
                my $locus = $name_method{$locus_name};
                unless ($locus) {
                    $locus = Hum::Ace::Locus->new_from_ace_tag($locus_tag);
                    $name_method{$locus_name} = $locus;
                }
                $sub->Locus($locus);
            }

            $self->add_SubSeq($sub);
        };
        $err .= $@ if $@;
    }
    warn $err if $err;
}

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

sub add_support_to_Clone {
    my ($self ,$ens_ana)=@_;

    # Connect to appropriate enspipe database to get supporting evidence
    my $ens_ana_db = $ens_ana->get_EnsAnalysisDB;

    my $host=$ens_ana_db->host;
    my $db_name=$ens_ana_db->db_name;

    # get vc, contigs and features (but doesn't work)
    #my $ens_db_f = $ens_ana_db->db_adaptor;
    #my $ens_clone_f = $ens_db_f->get_Clone($self->accession);
    # (expect finished sequence - one contig)
    #my ($ens_contig_f) = $ens_clone_f->get_all_Contigs();
    #my $ens_contig_f_id=$ens_contig_f->id;
    #my $len=$ens_contig_f[0]->length;

    # fetching features off $ens_contig_f doesn't seem to work...
    my $ens_contig_f2=$ens_ana->get_EnsEMBL_VirtualContig_of_contig;
    #my $len2=$ens_contig_f2->length;
    #print "$seq_name: length: $len, $len2\n";

    my $n=0;
    # filter features
    foreach my $feature ($ens_contig_f2->get_all_SimilarityFeatures()){
	#print join ' ', $feature->analysis->dbID, $feature->primary_tag, $feature->source_tag, $feature->hseqname, 
	#$feature->start, $feature->end, $feature->hstart, $feature->hend, "\n";
	my $analysis = $feature->analysis;
	next if($analysis->logic_name=~/\./);
	$n++;
	push(@{$self->{'_supporting_evidence_object'}},$feature);
    }
    print "Fetched $n features from $host, $db_name for ".$self->sequence_name."\n";
    
}

sub get_all_support {
    my( $self ) = @_;
    
    if (my $se = $self->{'_supporting_evidence_object'}) {
        return @$se;
    } else {
        return;
    }
}

#sub DESTROY {
#    my( $self ) = @_;
#    
#    print STDERR "Clone ", $self->ace_name, " is released\n";
#}

1;

__END__

=head1 NAME - Hum::Ace::CloneSeq

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

