
### Hum::AnaStatus::EnsAnalysis

package Hum::AnaStatus::EnsAnalysis;

use strict;
use warnings;
use Carp;
use Hum::Submission 'prepare_statement';
use Hum::AnaStatus::EnsAnalysisDB;

sub fetch_all_for_ensembl_db_id {
    my( $pkg, $id ) = @_;
    
    return $pkg->_fetch_all_where(qq{ ensembl_db_id = $id });
}

sub fetch_all_for_ana_seq_id {
    my( $pkg, $id ) = @_;
    
    return $pkg->_fetch_all_where(qq{ ana_seq_id = $id });
}

sub fetch_all_complete_for_ana_seq_id {
    my( $pkg, $id ) = @_;
    
    return $pkg->_fetch_all_where(qq{ ana_seq_id = $id AND is_complete = 'Y' });
}

sub _fetch_all_where {
    my( $pkg, $where_clause ) = @_;
    
    my $sth = prepare_statement(qq{
        SELECT ana_seq_id
          , ensembl_db_id
          , ensembl_contig_id
          , is_complete
        FROM ana_sequence_ensembl
        WHERE $where_clause
        });
    $sth->execute;
    
    my( @ens_ana );
    while (my ($ana_seq_id, $ensembl_db_id, $ensembl_contig_id, $is_complete) = $sth->fetchrow) {
        my $ea = $pkg->new;
        $ea->ana_seq_id($ana_seq_id);
        $ea->ensembl_db_id($ensembl_db_id);
        $ea->ensembl_contig_id($ensembl_contig_id);
        $ea->is_complete($is_complete eq 'Y' ? 1 : 0);
        push(@ens_ana, $ea);
    }
    return @ens_ana;
}

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}

sub ana_seq_id {
    my( $self, $ana_seq_id ) = @_;
    
    if ($ana_seq_id) {
        $self->{'_ana_seq_id'} = $ana_seq_id;
    }
    return $self->{'_ana_seq_id'};
}

sub ensembl_db_id {
    my( $self, $ensembl_db_id ) = @_;
    
    if ($ensembl_db_id) {
        $self->{'_ensembl_db_id'} = $ensembl_db_id;
    }
    return $self->{'_ensembl_db_id'};
}

sub ensembl_contig_id {
    my( $self, $ensembl_contig_id ) = @_;
    
    if ($ensembl_contig_id) {
        $self->{'_ensembl_contig_id'} = $ensembl_contig_id;
    }
    return $self->{'_ensembl_contig_id'};
}

sub is_complete {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_is_complete'} = $flag ? 1 : 0;
    }
    return $self->{'_is_complete'} || 0;
}

sub species_name {
    my( $self, $species_name ) = @_;
    
    if (defined $species_name) {
        $self->{'_species_name'} = $species_name
    }
    return $self->{'_species_name'} || 0;
}

sub get_EnsAnalysisDB {
    my( $self ) = @_;
    
    my $db_id = $self->ensembl_db_id
        or confess "ensembl_db_id not set";
    return Hum::AnaStatus::EnsAnalysisDB
        ->get_cached_by_ensembl_db_id($db_id);
}

sub get_SpeciesGeneBuildDB {
    my( $self ) = @_;
    
    my $species_name = $self->species_name
        or confess "species name not set";
    return Hum::AnaStatus::EnsAnalysisDB
        ->get_cached_by_species_name($species_name);
}

sub get_EnsEMBL_VirtualContig_of_contig {
    my( $self ) = @_;
    
    my $contig_id = $self->ensembl_contig_id
        or confess "ensembl_contig_id not set";
    return $self
        ->get_EnsAnalysisDB
        ->db_adaptor
        ->get_StaticGoldenPathAdaptor
        ->fetch_VirtualContig_of_contig($contig_id, 0);
}

sub get_EnsEMBL_Slice_of_contig {
    my( $self ) = @_;
    
    my $contig_id = $self->ensembl_contig_id
        or confess "ensembl_contig_id not set";
    print "Fetching contig by name $contig_id\n";
    return $self
        ->get_EnsAnalysisDB
        ->db_adaptor
        ->get_SliceAdaptor
        ->fetch_by_contig_name($contig_id, 0);
}

#SMJS TODO
sub get_GeneBuild_VirtualContig_of_contig {
    my( $self ) = @_;
    
    my $contig_id = $self->ensembl_contig_id
        or confess "ensembl_contig_id not set";
    return $self
        ->get_SpeciesGeneBuildDB
        ->db_adaptor
        ->get_StaticGoldenPathAdaptor
        ->fetch_VirtualContig_of_contig($contig_id, 0);
}

sub store {
    my( $self ) = @_;
    
    my $ana_seq_id = $self->ana_seq_id
        or confess        "ana_seq_id not set";
    my $ensembl_db_id = $self->ensembl_db_id
        or confess     "ensembl_db_id not set";
    my $ensembl_contig_id = $self->ensembl_contig_id
        or confess "ensembl_contig_id not set";
    my $is_complete = $self->is_complete ? 'Y' : 'N';
    
    my $sth = prepare_statement(qq{
        REPLACE ana_sequence_ensembl (ana_seq_id
              , ensembl_db_id
              , ensembl_contig_id
              , is_complete)
        VALUES ($ana_seq_id
              , $ensembl_db_id
              , '$ensembl_contig_id'
              , '$is_complete')
        });
    $sth->execute;
}

1;

__END__

=head1 NAME - Hum::AnaStatus::EnsAnalysis

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

