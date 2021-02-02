=head1 LICENSE

Copyright [2018-2021] EMBL-European Bioinformatics Institute

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


### Hum::Analysis::Factory::StringMatch

package Hum::Analysis::Factory::StringMatch;

use strict;
use warnings;
use Carp;
use Hum::Ace::SeqFeature::Pair;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}


sub run {
    my( $self, $query, $fwd ) = @_;
    
    my $rev = $fwd->reverse_complement;
    
    my $features = [];
    $self->find_features($query, $fwd,  1, $features);
    $self->find_features($query, $rev, -1, $features);
    
    return $features;
}

sub find_features {
    my( $self, $query, $subject, $strand, $features ) = @_;
    
    my $seq_str = lc $query->sequence_string
        or confess "Empty sequence string for '",   $query->name, "'";
    my $hit_str = lc $subject->sequence_string
        or confess "Empty sequence string for '", $subject->name, "'";
    my $hit_len = $subject->sequence_length;
    
    my $i = 0;
    while ((my $pos = index($seq_str, $hit_str, $i)) != -1) {
        $i = $pos + 1;
        #warn "Found on $strand at ", $pos + 1, "\n";
        my $match = Hum::Ace::SeqFeature::Pair->new;
        $match->percent_identity(100);

        $match->seq_name($query->name);
        $match->seq_start($pos + 1);
        $match->seq_end($pos + $hit_len);
        $match->seq_strand($strand);

        $match->hit_name($subject->name);
        $match->hit_start(1);
        $match->hit_end($hit_len);
        $match->hit_strand(1);
        
        push(@$features, $match);
    }
}

1;

__END__

=head1 NAME - Hum::Analysis::Factory::StringMatch

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

