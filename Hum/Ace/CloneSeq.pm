
### Hum::Ace::CloneSeq

package Hum::Ace::CloneSeq;

use strict;
use Carp;

use Hum::Fox::AceData::GenomeSequence;

use Hum::Sequence::DNA;
use Hum::Ace::Locus;
use Hum::Ace::GeneMethod;
use Hum::Ace::SubSeq;
use Hum::Ace::AceText;
use Bio::Otter::Keyword;
use Bio::Otter::CloneRemark;
use Bio::Otter::Author;
use Bio::Otter::CloneInfo;
use Bio::Otter::AnnotatedClone;
use Bio::EnsEMBL::SimpleFeature;

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

sub make_Otter_CloneInfo {
    my ($self) = @_; 

    my @clone_remarks;
    foreach my $remark ($self->get_all_Remarks) {
        push @clone_remarks,new Bio::Otter::CloneRemark(-remark => $remark);
    }

    my @clone_keywords;
    foreach my $keyword ($self->get_all_Keywords) {
        push @clone_keywords,new Bio::Otter::Keyword(-name => $keyword);
    }

    my ($author_name, $edit_time) = Hum::Fox::AceData::GenomeSequence
        ->get_who_and_edit_time($self->sequence_name);
    if (! $author_name or $author_name eq 'jgrg') {
        $author_name = 'vega';
    }
    $edit_time ||= time;
    my $author = new Bio::Otter::Author(
        -name  => $author_name,
        -email => "$author_name\@sanger.ac.uk",
        );

    my $ott_clone_info = new Bio::Otter::CloneInfo 
                                     (-clone_id  => $self->EnsEMBL_Contig->clone->dbID,
                                      -author    => $author,
                                      -timestamp => 100,
                                      -is_active => 1,
                                      -remark    => \@clone_remarks,
                                      -keyword   => \@clone_keywords,
                                      -source    => 'SANGER');

    return $ott_clone_info;
}

sub make_Otter_Clone {
    my ($self) = @_; 

    my $clone_info = $self->make_Otter_CloneInfo;

    my $clone = $self->EnsEMBL_Contig->clone;

    bless $clone, 'Bio::Otter::AnnotatedClone';

    $clone->clone_info($clone_info);

    return $clone;
}

# Create simple features to represent polyA signals and sites
sub make_EnsEMBL_PolyA_Features {
    my ($self) = @_; 

    my $ana_adaptor = $self->EnsEMBL_Contig->adaptor->db->get_AnalysisAdaptor;

    confess "No analysis adaptor for PolyA conversion" unless $ana_adaptor;

    my @ens_polyAs;
    my %anahash;
    foreach my $polyA ($self->get_all_PolyAs) {
      if (scalar(@$polyA) == 5) {
        my $start = $polyA->[1];
        my $end   = $polyA->[2];
        my $sf;
        if ($start > $end) {
          $sf = new Bio::EnsEMBL::SimpleFeature(-start       => $end,
                                                -end         => $start,
                                                -strand      => -1,
                                                -score       => $polyA->[3],
                                                );
        } else {
          $sf = new Bio::EnsEMBL::SimpleFeature(-start       => $start,
                                                -end         => $end,
                                                -strand      => 1,
                                                -score       => $polyA->[3],
                                                );
        }
        my $type  = $polyA->[0];
        my $ana = $anahash{$type};
        unless ($ana) {
          $ana = $ana_adaptor->fetch_by_logic_name($type);
          unless ($ana) {
            $ana = Bio::EnsEMBL::Analysis->new(
                -LOGIC_NAME => $type,
                );
            $ana_adaptor->store($ana);
          }
          $anahash{$type} = $ana;
        }
        $sf->analysis($ana);
        $sf->contig($self->EnsEMBL_Contig);
        $sf->display_label($polyA->[4]);
  
        push @ens_polyAs, $sf;
      }
    }
    return \@ens_polyAs;
}

sub EnsEMBL_Contig {
    my( $self, $ens_contig ) = @_;
    
    if ($ens_contig) {
        my $class = 'Bio::EnsEMBL::RawContig';
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
    
    my $key_list = $ace->raw_query('show -a Keyword');
    my $keytxt = Hum::Ace::AceText->new($key_list);
    foreach my $keyword ($keytxt->get_values('Keyword')) {
      if (defined($keyword->[0])) {
        $self->add_Keyword($keyword->[0]);
      }
    }

    my $rem_list = $ace->raw_query('show -a Annotation_remark');
    my $remtxt = Hum::Ace::AceText->new($rem_list);
    foreach my $remark ($remtxt->get_values('Annotation_remark')) {
      if (defined($remark->[0])) {
        $self->add_Remark("Annotation_remark- " . $remark->[0]);
      }
    }

    my $dump_list = $ace->raw_query('show -a EMBL_dump_info');
    my $dumptxt = Hum::Ace::AceText->new($dump_list);
    foreach my $embldump ($dumptxt->get_values('EMBL_dump_info.DE_line')) {
      if (defined($embldump->[0])) {
        $self->add_Remark("EMBL_dump_info.DE_line- " . $embldump->[0]);
      }
    }

    my $polyA_list = $ace->raw_query('show -a Feature');
    my $polyAtxt = Hum::Ace::AceText->new($polyA_list);
    foreach my $polyA ($polyAtxt->get_values('Feature')) {
      if ($polyA->[0] =~ /^polyA/) {
        $self->add_PolyA($polyA);
      }
    } 

    # Store clone spans.  These are used to show the annotator
    # the borders between clones in the fMap display, and to
    # choose the names of new sequences created in XaceSeqChooser
    my $cle_list = $ace->raw_query('show -a Clone_left_end');
    my $cle_txt = Hum::Ace::AceText->new($cle_list);
    my( %name_pos );
    foreach my $cle ($cle_txt->get_values('Clone_left_end')) {
        my ($name, $left) = @$cle;
        $name_pos{$name} = [$left];
    }
    my $cre_list = $ace->raw_query('show -a Clone_right_end');
    my $cre_txt = Hum::Ace::AceText->new($cre_list);
    foreach my $cre ($cre_txt->get_values('Clone_right_end')) {
        my ($name, $right) = @$cre;
        my $pos_array = $name_pos{$name} or next;
        push(@$pos_array, $right);
    }
    while (my ($name, $pos) = each %name_pos) {
        if (@$pos == 2) {
            $self->add_clone_span($name, @$pos);
        }
    }

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
            ### This was never used
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
    my $seq = Hum::Sequence::DNA->new;
    $seq->name($name);
    my $dna_obj = $ace->fetch(DNA => $name);
    if ($dna_obj) {
        my $dna_str = $dna_obj->fetch->at;
        #warn "Got DNA string ", length($dna_str), " long";
        $seq->sequence_string($dna_str);
    } else {
        my $genomic = $ace->fetch(Sequence => $name)
            or confess "Can't fetch Sequence '$name' : ", Ace->error;
        my $dna_str = $genomic->asDNA
            or confess "asDNA didn't fetch the DNA : ", Ace->error;
        $dna_str =~ s/^>.+//m
            or confess "Can't strip fasta header";
        $dna_str =~ s/\s+//g;
        
        ### Nasty hack sMap is putting dashes
        ### on the end of the sequence.
        $dna_str =~ s/[\s\-]+$//;
        
        $seq->sequence_string($dna_str);
        
        #use Hum::FastaFileIO;
        #my $debug = Hum::FastaFileIO->new_DNA_IO("> /tmp/spandit-debug.seq");
        #$debug->write_sequences($seq);
    }
    warn "Sequence '$name' is ", $seq->sequence_length, " long\n";
    return $seq;
}

sub add_Keyword {
    my($self,$keyword)=@_;
    push(@{$self->{'_Keywords'}},$keyword);
}

sub get_all_Keywords {
    my($self)=@_;
    if($self->{'_Keywords'}){
        return @{$self->{'_Keywords'}};
    }else{
        return ();
    }
}

sub add_Remark {
    my($self,$remark)=@_;
    push(@{$self->{'_Remarks'}},$remark);
}
sub get_all_Remarks {
    my($self)=@_;
    if($self->{'_Remarks'}){
        return @{$self->{'_Remarks'}};
    }else{
        return ();
    }
}

sub add_PolyA {
    my($self,$polyAref)=@_;
    push(@{$self->{'_PolyAs'}},$polyAref);
}
sub get_all_PolyAs {
    my($self)=@_;
    if($self->{'_PolyAs'}){
        return @{$self->{'_PolyAs'}};
    }else{
        return ();
    }
}

sub add_clone_span {
    my( $self, $name, $start, $end ) = @_;
    
    print STDERR "Adding: $self, $name, $start, $end\n";
    
    my $list = $self->{'_clone_span_list'} ||= [];
    push(@$list, [$name, $start, $end]);
}

sub clone_name_overlapping {
    my( $self, $pos ) = @_;
    
    print STDERR "Getting: $self, $pos\n";
    
    my $list = $self->{'_clone_span_list'} or return;
    foreach my $span (@$list) {
        if ($pos >= $span->[1] and $pos <= $span->[2]) {
            return $span->[0];
        }
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

