
### Hum::SequenceOverlap::Position

package Hum::SequenceOverlap::Position;

use strict;
use warnings;
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
          , dovetail_length
        FROM sequence_overlap
        WHERE id_overlap = ?
        });
    $sth->execute($id);
    my( @pos );
    while (my ($seq_id, $pos, $is_3prime, $dove) = $sth->fetchrow) {
        my $seq_info = Hum::SequenceInfo->fetch_by_db_id($seq_id);
        my $self = $pkg->new;
        $self->position($pos);
        $self->is_3prime($is_3prime);
        $self->dovetail_length($dove);
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
    
    if (defined $position) {
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

sub dovetail_length {
    my( $self, $dovetail_length ) = @_;
    
    if (defined $dovetail_length) {
        $self->{'_dovetail_length'} = $dovetail_length;
    }
    return $self->{'_dovetail_length'};
}

sub validate {
    my( $self ) = @_;
    
    my $pos = $self->position;
    my $seq = $self->SequenceInfo;
    my $length = $seq->sequence_length;
    if ($pos < 1 or $pos > $length) {
        my $acc = $seq->accession;
        confess "Position $pos lies outside sequence '$acc' of length $length\n";
    }
}

sub matches {
    my( $self, $othr ) = @_;

    # 4 factors are used to compare for difference in overlap
    # position, orientation (5'/3') and accession, version
    
    foreach my $num (qw{ position is_3prime }) {
        return 0 unless $self->$num() == $othr->$num()
    }
    my $self_inf = $self->SequenceInfo;
    my $othr_inf = $othr->SequenceInfo;
    foreach my $num (qw{ sequence_version sequence_length }) {
        return 0 unless $self_inf->$num() == $othr_inf->$num()
    }
    return 0 unless $self_inf->accession eq $othr_inf->accession;
    
    return 1;
}

sub distance_to_end {
    my( $self ) = @_;
    
    my $pos = $self->position
        or confess 'position not set';
    my $is_3prime = $self->is_3prime;
    my $length = $self->SequenceInfo->sequence_length;
    if ($is_3prime) {
        return $length - $pos
    } else {
        return $pos - 1;
    }
}

sub store {
    my( $self, $overlap_id ) = @_;
    
    confess "No overlap_id given"
        unless $overlap_id;
    
    my $info = $self->SequenceInfo;
    $info->store unless $info->db_id;
    # REPLACE instead of INSERT?
    my $sth = track_db->prepare_cached(q{
        INSERT INTO sequence_overlap(
            id_sequence
          , id_overlap
          , position
          , is_3prime
          , dovetail_length )
        VALUES(?,?,?,?,?)
        });
    $sth->execute(
        $info->db_id,
        $overlap_id,
        $self->position,
        $self->is_3prime,
        $self->dovetail_length,
        );    
}

1;

__END__

=head1 NAME - Hum::SequenceOverlap::Position

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

