
### Hum::Ace::SeqFeature::Pair

package Hum::Ace::SeqFeature::Pair;

use strict;
use vars '@ISA';

@ISA = ('Hum::Ace::SeqFeature');


sub hit_start {
    my( $self, $hit_start ) = @_;
    
    if ($hit_start) {
        $self->{'_hit_start'} = $hit_start;
    }
    return $self->{'_hit_start'};
}

sub hit_end {
    my( $self, $hit_end ) = @_;
    
    if ($hit_end) {
        $self->{'_hit_end'} = $hit_end;
    }
    return $self->{'_hit_end'};
}

sub percent_identity {
    my( $self, $percent_identity ) = @_;
    
    if (defined $percent_identity) {
        $self->{'_percent_identity'} = $percent_identity;
    }
    return $self->{'_percent_identity'};
}


1;

__END__

=head1 NAME - Hum::Ace::SeqFeature::Pair

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

