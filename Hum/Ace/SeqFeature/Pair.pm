
### Hum::Ace::SeqFeature::Pair

package Hum::Ace::SeqFeature::Pair;

use strict;
use vars '@ISA';

@ISA = ('Hum::Ace::SeqFeature');


sub hit_name {
    my( $self, $hit_name ) = @_;
    
    if ($hit_name) {
        $self->{'_hit_name'} = $hit_name;
    }
    return $self->{'_hit_name'};
}

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

sub hit_length {
    my( $self ) = @_;
    
    my $start = $self->hit_start;
    my $end   = $self->hit_end;
    return $end - $start + 1;
}

sub hit_Sequence {
    my( $self, $hit_seq ) = @_;
    
    if ($hit_seq) {
        unless (ref($hit_seq) and $hit_seq->isa('Hum::Sequence')) {
            confess "'$hit_seq' is not a Hum::Sequence";
        }
        $self->{'_hit_Sequence'} = $hit_seq;
    }
    return $self->{'_hit_Sequence'};
}

sub percent_identity {
    my( $self, $percent_identity ) = @_;
    
    if (defined $percent_identity) {
        $self->{'_percent_identity'} = $percent_identity;
    }
    return $self->{'_percent_identity'} || 0;
}


1;

__END__

=head1 NAME - Hum::Ace::SeqFeature::Pair

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

