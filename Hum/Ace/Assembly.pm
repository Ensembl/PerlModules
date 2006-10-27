
### Hum::Ace::Assembly

package Hum::Ace::Assembly;

use strict;

use Hum::Ace::Locus;
use Hum::Ace::Method;
use Hum::Ace::SubSeq;
use Hum::Ace::Clone;
use Hum::Sequence::DNA;

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


sub Sequence {
    my( $self, $seq ) = @_;
    
    if ($seq) {
        $self->{'_sequence_dna_object'} = $seq;
    }
    return $self->{'_sequence_dna_object'};
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


sub clear_SimpleFeatures {
    my ($self) = @_;

    $self->{_SimpleFeatures} = [];
}

sub add_SimpleFeatures {
    my $self = shift @_;

    push @{$self->{_SimpleFeatures}}, @_;
}

sub set_SimpleFeatures {
    my $self = shift @_;

    $self->clear_SimpleFeatures();
    $self->add_SimpleFeatures( @_ );
}

sub get_SimpleFeatures {
    my ($self, $types) = @_;

    if($types) {
        my %valid_type = map { $_ => 1 } @$types;

        return grep { $valid_type{ $_->[0] } } @{$self->{_SimpleFeatures}};
    } else {
        return @{$self->{_SimpleFeatures}};
    }
}


sub express_data_fetch {
    my( $self, $ace ) = @_;

    my $clone_name = $self->ace_name;
    
    # These raw_queries are much faster than
    # fetching the whole Genome_Sequence object!
    $ace->raw_query("find Sequence $clone_name");

    # The SimpleFeatures we are intersted in (polyA etc...)
    # are only present on the top level assembly object.
    $self->set_SimpleFeatures( $ace->values_from_tag('Feature') );

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
    
    # To save memory we only store the DNA from this top level sequence object.
    $self->store_Sequence_from_ace_handle($ace);

    # Store the information from the clones
    foreach my $frag ($agp_frag_txt->values_from_tag('AGP_Fragment')) {
        my ($clone_name, $start, $end) = @{$frag}[0,1,2];
        my $strand = 1;
        if ($start > $end) {
            ($start, $end) = ($end, $start);
            $strand = -1;
        }

        my $clone = Hum::Ace::Clone->new;
        $clone->ace_name($clone_name);
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
    
    my $name = $self->ace_name;
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
    
    my $list = $self->{'_clone_list'} ||= [];
    push @$list, $clone;
}

sub clone_name_overlapping {
    my( $self, $pos ) = @_;
    
    #print STDERR "Getting: $self, $pos\n";
    
    my $list = $self->{'_clone_list'} or return;
    foreach my $clone (@$list) {
        if ($pos >= $clone->assembly_start and $pos <= $clone->assembly_end) {
            return $clone->name;
        }
    }
}

1;

__END__

=head1 NAME - Hum::Ace::Assembly

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk
