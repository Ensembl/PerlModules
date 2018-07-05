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


### Hum::Sequence::Peptide

package Hum::Sequence::Peptide;

use strict;
use warnings;
use vars '@ISA';
use Carp;
use Hum::Sequence;

@ISA = 'Hum::Sequence';


sub ace_string {
    my( $seq_obj ) = @_;
    
    my $name = $seq_obj->name
        or confess "No name";
    my $seq  = $seq_obj->sequence_string
        or confess "No sequence";
    my $ace_string = qq{\nProtein : "$name"\n\nPeptide : "$name"\n};
    while ($seq =~ /(.{1,60})/g) {
        $ace_string .= $1 . "\n";
    }
    return $ace_string;
}


1;

__END__

=head1 NAME - Hum::Sequence::Peptide

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

