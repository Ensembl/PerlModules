=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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


### Hum::ProjectDump::EMBL::Finished::Pooled

package Hum::ProjectDump::EMBL::Finished::Pooled;

use strict;
use warnings;
use Carp;

use Hum::Submission qw{
  accession_from_sanger_name
};
use Hum::Tracking qw{
  parent_project
};

use base qw{ Hum::ProjectDump::EMBL::Finished };

sub secondary {
    my ($self) = @_;

    unless ($self->{'_parent_acc_fetched'}) {
        my $parent = parent_project($self->project_name)
            or confess "No parent project";
        # the pooled project name will always be the sequence name
        my $second_acc = accession_from_sanger_name($parent);
        if (!$second_acc) {
            die "No accession for parent project $parent\n";
        }
        my $seen;
        foreach my $sec ($self->SUPER::secondary) {
            $seen = 1 if $sec eq $second_acc;
        }
        $self->add_secondary($second_acc) unless $seen;        
        $self->{'_parent_acc_fetched'} = 1;
    }

    return $self->SUPER::secondary;
}


1;

__END__

=head1 NAME - Hum::ProjectDump::EMBL::Finished::Pooled

=head1 AUTHOR

Mustapha Larbaoui B<email> ml6@sanger.ac.uk
