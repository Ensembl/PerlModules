
### Hum::SequenceOverlap::Position

package Hum::SequenceOverlap::Position;

use strict;
use Carp;
use Hum::Tracking 'track_db';
use Hum::SequenceInfo;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}



# Don't think this method will be needed?
sub fetch_both_for_overlap_id {
    my( $pkg, $id ) = @_;
    
    my $sth = track_db()->prepare_cached(q{
        SELECT id_seqeunce
          , position
          , is_3prime
        FROM sequence_overlap
        WHERE id_overlap = ?
        });
    $sth->execute($id);
    my( @pos );
    while (my ($seq_id, $pos, $is_3prime) = $sth->fetchrow) {
        my $seq_info = Hum::SequenceInfo->fetch_by_db_id($seq_id);
        my $self = $pkg->new;
        $self->position($pos);
        $self->is_3prime($is_3prime);
        $self->SequenceInfo($seq_info);
    }
    if (@pos) {
        return @pos;
    } else {
        confess "No overlap positions for id_overlap = '$id'";
    }
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

sub store {
    my( $self, $overlap_id ) = @_;
    
    confess "No overlap_id given"
        unless $overlap_id;
    
    my $info = $self->SequenceInfo;
    $info->store;
    
    # REPLACE instead of INSERT?
    my $sth = track_db->prepare_cached(q{
        INSERT INTO sequence_overlap(
            id_sequence
          , id_overlap
          , position
          , is_3prime )
        VALUES(?,?,?,?)
        });
    $sth->execute(
        $info->db_id,
        $overlap_id,
        $self->position,
        $self->is_3prime,
        );    
}

1;

__END__

=head1 NAME - Hum::SequenceOverlap::Position

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

