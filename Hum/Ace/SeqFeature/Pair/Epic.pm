=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


### Hum::Ace::SeqFeature::Pair::Epic

package Hum::Ace::SeqFeature::Pair::Epic;

use strict;
use warnings;
use Hum::Ace::SeqFeature::Pair;
use vars '@ISA';

@ISA = ('Hum::Ace::SeqFeature::Pair');

sub algorithm {
    return 'epic';
}

sub cigar_string {
    my ($self, $cigar_string) = @_;

    if ($cigar_string) {
        $self->{'_cigar_string'} = $cigar_string;
    }
    return $self->{'_cigar_string'};
}

sub alignment_length {
    my ($self, $alignment_length) = @_;

    if ($alignment_length) {
        $self->{'_alignment_length'} = $alignment_length;
    }
    return $self->{'_alignment_length'};
}

sub percent_substitution {
    my ($self, $percent_substitution) = @_;

    if (defined $percent_substitution) {
        $self->{'_percent_substitution'} = $percent_substitution;
    }
    return $self->{'_percent_substitution'};
}

sub percent_insertion {
    my ($self, $percent_insertion) = @_;

    if (defined $percent_insertion) {
        $self->{'_percent_insertion'} = $percent_insertion;
    }
    return $self->{'_percent_insertion'};
}

sub percent_deletion {
    my ($self, $percent_deletion) = @_;

    if (defined $percent_deletion) {
        $self->{'_percent_deletion'} = $percent_deletion;
    }
    return $self->{'_percent_deletion'};
}

sub pretty_alignment_string {
    warn "Not implemented";
}

1;

__END__

=head1 NAME - Hum::Ace::SeqFeature::Pair::Epic

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

