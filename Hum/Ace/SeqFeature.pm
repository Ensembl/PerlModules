
### Hum::Ace::SeqFeature

package Hum::Ace::SeqFeature;

use strict;
use Carp;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub seq_name {
    my( $self, $seq_name ) = @_;
    
    if ($seq_name) {
        $self->{'_seq_name'} = $seq_name;
    }
    return $self->{'_seq_name'};
}

sub seq_start {
    my( $self, $seq_start ) = @_;
    
    if (defined $seq_start) {
        $self->{'_seq_start'} = $seq_start;
    }
    return $self->{'_seq_start'};
}

sub seq_end {
    my( $self, $seq_end ) = @_;
    
    if (defined $seq_end) {
        $self->{'_seq_end'} = $seq_end;
    }
    return $self->{'_seq_end'};
}

sub seq_length {
    my( $self ) = @_;
    
    my $start = $self->seq_start;
    my $end   = $self->seq_end;
    return $end - $start + 1;
}

sub seq_Sequence {
    my( $self, $seq ) = @_;
    
    if ($seq) {
        unless (ref($seq) and $seq->isa('Hum::Sequence')) {
            confess "'$seq' is not a Hum::Sequence";
        }
        $self->{'_seq_Sequence'} = $seq;
    }
    return $self->{'_seq_Sequence'};
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
    return $self->{'_score'} || 0;
}


1;

__END__

=head1 NAME - Hum::Ace::SeqFeature

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

