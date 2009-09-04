
### Hum::Ace::SeqFeature

package Hum::Ace::SeqFeature;

use strict;
use warnings;
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

{
    my %allowed_strand = map {$_, 1} qw{ -1 0 1 };

    sub seq_strand {
        my( $self, $strand ) = @_;

        if (defined $strand) {
            confess "Illegal strand '$strand'"
                unless $allowed_strand{$strand};
            $self->{'_seq_strand'} = $strand;
        }
        return $self->{'_seq_strand'};
    }
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

sub score {
    my( $self, $score ) = @_;
    
    if (defined $score) {
        $self->{'_score'} = $score;
    }
    return $self->{'_score'} || 0;
}

sub method_name {
    my( $self, $method_name ) = @_;
    
    if ($method_name) {
        $self->{'_method_name'} = $method_name;
    }
    return $self->{'_method_name'};
}
 
sub seq_overlaps {
    my( $self, $other ) = @_;
    
    if ($self->seq_end >= $other->seq_start
        and $self->seq_start <= $other->seq_end)
    {
        return 1;
    } else {
        return 0;
    }
}

1;

__END__

=head1 NAME - Hum::Ace::SeqFeature

=head1 METHODS

=over 4

=item new

Returns a new B<Hum::Ace::SeqFeature> object.

=item seq_name

The name of the sequence this feature is on.

=item seq_start

The start of this feature in the sequence

=item seq_end

The end of this feature in the sequence

=item seq_length

=item seq_Sequence

=item score

=item method_name


=back


=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

