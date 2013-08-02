
### Hum::EMBL_Oracle

package Hum::EMBL_Oracle;

use strict;
use warnings;
use Carp;
use DBI;
use Net::Netrc;
use Exporter;
use vars qw( @ISA @EXPORT_OK );

@ISA       = ('Exporter');
@EXPORT_OK = qw{
  prepare_embl_statement
  embl_disconnect
};

sub _raw_dbh {
    my $host = 'oracle.ebi.ac.uk';
    my $mach = Net::Netrc->lookup($host);
    my $dbh  = eval {
        DBI->connect("dbi:Oracle:host=$host;sid=ENAPRO;port=2001", $mach->login, $mach->password, { RaiseError => 1 });
    };
    my $prob = $@;
    $mach = undef;    # Remove password from memory

    return $dbh if defined $dbh;

    if ($prob =~ /\bORA-01035:/) {

        # "ORACLE only available to users with RESTRICTED SESSION privilege"
        die(    "EMBL_Oracle connection blocked.\n"
              . "Assume they are preparing a release - please wait.\n"
              . "\n   $prob");
    }
    else {

        # Some other error
        die "EMBL_Oracle: connect failed, $@";
    }
}

{
    my ($dbh, @active_statements);

    sub dbh {
        unless ($dbh) {
            $dbh = _raw_dbh();
        }
        return $dbh;
    }

    sub embl_disconnect {
        return unless $dbh;
        foreach my $sth (grep $_, @active_statements) {
            $sth->finish;
        }
        $dbh->disconnect;
    }
}

END {
    embl_disconnect();
}

sub prepare_embl_statement {
    my ($sql) = @_;

    return dbh()->prepare($sql);
}

1;

__END__

=head1 NAME - Hum::EMBL_Oracle

=head1 DESCRIPTION

Wraps access to the EMBL Oracle database,
providing access via these methods:

=over 4

=head2 prepare_embl_statement SQL_STRING

Returns a B<DBI::sth> object given a string of sql.

=head2 embl_disconnect

Disconnects from the EMBL database.  Useful in
long running scripts.

=back

We can SELECT data from the following tables:

=over 4

=head2 v_projects

Codes for the large scale sequencing projects in
EMBL.

    Name    Description
    ------  --------------------------------
    CODE    PROJECT# in v_gp_primary
    NAME    Brief description of the project

=head2 v_gp_secondary

Mapping of primary to secondary accessions.

    Name       Description
    ---------  --------------------
    PRIMARY    Primary accession number
    SECONDARY  Secondary accession number

=head2 v_gp_primary

Details of primary submissions.

    Name          Description              Null?     Type
    ------------  -----------------------  --------  ------------
    PROJECT#      Sequencing project code  NOT NULL  NUMBER(2)
    NAME          EMBL ID                  NOT NULL  VARCHAR2(10)
    ACC           Primary accession        NOT NULL  VARCHAR2(15)
    GP_ID         eg: 12_DJ1187J4                    VARCHAR2(45)
    SEQLEN        Length of sequence       NOT NULL  NUMBER(15)
    CRC32         EMBL checksum            NOT NULL  NUMBER(15)
    SV            Sequence version         NOT NULL  NUMBER(5)
    LAST_MOD      Last modified date                 DATE

=head2 v_gp_primary_audit

Same as v_gp_primary, but shows data for old
versions of sequences that do not appear in
v_gp_primary.

=head2 v_gp_keyword

=back

=head1 ACCESS

To get access to this database, we asked Sanger's network team to ask
EBI for holes in the relevant firewalls.  Most recent was RT#345841.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

