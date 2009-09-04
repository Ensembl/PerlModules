
### Hum::AnaStatus::EnsAnalysisDB

package Hum::AnaStatus::EnsAnalysisDB;

use strict;
use warnings;
use Carp;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Hum::Submission 'prepare_statement';
use Hum::AnaStatus::EnsAnalysis;

{
    my( %ens_db_cache );
    
    sub get_cached_by_ensembl_db_id {
        my( $pkg, $db_id ) = @_;
        
        my( $db );
        unless ($db = $ens_db_cache{$db_id}) {
            $db = $ens_db_cache{$db_id}
                = $pkg->new_from_ensembl_db_id($db_id);
        }
        
        return $db;
    }

    sub get_cached_by_species_name {
        my( $pkg, $species_name ) = @_;

        confess "No species name given" unless $species_name;

        my $sth = prepare_statement(qq{
            SELECT ensembl_db_id
            FROM species_ensembl_db
            WHERE species_name = '$species_name'
            });
        $sth->execute;

        my( @ens_db );
        while (my ($db_id) = $sth->fetchrow) {
            push(@ens_db, $pkg->get_cached_by_ensembl_db_id($db_id));
        }
        if (@ens_db) {
            return @ens_db;
        } else {
            confess "No Ensembl db for species '$species_name'";
        }
    }
    
    sub disconnect_all_ensembl_dbs {
        # Explicitly destroy data structure, to try
        # and work around memory cycle in DBAdaptor
        foreach my $db (values %ens_db_cache) {
            if (my $aptr = $db->get_cached_db_adaptor) {
                #$aptr->_db_handle->disconnect;
                $aptr->db_handle->disconnect;
            }
            foreach my $key (keys %$db) {
                $db->{$key} = undef;
            }
        }
        %ens_db_cache = ();
    }
}

sub fetch_all_EnsAnalysis {
    my( $self ) = @_;
    
    my $ens_db_id = $self->ensembl_db_id
        or confess "ensembl_db_id not set";
    return Hum::AnaStatus::EnsAnalysis
        ->fetch_all_for_ensembl_db_id($ens_db_id);
}

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}

# Not sure if this method is needed.
sub new_from_EnsEMBL_DBAdaptor {
    my( $pkg, $dba ) = @_;
    
    my $db_name = $dba->dbname   or confess   "dbname not set in DBAdaptor";
    my $host    = $dba->host     or confess     "host not set in DBAdaptor";
    confess "'$host' isn't good enough for a hostname"
        if $host =~ /localhost/i;
    
    return $pkg->_fetch_where(qq{ db_name = '$db_name' AND host = '$host' });
}

sub new_from_ensembl_db_id {
    my( $pkg, $db_id ) = @_;

    return $pkg->_fetch_where(qq{ ensembl_db_id = $db_id });
}

sub _fetch_where {
    my( $pkg, $where ) = @_;

    my $sth = prepare_statement(qq{
        SELECT ensembl_db_id
          , db_name
          , host
          , user
          , golden_path_type
          , port
          , dna_ensembl_db_id
        FROM ana_ensembl_db
        WHERE $where
        });
    $sth->execute;
    
    my ($ensembl_db_id, $db_name, $host, $user,
        $type, $port, $dna_ensembl_db_id) = $sth->fetchrow;
    confess "No EnsAnalysisDB found with '$where'"
        unless $ensembl_db_id;
    
    my $self = $pkg->new;
    $self->ensembl_db_id($ensembl_db_id);
    $self->db_name($db_name);
    $self->host($host);
    $self->user($user);
    $self->golden_path_type($type);
    $self->port($port);
    $self->dna_ensembl_db_id($dna_ensembl_db_id);
    
    return $self;
}

sub db_name {
    my( $self, $db_name ) = @_;
    
    if ($db_name) {
        $self->{'_db_name'} = $db_name;
    }
    return $self->{'_db_name'};
}

sub host {
    my( $self, $host ) = @_;
    
    if ($host) {
        $self->{'_host'} = $host;
    }
    return $self->{'_host'};
}

sub port {
    my( $self, $port ) = @_;
    
    if ($port) {
        $self->{'_port'} = $port;
    }
    return $self->{'_port'} || 3306;
}

sub user {
    my( $self, $user ) = @_;
    
    if ($user) {
        $self->{'_user'} = $user;
    }
    return $self->{'_user'};
}

sub password {
    my( $self, $password ) = @_;
    
    if ($password) {
        $self->{'_password'} = $password;
    }
    return $self->{'_password'};
}

sub ensembl_db_id {
    my( $self, $ensembl_db_id ) = @_;
    
    if ($ensembl_db_id) {
        $self->{'_ensembl_db_id'} = $ensembl_db_id;
    }
    return $self->{'_ensembl_db_id'};
}

sub dna_ensembl_db_id {
    my( $self, $dna_ensembl_db_id ) = @_;
    
    if ($dna_ensembl_db_id) {
        $self->{'_dna_ensembl_db_id'} = $dna_ensembl_db_id;
    }
    return $self->{'_dna_ensembl_db_id'};
}

sub golden_path_type {
    my( $self, $golden_path_type ) = @_;
    
    if ($golden_path_type) {
        $self->{'_golden_path_type'} = $golden_path_type;
    }
    return $self->{'_golden_path_type'};
}

sub gene_type {
    my( $self, $gene_type ) = @_;
    
    if ($gene_type) {
        $self->{'_gene_type'} = $gene_type;
    }
    return $self->{'_gene_type'};
}

sub ace_data_factory {
    my( $self, $ace_data_factory ) = @_;
    
    if ($ace_data_factory) {
        $self->{'_ace_data_factory'} = $ace_data_factory;
    }
    return $self->{'_ace_data_factory'};
}

{
    # Set default db adaptor type
    my $adaptor_type = 'Bio::EnsEMBL::DBSQL::DBAdaptor';

    sub set_db_adaptor_type {
        my( $thing, $type ) = @_;
        
        if ($type eq 'Pipeline') {
            $adaptor_type = 'Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor';
            require Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor;
        }
        elsif ($type eq 'DBSQL') {
            $adaptor_type = 'Bio::EnsEMBL::DBSQL::DBAdaptor';
        }
        else {
            confess "argument must be either 'Pipeline' or 'DBSQL'; got '$type'";
        }
    }
    
    sub get_cached_db_adaptor {
        my( $self ) = @_;
        
        return $self->{'_db_adaptor'};
    }
    
    sub db_adaptor {
        my( $self ) = @_;

        my( $db_adaptor );
        unless ($db_adaptor = $self->{'_db_adaptor'}) {
            my $db_name = $self->db_name or confess "db_name not set";
            my $host    = $self->host    or confess    "host not set";
            my $user    = $self->user    or confess    "user not set";
            my $type    = $self->golden_path_type
                                or confess "golden_path_type not set";
            my $pass    = $self->password || '';
            my $port    = $self->port;

            $db_adaptor
                = $self->{'_db_adaptor'}
                = $adaptor_type->new(
                    -HOST   => $host,
                    -DBNAME => $db_name,
                    -USER   => $user,
                    -PASS   => $pass,
                    -PORT   => $port,
                    );
            $db_adaptor->assembly_type($type);
        }
        
        if (my $dna_db = $self->dna_ensembl_db_id) {
            # Hmm ... maybe someone could create an
            # infinite loop in the data?
            my $ens_db = ref($self)->get_cached_by_ensembl_db_id($dna_db);
            $db_adaptor->dnadb($ens_db->db_adaptor);
        }
        
        return $db_adaptor;
    }
}

sub store {
    my( $self ) = @_;
    
    if (my $db_id = $self->ensembl_db_id) {
        confess "already stored in database with ensembl_db_id = '$db_id'";   
    }
    
    my $db_name = $self->db_name or confess "db_name not set";
    my $host    = $self->host    or confess    "host not set";
    my $user    = $self->user    or confess    "user not set";
    my $type    = $self->golden_path_type
                        or confess "golden_path_type not set";
    my $port    = $self->port;
    
    
    my $sth = prepare_statement(qq{
        INSERT ana_ensembl_db( db_name, host, user, golden_path_type, port )
        VALUES ( '$db_name', '$host', '$user', '$type', $port )
        });
    $sth->execute;
    
    my $insert_id = $sth->{'mysql_insertid'}
        or confess "Failed to get insertid from statement handle";
    $self->ensembl_db_id($insert_id);
}

1;

__END__

=head1 NAME - Hum::AnaStatus::EnsAnalysisDB

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

