
### Hum::Analysis::Factory::StringMatch

package Hum::Analysis::Factory::StringMatch;

use strict;
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
    
    my $seq_str = $query->sequence_string;
    my $hit_str = $subject->sequence_string;
    my $hit_len = $subject->sequence_length;
    
    my $i = 0;
    while ((my $pos = index($seq_str, $hit_str, $i)) != -1) {
        $i = $pos + 1;
        #warn "Found on $strand at ", $pos + 1, "\n";
        my $match = Hum::Ace::SeqFeature::Pair->new;
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

