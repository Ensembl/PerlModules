=head1 LICENSE

Copyright [2018-2020] EMBL-European Bioinformatics Institute

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


### Hum::Ace::SeqFeature::Simple

package Hum::Ace::SeqFeature::Simple;
# is given mix-ins by Bio::Otter::ZMap::XML::SeqFeature::Simple

use strict;
use warnings;
use Carp;
use base 'Hum::Ace::SeqFeature';

sub Method {
    my ($self, $Method) = @_;

    if ($Method) {
        $self->{'_Method'} = $Method;
    }
    return $self->{'_Method'};
}

sub method_name {
    my $self = shift;

    confess "read-only method" if @_;

    my $meth = $self->Method or return;
    return $meth->name;
}

sub text {
    my ($self, $text) = @_;

    if ($text) {
        $self->{'_text'} = $text;
    }
    return $self->{'_text'};
}

sub ace_string {
    my ($self) = @_;

    my ($start, $end);
    if ($self->seq_strand == 1) {
        $start = $self->seq_start;
        $end   = $self->seq_end;
    }
    else {
        $start = $self->seq_end;
        $end   = $self->seq_start;
    }

    return sprintf qq{Feature "%s" %d %d %.3f "%s"\n},
      $self->method_name,
      $start, $end,
      $self->score, $self->text;
}

sub ensembl_dbID {
    my ($self, @args) = @_;
    ($self->{'_ensembl_dbID'}) = @args if @args;
    my $ensembl_dbID = $self->{'_ensembl_dbID'};
    return $ensembl_dbID;
}


1;

__END__

=head1 NAME - Hum::Ace::SeqFeature::Simple

=head1 DESCRIPTION

Subclass of C<Hum::Ace::SeqFeature> used to
represent simple features edited in otterlace,
such as polyA signals and sites.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

