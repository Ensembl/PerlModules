
### Hum::Analysis::Factory::ExonLocator

package Hum::Analysis::Factory::ExonLocator;

use strict;
use warnings;
use Carp;
use Hum::Analysis::Factory::StringMatch;
use Hum::Analysis::Factory::CrossMatch;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub genomic_Sequence {
    my( $self, $genomic ) = @_;
    
    if ($genomic) {
        my $expected = 'Hum::Sequence::DNA';
        if (eval{ $genomic->isa($expected) }) {
            $self->{'_genomic'} = $genomic;
        } else {
            confess "Expected a '$expected' object  but got a '$genomic'";
        }
    }
    return $self->{'_genomic'};
}

sub find_best_Feature_set {
    my( $self, $exon_seqs ) = @_;
    
    my $sets = $self->find_Feature_sets($exon_seqs);
    return $sets->[0];
}

sub find_Feature_sets {
    my( $self, $exon_seqs ) = @_;
    
    my $features = $self->find_Features($exon_seqs);
    my ($fwd, $rev) = $self->split_Features_by_strand($features);
    $features = $self->best_occupied_set($fwd, $rev);
    my $ex_list = [];
    for (my $i = 0; $i < @$exon_seqs; $i++) {
        #my $exon = $exon_seqs->[$i];
        if ($features and my $feat = $features->[$i]) {
            @$feat = sort {$b->hit_length <=> $a->hit_length} @$feat;
            push(@$ex_list, shift @$feat);
        } else {
            push(@$ex_list, undef);
        }
    }
    
    # Check that features are colinear - no use when we are finding $gene->get_all_Exons
    # Could check splice sites

    # May return several sets in future when, for example
    # there are tandemly duplicated genes.
    return [$ex_list];
}

sub best_occupied_set {
    my( $self, @all_set ) = @_;
    
    my $max_set = undef;
    my $max = 0;
    for (my $i = 0; $i < @all_set; $i++) {
        my $set = $all_set[$i];
        my $score = 0;
        for (my $j = 0; $j < @$set; $j++) {
            if (my $feat_list = $set->[$j]) {
                # Increment score if we found features at this position
                $score++ if @$feat_list;
            }
        }
        if ($score > $max) {
            $max = $score;
            $max_set = $set;
        }
    }
    # $max_set will be undef if there are no features
    return $max_set;
}

sub split_Features_by_strand {
    my( $self, $feat_list ) = @_;
    
    my $fwd_set = [];
    my $rev_set = [];
    for (my $i = 0; $i < @$feat_list; $i++) {
        my $fwd = $fwd_set->[$i] = [];
        my $rev = $rev_set->[$i] = [];
        my $this = $feat_list->[$i];
        foreach my $feat (@$this) {
            # hit_strand is always 1 from StringMatch but
            # seq_strand is always 1 from CrossMatch.
            my $strand = $feat->seq_strand * $feat->hit_strand;
            if ($strand == 1) {
                push(@$fwd, $feat);
            }
            else {
                push(@$rev, $feat);
            }
        }
    }
    return ($fwd_set, $rev_set);
}

sub find_Features {
    my( $self, $exon_seqs ) = @_;
    
    my $genomic = $self->genomic_Sequence
        or confess "genomic_Sequence not set";
    
    my $features = [];
    foreach my $exon (@$exon_seqs) {
        my $str_matcher = Hum::Analysis::Factory::StringMatch->new;
        my $str_matches = $str_matcher->run($genomic, $exon);
        if (@$str_matches) {
            push(@$features, $str_matches);
        } else {
            my $factory = Hum::Analysis::Factory::CrossMatch->new;
            $factory->show_all_matches(1);
            my $parser = $factory->run($genomic, $exon);
            push(@$features, $parser->get_all_Features);
        }
    }
    return $features;
}

sub find_Features_cross_match_first {
    my( $self, $exon_seqs ) = @_;
    
    my $genomic = $self->genomic_Sequence
        or confess "genomic_Sequence not set";
    
    my $features = [];
    foreach my $exon (@$exon_seqs) {
        my $factory = Hum::Analysis::Factory::CrossMatch->new;
        $factory->show_all_matches(1);
        my $parser = $factory->run($genomic, $exon);
        my $matches = $parser->get_all_Features;
        if (@$matches) {
            push(@$features, $matches);
        } else {
            my $str_matcher = Hum::Analysis::Factory::StringMatch->new;
            push(@$features, $str_matcher->run($genomic, $exon));
        }
    }
    return $features;
}

1;

__END__

=head1 NAME - Hum::Analysis::Factory::ExonLocator

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

