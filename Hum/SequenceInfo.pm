
### Hum::SequenceInfo

package Hum::SequenceInfo;

use strict;
use Hum::Tracking 'track_db';

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub fetch_by_db_id {
    my( $pkg, $db_id ) = @_;
    
    my $sth = track_db()->prepare_cached(q{
        SELECT accession
          , sv
          , id_htgsphase
          , length
          , embl_checksum
          , projectname
        FROM sequence
        WHERE id_sequence = ?
        });
    $sth->execute($db_id);
    my ($acc, $sv, $htgs_phase, $length, $cksum, $proj) = $sth->fetchrow;
}

sub new_from_Sequence {
    my( $pkg, $seq ) = @_;
    
    my $self = bless {}, $pkg;
    $self->Sequence($seq);
    return $self;
}

sub db_id {
    my( $self, $db_id ) = @_;
    
    if ($db_id) {
        $self->{'_db_id'} = $db_id;
    }
    return $self->{'_db_id'};
}

sub accession {
    my( $self, $accession ) = @_;
    
    if ($accession) {
        $self->{'_accession'} = $accession;
    }
    return $self->{'_accession'};
}

sub sequence_version {
    my( $self, $sequence_version ) = @_;
    
    if ($sequence_version) {
        $self->{'_sequence_version'} = $sequence_version;
    }
    return $self->{'_sequence_version'};
}

sub htgs_phase {
    my( $self, $htgs_phase ) = @_;
    
    if ($htgs_phase) {
        $self->{'_htgs_phase'} = $htgs_phase;
    }
    return $self->{'_htgs_phase'};
}

sub sequence_length {
    my( $self, $sequence_length ) = @_;
    
    if ($sequence_length) {
        $self->{'_sequence_length'} = $sequence_length;
    }
    return $self->{'_sequence_length'};
}

sub embl_checksum {
    my( $self, $embl_checksum ) = @_;
    
    if ($embl_checksum) {
        $self->{'_embl_checksum'} = $embl_checksum;
    }
    return $self->{'_embl_checksum'};
}

sub projectname {
    my( $self, $projectname ) = @_;
    
    if ($projectname) {
        $self->{'_projectname'} = $projectname;
    }
    return $self->{'_projectname'};
}

sub clonename {
    my( $self, $clonename ) = @_;
    
    if ($clonename) {
        $self->{'_clonename'} = $clonename;
    }
    return $self->{'_clonename'};
}

sub Sequence {
    my( $self, $seq ) = @_;
    
    if ($seq) {
        $self->{'_Sequence'} = $seq;
        $self->sequence_length($seq->sequence_length);
        $self->embl_checksum($seq->embl_checksum);
    }
    return $self->{'_Sequence'};
}

sub store {
    my( $self ) = @_;
    
    # Warning here?
    return if $self->db_id;
    
    ### Get next value from sequence
    $self->get_next_id;
    
    # Could check if already stored, or use a REPLACE?
    my $sth = track_db->prepare_cached(q{
        INSERT INTO sequence(
            id_sequence
          , accession
          , sv
          , id_htgsphase
          , length
          , embl_checksum
          , projectname )
        VALUES(?,?,?,?,?,?,?)
        });
    $sth->execute(
        $self->db_id,
        $self->accession,
        $self->sequence_version,
        $self->htgs_phase,
        $self->sequence_length,
        $self->embl_checksum,
        $self->projectname,
        );
}

sub get_next_id {
    my( $self ) = @_;
    
    my $sth = track_db()->prepare_cached(q{
        SELECT sequ_seq.nextval FROM dual
        });
    $sth->execute;
    my ($id) = $sth->fetchrow;
    $self->db_id($id);
}

1;

__END__

=head1 NAME - Hum::SequenceInfo

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

