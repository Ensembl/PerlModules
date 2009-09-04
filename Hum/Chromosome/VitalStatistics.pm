
### Hum::Chromosome::VitalStatistics

package Hum::Chromosome::VitalStatistics;

use strict;
use warnings;
use Carp;
use Hum::Chromosome::VitalStatistics::NameValue;

sub new {
    my( $pkg ) = @_;

    my $self = bless {}, $pkg;
    $self->gene_lengths(        []);
    $self->exon_lengths(        []);
    $self->intron_lengths(      []);
    $self->transcript_counts(   []);
    $self->exon_counts(         []);
    $self->splice_counts(
        {
            0   => 0,
            1   => 0,
            2   => 0,
        });
    return $self;
}

sub merge {
    my( $self, $donor ) = @_;
    
    foreach my $method (qw{
        gene_lengths
        exon_lengths
        intron_lengths
        transcript_counts
        exon_counts
        })
    {
        my $self_a =  $self->$method();
        my $donr_a = $donor->$method();
        push @$self_a, @$donr_a;
    }
    
    my $self_splice = $self->splice_counts;
    my $donr_splice = $donor->splice_counts;
    while (my ($type, $count) = each %$donr_splice) {
        $self_splice->{$type} += $count;
    }
    
    foreach my $method (qw{
        shortest_gene
        shortest_exon
        })
    {
        my $donr_nv = $donor->$method() or next;
        my $self_nv =  $self->$method();
        if (! $self_nv or $donr_nv->value < $self_nv->value) {
            $self->$method($donr_nv);
        }
    }
    
    foreach my $method (qw{
        longest_gene
        longest_exon
        longest_intron
        most_transcripts
        most_exons
        })
    {
        my $self_nv =  $self->$method();
        my $donr_nv = $donor->$method() or next;
        if (! $self_nv or $donr_nv->value > $self_nv->value) {
            $self->$method($donr_nv);
        }
    }
    
    $self->single_exon_gene_count(
        $self->single_exon_gene_count
      + $donor->single_exon_gene_count);
}

sub test_count {
    my( $self, $test_count ) = @_;
    
    if (defined $test_count) {
        $self->{'_test_count'} = $test_count;
    }
    return $self->{'_test_count'};
}

sub make_stats {
    my( $self, $slice ) = @_;
    
    my $type = $self->gene_type or confess "gene_type not set";
    
    my $gene_lengths        = $self->gene_lengths;
    my $exon_lengths        = $self->exon_lengths;
    my $intron_lengths      = $self->intron_lengths;
    my $transcript_counts   = $self->transcript_counts;
    my $exon_counts         = $self->exon_counts;
    my $splice_counts       = $self->splice_counts;

    my $test_count = $self->test_count;
    my $gene_i = 0;
    my $gene_count = 0;
    
    my $gene_aptr = $slice->adaptor->db->get_GeneAdaptor;
    # list_current_dbIDs_for_Slice_by_type is otter API only:
    my $id_list = $gene_aptr->list_current_dbIDs_for_Slice_by_type($slice, $type);
    my $i = 0;
    foreach my $id (@$id_list) {
        my $gene = $gene_aptr->fetch_by_dbID($id);
        $gene->transform($slice);

        unless ($gene->type eq $type) {
            confess sprintf "Gene '%s' does not have type '%s' but '%s'",
                $gene->stable_id, $type, $gene->type;
        }
        my $name;
        if ($gene->can('gene_info')) {
            $name = $gene->gene_info->name->name;
            if ($name =~ /^[A-Z]+:/) {
                warn "Skipping gene '$name'\n";
                next;
            }
        }

        $gene_count++;
        
        # Stats from the gene
        eval { push @$gene_lengths, $gene->length; };
        
        if ($@) {
            warn "Error with gene '$name': $@";
            next;
        }
        
        $self->save_longest_gene($gene);
        $self->save_shortest_gene($gene);
        $self->save_most_transcripts($gene);
        $self->save_most_exons($gene);
        push @$transcript_counts, scalar @{$gene->get_all_Transcripts};
        foreach my $transcript (@{$gene->get_all_Transcripts}) {
            my $exons = $transcript->get_all_Exons;
            for (my $i = 0; $i < @$exons; $i++) {
                my $ex = $exons->[$i];
                $self->save_longest_exon($ex);

                # Don't use the first or last exon to find the shortest
                if (@$exons == 1 or ! ($i == 0 or $i == $#$exons)) {
                    $self->save_shortest_exon($ex);
                }
            }
        }
        
        # Stats from the longest transcript
        my $trans = $self->get_longest_transcript($gene);
        foreach my $exon (@{$trans->get_all_Exons}) {
            push(@$exon_lengths, $exon->length);
        }
        foreach my $int (@{$trans->get_all_Introns}) {
            $self->save_longest_intron($int);
            push @$intron_lengths, $int->length;
        }
        push @$exon_counts, scalar @{$trans->get_all_Exons};
        
        # Count single exon genes or splice phases
        my $exons = $trans->get_all_Exons;
        if (@$exons == 1) {
            $self->increment_single_exon_gene_count;
        } else {
            for (my $i = 0; $i < @$exons - 1; $i++) {
                my $ex = $exons->[$i];
                my $end_phase = $ex->end_phase;
                #warn "end_phase = $end_phase\n";
                if ($end_phase != -1) {
                    $splice_counts->{$end_phase}++;
                }
            }
        }
    }
    $self->gene_count($gene_count);
}

sub gene_count {
    my( $self, $gene_count ) = @_;
    
    if (defined $gene_count) {
        $self->{'_gene_count'} = $gene_count;
    }
    return $self->{'_gene_count'} || 0;
}

sub save_longest_gene {
    my( $self, $gene ) = @_;
    
    if (my $long = $self->longest_gene) {
        if ($gene->length > $long->value) {
            $long->name($gene->gene_info->name->name);
            $long->value($gene->length);
        }
    } else {
        $long = Hum::Chromosome::VitalStatistics::NameValue->new;
        $long->label('Longest genomic gene');
        $long->name($gene->gene_info->name->name);
        $long->value($gene->length);
        $self->longest_gene($long);
    }
}

sub save_shortest_gene {
    my( $self, $gene ) = @_;
    
    if (my $short = $self->shortest_gene) {
        if ($gene->length < $short->value) {
            $short->name($gene->gene_info->name->name);
            $short->value($gene->length);
        }
    } else {
        $short = Hum::Chromosome::VitalStatistics::NameValue->new;
        $short->label('Shortest genomic gene');
        $short->name($gene->gene_info->name->name);
        $short->value($gene->length);
        $self->shortest_gene($short);
    }
}

sub save_longest_exon {
    my( $self, $exon ) = @_;
    
    if (my $long = $self->longest_exon) {
        if ($exon->length > $long->value) {
            $long->name($exon->stable_id);
            $long->value($exon->length);
        }
    } else {
        $long = Hum::Chromosome::VitalStatistics::NameValue->new;
        $long->label('Longest exon');
        $long->name($exon->stable_id);
        $long->value($exon->length);
        $self->longest_exon($long);
    }
}

sub save_shortest_exon {
    my( $self, $exon ) = @_;
    
    if (my $short = $self->shortest_exon) {
        if ($exon->length < $short->value) {
            $short->name($exon->stable_id);
            $short->value($exon->length);
        }
    } else {
        $short = Hum::Chromosome::VitalStatistics::NameValue->new;
        $short->label('Shortest exon');
        $short->name($exon->stable_id);
        $short->value($exon->length);
        $self->shortest_exon($short);
    }
}

sub save_longest_intron {
    my( $self, $intron ) = @_;
    
    if (my $long = $self->longest_intron) {
        if ($intron->length > $long->value) {
            $long->name($intron->stable_id);
            $long->value($intron->length);
        }
    } else {
        $long = Hum::Chromosome::VitalStatistics::NameValue->new;
        $long->label('Longest intron');
        $long->name($intron->stable_id);
        $long->value($intron->length);
        $self->longest_intron($long);
    }
}


sub save_most_transcripts {
    my( $self, $gene ) = @_;
    
    my $count = scalar @{$gene->get_all_Transcripts};
    if (my $most = $self->most_transcripts) {
        if ($count > $most->value) {
            $most->name($gene->stable_id);
            $most->value($count);
        }
    } else {
        $most = Hum::Chromosome::VitalStatistics::NameValue->new;
        $most->label('Most transcripts');
        $most->name($gene->stable_id);
        $most->value($count);
        $self->most_transcripts($most);
    }
}

sub save_most_exons {
    my( $self, $gene ) = @_;
    
    my $max_exons = 0;
    my( $trans );
    foreach my $tr (@{$gene->get_all_Transcripts}) {
        my $count = scalar @{$tr->get_all_Exons};
        if ($count > $max_exons) {
            $max_exons = $count;
            $trans = $tr;
        }
    }
    
    if (my $most = $self->most_exons) {
        if ($max_exons > $most->value) {
            $most->name($trans->stable_id);
            $most->value($max_exons);
        }
    } else {
        $most = Hum::Chromosome::VitalStatistics::NameValue->new;
        $most->label('Most exons');
        $most->name($trans->stable_id);
        $most->value($max_exons);
        $self->most_exons($most);
    }
}

sub get_longest_transcript {
    my( $self, $gene ) = @_;
    
    my( @length_transcript );
    foreach my $tr (@{$gene->get_all_Transcripts}) {
        my $exon_length_sum = 0;
        foreach my $exon (@{$tr->get_all_Exons}) {
            $exon_length_sum += $exon->length;
        }
        push @length_transcript, [$exon_length_sum, $tr];
    }
    my ($longest) = sort {$b->[0] <=> $a->[0]} @length_transcript;
    my $trans = $longest->[1];
    return $trans;
}

sub gene_type {
    my( $self, $gene_type ) = @_;
    
    if ($gene_type) {
        $self->{'_gene_type'} = $gene_type;
    }
    return $self->{'_gene_type'};
}


sub single_exon_gene_count {
    my( $self, $single_exon_gene_count ) = @_;
    
    if ($single_exon_gene_count) {
        $self->{'_single_exon_gene_count'} = $single_exon_gene_count;
    }
    return $self->{'_single_exon_gene_count'} || 0;
}

sub increment_single_exon_gene_count {
    my( $self ) = @_;
    
    $self->{'_single_exon_gene_count'}++;
}


### These properties are all arrays of numbers:

sub gene_lengths {
    my( $self, $gene_lengths ) = @_;
    
    if ($gene_lengths) {
        $self->{'_gene_lengths'} = $gene_lengths;
    }
    return $self->{'_gene_lengths'};
}

sub exon_lengths {
    my( $self, $exon_lengths ) = @_;
    
    if ($exon_lengths) {
        $self->{'_exon_lengths'} = $exon_lengths;
    }
    return $self->{'_exon_lengths'};
}

sub intron_lengths {
    my( $self, $intron_lengths ) = @_;
    
    if ($intron_lengths) {
        $self->{'_intron_lengths'} = $intron_lengths;
    }
    return $self->{'_intron_lengths'};
}

sub transcript_counts {
    my( $self, $transcript_counts ) = @_;
    
    if ($transcript_counts) {
        $self->{'_transcript_counts'} = $transcript_counts;
    }
    return $self->{'_transcript_counts'};
}

sub exon_counts {
    my( $self, $exon_counts ) = @_;
    
    if ($exon_counts) {
        $self->{'_exon_counts'} = $exon_counts;
    }
    return $self->{'_exon_counts'};
}

### These properties are all Hum::Chromosome::VitalStatistics::NameValue objects:

sub longest_gene {
    my( $self, $longest_gene ) = @_;
    
    if ($longest_gene) {
        $self->{'_longest_gene'} = $longest_gene;
    }
    return $self->{'_longest_gene'};
}

sub shortest_gene {
    my( $self, $shortest_gene ) = @_;
    
    if ($shortest_gene) {
        $self->{'_shortest_gene'} = $shortest_gene;
    }
    return $self->{'_shortest_gene'};
}

sub longest_exon {
    my( $self, $longest_exon ) = @_;
    
    if ($longest_exon) {
        $self->{'_longest_exon'} = $longest_exon;
    }
    return $self->{'_longest_exon'};
}

sub shortest_exon {
    my( $self, $shortest_exon ) = @_;
    
    if ($shortest_exon) {
        $self->{'_shortest_exon'} = $shortest_exon;
    }
    return $self->{'_shortest_exon'};
}

sub longest_intron {
    my( $self, $longest_intron ) = @_;
    
    if ($longest_intron) {
        $self->{'_longest_intron'} = $longest_intron;
    }
    return $self->{'_longest_intron'};
}

sub most_transcripts {
    my( $self, $most_transcripts ) = @_;
    
    if ($most_transcripts) {
        $self->{'_most_transcripts'} = $most_transcripts;
    }
    return $self->{'_most_transcripts'};
}

sub most_exons {
    my( $self, $most_exons ) = @_;
    
    if ($most_exons) {
        $self->{'_most_exons'} = $most_exons;
    }
    return $self->{'_most_exons'};
}


### For counting splice junctions

sub splice_counts {
    my( $self, $splice_counts ) = @_;
    
    if ($splice_counts) {
        $self->{'_splice_counts'} = $splice_counts;
    }
    return $self->{'_splice_counts'};
}

sub median {
    my( $self, $values ) = @_;
    
    @$values = sort {$a <=> $b} @$values;
    my $count = scalar @$values;
    if ($count % 2) {
        # odd number of values
        return $values->[($count - 1) / 2];
    } else {
        # even number of values
        my $i = $count / 2;
        return(
            ($values->[$i-1] + $values->[$i]) / 2
            );
    }
}




1;

__END__

=head1 NAME - Hum::Chromosome::VitalStatistics

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

