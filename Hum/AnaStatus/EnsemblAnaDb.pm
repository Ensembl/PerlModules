
### Hum::AnaStatus::EnsemblAnaDb

package Hum::AnaStatus::EnsemblAnaDb;

use strict;
use Carp;
use Bio::Ensembl::DBAdaptor;
use Hum::Submission 'prepare_statement';

{
    my( %ens_db_cache );
    
    sub connect {
        my( $pkg, $db_name, $host, $user ) = @_;
        
        confess "useage: connect(DB_NAME, HOST, [USER])"
            unless $db_name and $host;
        
        $user ||= 'ensro';
        my $key = join('++', $db_name, $host, $user);
        
        my( $db );
        unless ($db = $ens_db_cache{$key}) {
            $db = $pkg->new;
            $db->db_name($db_name);
            $db->host($host);
            $db->user($user);
            $db->dbh;   # Make connection
            
            $ens_db_cache{$key} = $db;
        }
        return $db;
    }
}

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}



1;

__END__

=head1 NAME - Hum::AnaStatus::EnsemblAnaDb

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

