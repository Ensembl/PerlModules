
### Hum::AnaStatus::EnsAnalysisDB

package Hum::AnaStatus::EnsAnalysisDB;

use strict;
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
    my $user    = $dba->username or confess "username not set in DBAdaptor";
    confess "'localhost' isn't good enough for a hostname"
        if $host eq 'localhost';
    
    return $pkg->_fetch_where(qq{ db_name = '$db_name' AND host = '$host' AND user = '$user' });
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
        FROM ana_ensembl_db
        WHERE $where
        });
    $sth->execute;
    
    my ($ensembl_db_id, $db_name, $host, $user, $type) = $sth->fetchrow;
    confess "No EnsAnalysisDB found with '$where'"
        unless $ensembl_db_id;
    
    my $self = $pkg->new;
    $self->ensembl_db_id($ensembl_db_id);
    $self->db_name($db_name);
    $self->host($host);
    $self->user($user);
    $self->golden_path_type($type);
    
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

sub user {
    my( $self, $user ) = @_;
    
    if ($user) {
        $self->{'_user'} = $user;
    }
    return $self->{'_user'};
}

sub ensembl_db_id {
    my( $self, $ensembl_db_id ) = @_;
    
    if ($ensembl_db_id) {
        $self->{'_ensembl_db_id'} = $ensembl_db_id;
    }
    return $self->{'_ensembl_db_id'};
}

sub golden_path_type {
    my( $self, $golden_path_type ) = @_;
    
    if ($golden_path_type) {
        $self->{'_golden_path_type'} = $golden_path_type;
    }
    return $self->{'_golden_path_type'};
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
        
        $db_adaptor
            = $self->{'_db_adaptor'}
            = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
                -HOST   => $host,
                -DBNAME => $db_name,
                -USER   => $user,
                );
        $db_adaptor->static_golden_path_type($type);
    }
    return $db_adaptor;
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
    
    
    my $sth = prepare_statement(qq{
        INSERT ana_ensembl_db( db_name, host, user, golden_path_type )
        VALUES ( '$db_name', '$host', '$user', '$type' )
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

