
### Hum::Ace::SeqFeature

package Hum::Ace::SeqFeature;

use strict;
use Carp;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub start {
    my( $self, $start ) = @_;
    
    if (defined $start) {
        $self->{'_start'} = $start;
    }
    return $self->{'_start'};
}

sub end {
    my( $self, $end ) = @_;
    
    if (defined $end) {
        $self->{'_end'} = $end;
    }
    return $self->{'_end'};
}

{
    my %allowed_strand = map {$_, 1} qw{ -1 0 1 +1 };

    sub strand {
        my( $self, $strand ) = @_;

        if (defined $strand) {
            confess "Illegal strand '$strand'"
                unless $allowed_strand{$strand};
            $self->{'_strand'} = $strand;
        }
        return $self->{'_strand'};
    }
}

sub score {
    my( $self, $score ) = @_;
    
    if (defined $score) {
        $self->{'_score'} = $score;
    }
    return $self->{'_score'};
}


1;

__END__

=head1 NAME - Hum::Ace::SeqFeature

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

