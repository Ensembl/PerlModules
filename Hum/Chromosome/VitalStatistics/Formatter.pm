=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

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


### Hum::Chromosome::VitalStatistics::Formatter

package Hum::Chromosome::VitalStatistics::Formatter;

use strict;
use warnings;
use Carp;
use Symbol 'gensym';

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub file {
    my( $self, $file ) = @_;
    
    if (ref($file)) {
        $self->{'_file'} = $file;
    }
    elsif ($file) {
        my $fh = gensym();
        open $fh, "> $file" or confess "Can't write to '$file' : $!";
        $self->{'_file'} = $fh;
    }
    return $self->{'_file'} || \*STDOUT;
}

sub head {
    my( $self, $head ) = @_;
    
    if ($head) {
        $self->{'_head'} = $head;
    }
    return $self->{'_head'};
}

sub note {
    return 'Note: Exon and Intron statistics are derived from the longest transcript';
}

sub make_report {
    my( $self ) = @_;
    
    confess sprintf "Class '%s' does not implement the make_report method",
        ref($self);
}

1;

__END__

=head1 NAME - Hum::Chromosome::VitalStatistics::Formatter

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

