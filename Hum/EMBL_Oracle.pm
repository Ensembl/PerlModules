
### Hum::EMBL_Oracle

package Hum::EMBL_Oracle;

use strict;
use Carp;
use DBI;
use Net::Netrc;
use Exporter;
use vars qw( @ISA @EXPORT_OK );

@ISA = ('Exporter');
@EXPORT_OK = qw{
    prepare_embl_statement
    embl_disconnect
    };

{
    my( $dbh, @active_statements );
    
    sub dbh {
        unless ($dbh) {
            my $host = 'tonic.ebi.ac.uk';
            my $mach = Net::Netrc->lookup($host);
            $dbh = DBI->connect("dbi:Oracle:host=$host;sid=PRDB1;port=1521",
                $mach->login,
                $mach->password,
                {RaiseError => 1});
            $mach = undef;  # Remove password from memory
        }
        return $dbh;
    }
    
    END {
        embl_disconnect();
    }
    
    sub embl_disconnect {
        return unless $dbh;
        foreach my $sth (grep $_, @active_statements) {
            $sth->finish;
        }
        $dbh->disconnect;
    }

    sub prepare_embl_statement {
        my( $sql ) = @_;

        return dbh()->prepare($sql);
    }
}


1;

__END__

=head1 NAME - Hum::EMBL_Oracle

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

