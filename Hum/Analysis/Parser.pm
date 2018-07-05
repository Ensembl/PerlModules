=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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


### Hum::Analysis::Parser

package Hum::Analysis::Parser;

use strict;
use warnings;
use Carp;
use File::Path 'rmtree';

sub new {
    my ($pkg) = @_;

    return bless {}, $pkg;
}

sub get_all_Features {
    my ($self) = @_;

    my $all = [];
    while (my $f = $self->next_Feature) {
        push(@$all, $f);
    }
    return $all;
}

sub results_filehandle {
    my ($self, $results_filehandle) = @_;

    if ($results_filehandle) {
        $self->{'_results_filehandle'} = $results_filehandle;
    }
    return $self->{'_results_filehandle'};
}

sub close_results_filehandle {
    my ($self) = @_;

    if (my $fh = $self->{'_results_filehandle'}) {
        close($fh) or confess "Error from results filehandle exit($?)";
    }

    $self->{'_results_filehandle'} = undef;
}

sub temporary_directory {
    my ($self, $temporary_directory) = @_;

    if ($temporary_directory) {
        $self->{'_temporary_directory'} = $temporary_directory;
    }
    return $self->{'_temporary_directory'};
}

sub DESTROY {
    my ($self) = @_;

    if (my $dir = $self->temporary_directory) {
        # warn "Not removing '$dir'"; return;
        rmtree($dir);
    }
}

1;

__END__

=head1 NAME - Hum::Analysis::Parser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

