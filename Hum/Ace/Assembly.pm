
### Hum::Ace::Assembly

package Hum::Ace::Assembly;

use strict;

use Carp;

use Hum::Ace::Locus;
use Hum::Ace::Method;
use Hum::Ace::SubSeq;
use Hum::Ace::Clone;
use Hum::Ace::SeqFeature::Simple;
use Hum::Sequence::DNA;

sub new {
    my( $pkg ) = shift;
    
    return bless {
        '_SubSeq_list'  => [],
        }, $pkg;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub Sequence {
    my( $self, $seq ) = @_;
    
    if ($seq) {
        $self->{'_sequence_dna_object'} = $seq;
    }
    return $self->{'_sequence_dna_object'};
}

sub MethodCollection {
    my( $self, $MethodCollection ) = @_;
    
    if ($MethodCollection) {
        $self->{'_MethodCollection'} = $MethodCollection;
    }
    return $self->{'_MethodCollection'};
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
    confess "No such SubSeq '$name' to replace";
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


sub clear_SimpleFeatures {
    my ($self) = @_;

    $self->{'_SimpleFeature_list'} = [];
}

sub add_SimpleFeatures {
    my $self = shift;

    push @{ $self->{'_SimpleFeature_list'} }, @_;
    $self->{'_SimpleFeatures_are_sorted'} = 0;
}

sub set_SimpleFeature_list {
    my $self = shift;

    $self->clear_SimpleFeatures;
    $self->add_SimpleFeatures( @_ );
}

sub get_all_SimpleFeatures {
    my ($self) = @_;

    my $feat_list = $self->{'_SimpleFeature_list'}
      or return;
    unless ($self->{'_SimpleFeatures_are_sorted'}) {
        @$feat_list = sort {
            $a->seq_start <=> $b->seq_start
            || $a->seq_end <=> $b->seq_end
            || $a->method_name cmp $b->method_name
            || $a->score <=> $b->score
            || $a->seq_strand <=> $b->seq_strand
            || $a->text cmp $b->text
          } @$feat_list;
        $self->{'_SimpleFeatures_are_sorted'} = 1;
    }

    return @$feat_list;
}

sub filter_SimpleFeature_list_from_ace_handle {
    my ($self, $ace) = @_;

    my $coll = $self->MethodCollection
      or confess "No MethodCollection attached";

    # We are only interested in the "editable" features on the Assembly.
    my %mutable_method =
      map { lc $_->name, $_ } $coll->get_all_mutable_non_transcript_Methods;

    my $name = $self->name;
    my $seq  = $self->Sequence;
    $ace->raw_query("find Sequence $name");
    my $sf_list = $self->{'_SimpleFeature_list'} ||= [];
    foreach my $row ($ace->values_from_tag('Feature')) {
        my ($method_name, $start, $end, $score, $text) = @$row;
        my $method = $mutable_method{lc $method_name}
          or next;

        my $feat = Hum::Ace::SeqFeature::Simple->new;
        $feat->seq_Sequence($seq);
        $feat->seq_name($name);
        $feat->Method($method);
        if ($start <= $end) {
            $feat->seq_start($start);
            $feat->seq_end($end);
            $feat->seq_strand(1);
        }
        else {
            $feat->seq_start($end);
            $feat->seq_end($start);
            $feat->seq_strand(-1);
        }
        $feat->score($score);
        $feat->text($text);

        push @$sf_list, $feat;
    }
    #printf STDERR "Found %d editable SimpleFeatures\n", scalar @$sf_list;
}

sub ace_string {
    my ($self) = @_;
    
    my $name = $self->name;
    
    my $ace = qq{\nSequence "$name"\n};
    my $coll = $self->MethodCollection
      or confess "No MethodCollection attached";
    foreach my $method ($coll->get_all_mutable_non_transcript_Methods) {
        $ace .= sprintf qq{-D Feature "%s"\n}, $method->name;
    }
    
    $ace .= qq{\nSequence "$name"\n};
    
    foreach my $feat ($self->get_all_SimpleFeatures) {
        $ace .= $feat->ace_string;
    }
    
    return $ace;
}



sub express_data_fetch {
    my( $self, $ace ) = @_;

    my $name = $self->name;
    
    # To save memory we only store the DNA from this top level sequence object.
    $self->store_Sequence_from_ace_handle($ace);
    
    # These raw_queries are much faster than
    # fetching the whole Genome_Sequence object!
    $ace->raw_query("find Sequence $name");

    # The SimpleFeatures we are intersted in (polyA etc...)
    # are only present on the top level assembly object.
    $self->filter_SimpleFeature_list_from_ace_handle($ace);

    my( $err, %name_method, %name_locus );
    foreach my $sub_txt ($ace->values_from_tag('Subsequence')) {
        eval{
            my($name, $start, $end) = @$sub_txt;
            my $t_seq = $ace->fetch(Sequence => $name)
                or die "No such Subsequence '$name'\n";
            $name =~ s/^em://i;
            my $sub = Hum::Ace::SubSeq
                ->new_from_name_start_end_transcript_seq(
                    $name, $start, $end, $t_seq,
                    );
            $sub->clone_Sequence($self->Sequence);

            # Flag that the sequence is in the db
            $sub->is_archival(1);

            # Is there a Method attached?
            if (my $meth_tag = $t_seq->at('Method[1]')) {
                my $meth_name = $meth_tag->name;
                # We treat "GD:", "MPI:" etc... prefixed methods
                # the same as the non-prefixed methods.
                $meth_name =~ s/^[^:]+://;
                my $meth = $name_method{$meth_name};
                unless ($meth) {
                    $ace->raw_query("find Method $meth_name");
                    my $txt = Hum::Ace::AceText->new($ace->raw_query('show -a'));
                    $meth = Hum::Ace::Method->new_from_AceText($txt);
                    $name_method{$meth_name} = $meth;
                }
                $sub->GeneMethod($meth);
            }

            # Is there a Locus attached?
            if (my $locus_tag = $t_seq->at('Visible.Locus[1]')) {
                my $locus_name = $locus_tag->name;
                my $locus = $name_locus{$locus_name};
                unless ($locus) {
                    $locus = Hum::Ace::Locus->new_from_ace_tag($locus_tag);
                    $name_locus{$locus_name} = $locus;
                }
                $sub->Locus($locus);
            }

            $self->add_SubSeq($sub);
        };
        $err .= $@ if $@;
    }
    warn $err if $err;

    # Store the information from the clones
    $ace->raw_query("find Sequence $name");
    foreach my $frag ($ace->values_from_tag('AGP_Fragment')) {
        my ($clone_name, $start, $end) = @{$frag}[0,1,2];
        my $strand = 1;
        if ($start > $end) {
            ($start, $end) = ($end, $start);
            $strand = -1;
        }

        my $clone = Hum::Ace::Clone->new;
        $clone->name($clone_name);
        $clone->express_data_fetch($ace);
        $clone->assembly_start($start);
        $clone->assembly_end($end);
        $clone->assembly_strand($strand);
        
        $self->add_Clone($clone);
    }
}

sub store_Sequence_from_ace_handle {
    my( $self, $ace ) = @_;
    
    my $seq = $self->new_Sequence_from_ace_handle($ace);
    $self->Sequence($seq);
}

sub new_Sequence_from_ace_handle {
    my( $self, $ace ) = @_;
    
    my $name = $self->name;
    my $seq = Hum::Sequence::DNA->new;
    $seq->name($name);
    my ($dna_obj) = $ace->fetch(DNA => $name);
    if ($dna_obj) {
        my $dna_str = $dna_obj->fetch->at->name;
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

sub add_Clone {
    my( $self, $clone ) = @_;
    
    #print STDERR "Adding: $self, $name, $start, $end\n";
    
    my $list = $self->{'_Clone_list'} ||= [];
    push @$list, $clone;
}

sub get_all_Clones {
    my ($self) = @_;
    
    my $list = $self->{'_Clone_list'} or return;
    return @$list;
}

sub get_Clone {
    my ($self, $clone_name) = @_;
    
    my $clone;
    foreach my $this ($self->get_all_Clones) {
        if ($this->name eq $clone_name) {
            $clone = $this;
            last;
        }
    }
    confess "Can't find clone '$clone_name' in list"
      unless $clone;
}

sub replace_Clone {
    my( $self, $clone ) = @_;
    
    my $name = $clone->name;
    my $clone_list = $self->{'_Clone_list'}
        or confess "No Clone list";
    for (my $i = 0; $i < @$clone_list; $i++) {
        my $this = $clone_list->[$i];
        if ($this->name eq $name) {
            splice(@$clone_list, $i, 1, $clone);
            return 1;
        }
    }
    confess "No such Clone '$name' to replace";
}

sub clone_name_overlapping {
    my( $self, $pos ) = @_;
    
    #print STDERR "Getting: $self, $pos\n";
    
    my $list = $self->{'_Clone_list'} or return;
    foreach my $clone (@$list) {
        if ($pos >= $clone->assembly_start and $pos <= $clone->assembly_end) {
            return $clone->clone_name;
        }
    }
}

1;

__END__

=head1 NAME - Hum::Ace::Assembly

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

