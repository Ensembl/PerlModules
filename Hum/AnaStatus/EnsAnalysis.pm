
### Hum::AnaStatus::EnsAnalysis

package Hum::AnaStatus::EnsAnalysis;

use strict;
use Carp;
use Hum::Submission 'prepare_statement';
use Hum::AnaStatus::EnsAnalysisDB;

sub new {
    my ($pkg) = @_;

    return bless {}, $pkg;
}

sub fetch_all_for_ensembl_db_id {
    my ( $pkg, $id ) = @_;

    return $pkg->_fetch_all_where(qq{ ase.ensembl_db_id = $id });
}

sub fetch_all_for_ana_seq_id {
    my ( $pkg, $id ) = @_;

    return $pkg->_fetch_all_where(qq{ aseq.ana_seq_id = $id });
}

sub fetch_all_complete_for_ana_seq_id {
    my ( $pkg, $id ) = @_;

    return $pkg->_fetch_all_where(
        qq{ ase.ana_seq_id = $id AND ase.is_complete = 'Y' });
}

sub _fetch_all_where {
    my ( $pkg, $where_clause ) = @_;

    my $sql = qq{
        SELECT ase.ana_seq_id
          , ase.ensembl_db_id
          , ase.ensembl_contig_id
          , ase.is_complete
          , sc.species_name
          , s.sequence_version
          , s.unpadded_length
          , pa.accession
        FROM ana_sequence_ensembl ase
          , ana_sequence aseq
          , sequence s
          , species_chromosome sc
          , project_dump pd
          , project_acc pa
        WHERE s.seq_id = pd.seq_id
          AND pd.sanger_id = pa.sanger_id
          AND sc.chromosome_id = s.chromosome_id
          AND s.seq_id = aseq.seq_id
          AND aseq.ana_seq_id = ase.ana_seq_id
          AND $where_clause
        };
    #warn $sql;
    my $sth = prepare_statement($sql);
    $sth->execute;

    my (@ens_ana);
    while (
        my (
            $ana_seq_id,  $ensembl_db_id, $ensembl_contig_id,
            $is_complete, $species_name,  $sequence_version, 
            $length, $acc
        )
        = $sth->fetchrow
      )
    {
        my $ea = $pkg->new;
        $ea->ana_seq_id($ana_seq_id);
        $ea->ensembl_db_id($ensembl_db_id);
        $ea->ensembl_contig_id($ensembl_contig_id);
        $ea->is_complete( $is_complete eq 'Y' ? 1 : 0 );
        $ea->species_name($species_name);
        $ea->sequence_version($sequence_version);
        $ea->length($length);
        $ea->accession($acc);
        push ( @ens_ana, $ea );
    }
    return @ens_ana;
}

sub ana_seq_id {
    my ( $self, $ana_seq_id ) = @_;

    if ($ana_seq_id) {
        $self->{'_ana_seq_id'} = $ana_seq_id;
    }
    return $self->{'_ana_seq_id'};
}

sub ensembl_db_id {
    my ( $self, $ensembl_db_id ) = @_;

    if ($ensembl_db_id) {
        $self->{'_ensembl_db_id'} = $ensembl_db_id;
    }
    return $self->{'_ensembl_db_id'};
}

sub ensembl_contig_id {
    my ( $self, $ensembl_contig_id ) = @_;

    if ($ensembl_contig_id) {
        $self->{'_ensembl_contig_id'} = $ensembl_contig_id;
    }
    return $self->{'_ensembl_contig_id'};
}

sub is_complete {
    my ( $self, $flag ) = @_;

    if ( defined $flag ) {
        $self->{'_is_complete'} = $flag ? 1 : 0;
    }
    return $self->{'_is_complete'} || 0;
}

sub species_name {
    my ( $self, $species_name ) = @_;

    if ( defined $species_name ) {
        $self->{'_species_name'} = $species_name;
    }
    return $self->{'_species_name'};
}

sub sequence_version {
    my ( $self, $sequence_version ) = @_;

    if ( defined $sequence_version ) {
        $self->{'_sequence_version'} = $sequence_version;
    }
    return $self->{'_sequence_version'};
}

sub length {
    my ( $self, $length ) = @_;

    if ( defined $length ) {
        $self->{'_length'} = $length;
    }
    return $self->{'_length'};
}

sub accession {
    my ( $self, $acc ) = @_;

    if ( defined $acc ) {
        $self->{'_accession'} = $acc;
    }
    return $self->{'_accession'};
}

sub get_EnsAnalysisDB {
    my ($self) = @_;

    my $db_id = $self->ensembl_db_id or confess "ensembl_db_id not set";
    return Hum::AnaStatus::EnsAnalysisDB->get_cached_by_ensembl_db_id($db_id);
}

sub get_GeneBuildDB {
    my ($self) = @_;
    my $species_name = $self->species_name or confess "species_name not set";
    return Hum::AnaStatus::EnsAnalysisDB->get_cached_by_species_name(
        $species_name);

}

sub get_EnsEMBL_VirtualContig_of_contig {
    my ($self) = @_;

    my $contig_id = $self->ensembl_contig_id
      or confess "ensembl_contig_id not set";
    return
      $self->get_EnsAnalysisDB->db_adaptor->get_StaticGoldenPathAdaptor
      ->fetch_VirtualContig_of_contig( $contig_id, 0 );
}

sub get_GeneBuild_VirtualContig_of_contig {
    my( $self ) = @_;
    
    my $contig_id = $self->accession.".".$self->sequence_version.".1.".$self->length
        or confess "genebuild_contig_id not set";
    return $self
        ->get_GeneBuildDB
        ->db_adaptor
        ->get_StaticGoldenPathAdaptor
        ->fetch_VirtualContig_of_contig($contig_id, 0);
}

sub store {
    my ($self) = @_;

    my $ana_seq_id    = $self->ana_seq_id    or confess "ana_seq_id not set";
    my $ensembl_db_id = $self->ensembl_db_id or confess "ensembl_db_id not set";
    my $ensembl_contig_id = $self->ensembl_contig_id
      or confess "ensembl_contig_id not set";
    my $is_complete = $self->is_complete ? 'Y' : 'N';
    #my $species_name = $self->species_name or confess "species_name not set";
    my $sth = prepare_statement( qq{
        REPLACE ana_sequence_ensembl (ana_seq_id
              , ensembl_db_id
              , ensembl_contig_id
              , is_complete)
        VALUES ($ana_seq_id
              , $ensembl_db_id
              , '$ensembl_contig_id'
              , '$is_complete')
        }
    );
    $sth->execute;
}

1;

__END__

=head1 NAME - Hum::AnaStatus::EnsAnalysis

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

