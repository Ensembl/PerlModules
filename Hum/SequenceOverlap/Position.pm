
### Hum::SequenceOverlap::Position

package Hum::SequenceOverlap::Position;

use strict;
use Carp;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub db_id {
    my( $self, $db_id ) = @_;
    
    if ($db_id) {
        $self->{'_db_id'} = $db_id;
    }
    return $self->{'_db_id'};
}

sub SequenceInfo {
    my( $self, $SequenceInfo ) = @_;
    
    if ($SequenceInfo) {
        $self->{'_SequenceInfo'} = $SequenceInfo;
    }
    return $self->{'_SequenceInfo'};
}

sub position {
    my( $self, $position ) = @_;
    
    if ($position) {
        $self->{'_position'} = $position;
    }
    return $self->{'_position'};
}

sub is_3prime {
    my( $self, $is_3prime ) = @_;
    
    if (defined $is_3prime) {
        $self->{'_is_3prime'} = $is_3prime ? 1 : 0;
    }
    return $self->{'_is_3prime'};
}

sub validate {
    my( $self ) = @_;
    
    my $pos = $self->position;
    my $seq = $self->Sequence;
    my $length   = $seq->sequence_length;
    if ($pos < 0 or $pos > $length) {
        my $seq_name = $seq->name;
        confess "Position $pos is outside sequence '$seq_name' of length $length";
    }
}

1;

__END__

=head1 NAME - Hum::SequenceOverlap::Position

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

