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


### Hum::Chromosome::VitalStatistics::NameValue

package Hum::Chromosome::VitalStatistics::NameValue;

use strict;
use warnings;
use Carp;

sub new {
    my( $pkg ) = @_;

    my $self = bless {}, $pkg;
    return $self;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub value {
    my( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_value'} = $value;
    }
    return $self->{'_value'};
}

sub label {
    my( $self, $label ) = @_;
    
    if ($label) {
        $self->{'_label'} = $label;
    }
    return $self->{'_label'};
}



1;

__END__

=head1 NAME - Hum::Chromosome::VitalStatistics::NameValue

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

