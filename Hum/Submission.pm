
package Hum::Submission;

use strict;
use DBI;
use Carp;
use Time::Local qw( timelocal );
use Exporter;
use vars qw( @ISA @EXPORT_OK );

@ISA = ('Exporter');
@EXPORT_OK = qw( sub_db
                 acc_data
                 create_lock
                 destroy_lock
                 ftp_path
                 timeace
                 ghost_path
                 dateMySQL
                 MySQLdatetime );

# sub_db returns the database handle
{
    my( $db );

    sub sub_db () {
        unless ($db) {
            my $user = (getpwuid($<))[0];
            
            # Make the database connection
            $db = DBI->connect("DBI:mysql:host=humsrv1;port=3399;database=submissions;user=$user",
                               undef, undef, {RaiseError => 1})
                or die "Can't connect to submissions database as '$user' ",
                DBI::errstr();
        }
        return $db;
    }

    END {
        $db->disconnect if $db;
    }
}

sub create_lock {
    my( $name ) = @_;
    
    confess "Can't create lock without a name" unless $name;
    
    my $create_lock = sub_db()->prepare(qq{
        INSERT INTO general_lock(lock_name, lock_time)
        VALUES (?, NOW())
        });
    
    # This is a bit "belt and braces".  It will work
    # wether {RaiseError => 1} is set or not
    my( $success );
    eval{
        $create_lock->execute($name);
        $success = $create_lock->rows;
    };
    
    if ($success and ! $@) {
        return 1;
    } else {
        confess "Failed to create lock '$name':\n$@"
    }
}

sub destroy_lock {
    my( $name ) = @_;
    
    confess "Can't create lock without a name" unless $name;
    
    my $destroy_lock = sub_db()->prepare(qq{
        DELETE FROM general_lock
        WHERE lock_name = ?
        });
    
    # This is a bit "belt and braces".  It will work
    # wether {RaiseError => 1} is set or not
    my( $success );
    eval{
        $destroy_lock->execute($name);
        $success = $destroy_lock->rows;
    };
    
    if ($success and ! $@) {
        return 1;
    } else {
        confess "Failed to destroy lock '$name':\n$@"
    }
}

sub acc_data {
    my( $sid ) = @_;

    my $dbh = sub_db();
    
    my $sth = $dbh->prepare(qq{
        SELECT a.accession
          , a.embl_name
          , s.secondary
        FROM project_acc a
        LEFT JOIN secondary_acc s
          ON a.accession = s.accession
        WHERE a.sanger_id = '$sid'
    });
    $sth->execute;
    
    my( $acc, $name, $s, @sec );
    while (my $ans = $sth->fetchrow_arrayref) {
        ($acc, $name, $s) = @$ans;
        push(@sec, $s) if $s;
    }
    if (defined($acc) and $acc eq 'UNKNOWN') {
        $acc = undef;
    }
    return ( $acc, $name, @sec );
}

BEGIN {

    my @two_figure = ('00'..'60');
    
    # Convert acedb style timestring (2000-03-19_16:20:45) to unix time int
    sub timeace {
        my( $acetime ) = @_;
        
        my ($year, $mon, $mday, $hour, $min, $sec) =
            $acetime =~ /(\d{4})-(\d\d)-(\d\d)_(\d\d):(\d\d):(\d\d)/
            or confess "Can't parse acedb time string '$acetime'";
        $year -= 1900;
        $mon--;
        return timelocal( $sec, $min, $hour, $mday, $mon, $year );
    }
    
    # Convert MySQL date to unix time int
    sub dateMySQL {
        my( $my_date ) = @_;
        my( $year, $mon, $mday ) = split /-/, $my_date;
        $year -= 1900;
        return timelocal( 0, 0, 0, $mday, $mon, $year );
    }

    # Convert unix time int to MySQL date
    sub MySQLdate {
        my $time = shift || time;
        my ($sec, $min, $hour, $mday, $mon, $year) = localtime($time);
        $year += 1900;
        ($mon, $mday) = @two_figure[$mon + 1, $mday];
        return "$year-$mon-$mday";
    }
    
    # Convert unix time int to MySQL datetime
    sub MySQLdatetime {
        my $time = shift || time;
        my ($sec, $min, $hour, $mday, $mon, $year) = localtime($time);
        $year += 1900;
        ($sec, $min, $hour, $mon, $mday) =
            @two_figure[$sec, $min, $hour, $mon + 1, $mday];
        return "$year-$mon-$mday $hour:$min:$sec";
    }
    
    my( %months );
    {
        my $i = 1;
        %months = map {$_, $two_figure[$i++]} qw( JAN FEB MAR APR MAY JUN
                                                  JUL AUG SEP OCT NOV DEC );
    }
    
    # Fossil from old Acception module
    sub accept_date {
        my( $accn ) = shift;

        if (@_) {
            $_ = shift;
            
            my ($unix);
            # Date in MySQL default date format
            if (/^\d{4}-\d\d-\d\d$/) {
                $unix = dateMySQL($_);
            }
            # EMBL format date
            elsif (my($mday, $mon, $year) = /^(\d\d)-([A-Z]{3})-(\d{4})$/) {
                $mon = $months{$mon};
                $unix = dateMySQL("$year-$mon-$mday");
            }
            # Unix time int (what we want)
            elsif (/^\d+$/) {
                $unix = $_;
            }
            else {
                confess "Unknown date format '$_'";
            }
            $accn->{'accept_date'} = $unix;
        }

        return $accn->{'accept_date'};
    }
}

1;

__END__


=head1 NAME - Hum::Submission

=head1 DESCRIPTION


Tables in oracle providing a view into the EMBL
oracle database:

=head2 embl_v_projects

Codes for the large scale sequencing projects in
EMBL.

    Name    Description
    ------  --------------------------------
    CODE    PROJECT# in embl_v_primary
    NAME    Brief description of the project

=head2 embl_v_secondary

Mapping of primary to secondary accessions.

    Name       Description
    ---------  --------------------
    PRIMARY    Primary accession number
    SECONDARY  Secondary accession number

=head2 embl_v_primary

Details of primary submissions.

    Name          Description              Null?     Type
    ------------  -----------------------  --------  ------------
    PROJECT#      Sequencing project code  NOT NULL  NUMBER(2)
    NAME          EMBL ID                  NOT NULL  VARCHAR2(10)
    ACC           Primary accession        NOT NULL  VARCHAR2(15)
    ACC_SYNONYM   eg: 12_DJ1187J4                    VARCHAR2(45)
    SEQLEN        Length of sequence       NOT NULL  NUMBER(15)
    CRC32         EMBL checksum            NOT NULL  NUMBER(15)
    SV            Sequence version         NOT NULL  NUMBER(5)
    LAST_MOD      Last modified date                 DATE


=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk
