
### Hum::Analysis::Factory::ExonLocator

package Hum::Analysis::Factory::ExonLocator;

use strict;
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
    my $ex_list = [];
    for (my $i = 0; $i < @$exon_seqs; $i++) {
        #my $exon = $exon_seqs->[$i];
        my $feat = $features->[$i];
        @$feat = sort {$b->hit_length <=> $a->hit_length} @$feat;
        push(@$ex_list, shift @$feat);
    }
    
    # Check that features are colinear - no use when we are finding $gene->get_all_Exons

    # May return several sets in future when, for example
    # there are tandemly duplicated genes.
    return [$ex_list];
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

