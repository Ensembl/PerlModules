
package Hum::Acception;

use strict;
use DBI;
use Carp;
use Time::Local qw( timelocal );


sub new {
    my( $pkg, $sanger_id ) = @_;

    my $accn = bless {}, $pkg;
    return $accn;
}

# db returns the database handle
{
    my( $db );

    sub db () {
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

BEGIN {

    my @two_figure = ('00'..'31');
    
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
    
    my( %months );
    {
        my $i = 1;
        %months = map {$_, $two_figure[$i++]} qw( JAN FEB MAR APR MAY JUN
                                                  JUL AUG SEP OCT NOV DEC );
        #warn map "$_ => $months{$_}\n", sort {$months{$a} <=> $months{$b}} keys %months;
    }
    
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

sub embl_checksum {
    my( $accn, $check ) = @_;
    
    # Allow adding 0 to embl_checksum field
    if (defined $check) {
        $accn->{'_embl_checksum'} = $check;
    }
    return $accn->{'_embl_checksum'};
}

BEGIN {
    my $field = '_secondary';

    sub secondary {
        my $accn = shift;

        if (@_) {
            $accn->{$field} = [@_];
        }
        return $accn->{$field} ? @{$accn->{$field}} : ();
    }

    sub add_secondary {
        my( $accn, $sec ) = @_;

        push( @{$accn->{$field}}, $sec ) if $sec;
    }
}

# Generate the other data access functions using closures

BEGIN {
        
    # List of fields we want scalar access fuctions to
    my @scalar_fields = qw(
        id
        sanger_id
        sequence_version
        sequence_length
        project_name
        project_suffix
        accession
        embl_name
        htgs_phase
    );
    
    # Make scalar field access functions
    foreach my $func (@scalar_fields) {
        no strict 'refs';
        
        # Don't overwrite existing functions
        die "'$func()' already defined" if defined (&$func);
        
        my $field = "_$func";
        *$func = sub {
            my( $accn, $arg ) = @_;
            
            if ($arg) {
                $accn->{$field} = $arg;
            }
            return $accn->{$field};
        }
    }
}

BEGIN {
    my $select = qq{
            SELECT p.project_name
              , p.sanger_id
              , p.accession
              , p.embl_name
              , p.project_suffix
              , UNIX_TIMESTAMP(a.accept_date) accept_date
              , a.sequence_version
              , a.sequence_length
              , a.htgs_phase
              , s.secondary add_secondary
            FROM project_acc p
              , acception a
            LEFT JOIN secondary_acc s
              ON p.accession = s.accession
            WHERE p.sanger_id = a.sanger_id
              AND p.project_name = ?
              AND a.is_current = 'Y'
            };

    sub by_project {
        my( $pkg, $project ) = @_;

        my $db = db();
        my $sth = $db->prepare($select);
        $sth->execute($project);
        
        my( %proj );
        while (my $h = $sth->fetchrow_hashref) {
            my( $accn );
            if ($accn = $proj{$h->{'sanger_id'}}) {
                # We've already had a row of data for this sanger_id
                $accn->add_secondary($h->{'secondary'});
            } else { 
                # Make a new Acception, and store in hash
                $accn = $pkg->new;
                map $accn->$_($h->{$_}), keys %$h;
                $proj{$h->{'sanger_id'}} = $accn;
            }
        }
        # Return the new objects
        return values %proj;
    }
}

BEGIN {
    my $select = qq{
            SELECT p.project_name
              , p.sanger_id
              , p.accession
              , p.embl_name
              , p.project_suffix
              , UNIX_TIMESTAMP(a.accept_date) accept_date
              , a.sequence_version
              , a.sequence_length
              , a.htgs_phase
              , s.secondary add_secondary
            FROM project_acc p
              , acception a
            LEFT JOIN secondary_acc s
              ON p.accession = s.accession
            WHERE p.sanger_id = a.sanger_id
              AND p.sanger_id = ?
              AND a.is_current = 'Y'
            };

    sub by_sanger_id {
        my( $pkg, $id ) = @_;

        my $db = db();
        my $sth = $db->prepare($select);
        $sth->execute($id);
        
        my( $accn );
        while (my $h = $sth->fetchrow_hashref) {
            if ($accn) {
                $accn->add_secondary($h->{'secondary'});
            } else { 
                $accn = $pkg->new;
                map $accn->$_($h->{$_}), keys %$h;
            }
        }
        return $accn;
    }
}



# Object methods

sub store {
    my( $accn ) = @_;
    
    # Store data in the three tables associated with
    # this project
    $accn->_update_project_acc;
    $accn->_update_acception;
    $accn->_update_secondary_acc;
}

sub show_fields {
    my( $accn, @fields ) = @_;
    
    return map $accn->$_(), @fields;
}

sub _matches_hash {
    my( $accn, $hash ) = @_;
    
    my $intersects = 1;
    foreach my $field (keys %$hash) {
        local $^W = 0;
        my $value = $hash->{$field};

        unless ($value eq $accn->$field()) {
            $intersects = 0;
            last;
        }
    }
    return $intersects;
}

# Storage methods for the project_acc table
BEGIN {

    my @fields = qw(
        sanger_id
        project_name
        project_suffix
        accession
        embl_name
    );

    my $field_list = join(', ', @fields);

    my $insert = qq{INSERT INTO project_acc($field_list)
                    VALUES(?,?,?,?,?)};

    sub _update_project_acc {
        my( $accn ) = @_;

        my $sid = $accn->sanger_id || confess "No sanger_id";

        # First see if it's in the database
        my $sth = $accn->db->prepare(qq{ select * from project_acc
                                        where sanger_id = '$sid' });
        $sth->execute;
        my $ans = $sth->fetchrow_hashref;

        if ($ans) {
            # It is in the database, so check that we
            # have the same information
            unless ($accn->_matches_hash( $ans )) {
                confess "New data: ", format_hashes($accn),
                    "Doesn't match db data: ", format_hashes($ans);
            }
        } else {
            my $sth = $accn->db->prepare($insert);
            $sth->execute($accn->show_fields(@fields));
        }
    }
}

# Storage methods for the acception table
BEGIN {

    my @fields = qw(
        embl_checksum
        sanger_id       
        sequence_version
        sequence_length 
        htgs_phase      
        accept_date     
    );

    my $where = q{WHERE sanger_id = ?
                  AND sequence_version = ?
                  AND sequence_length = ?
                  AND htgs_phase = ?
                  AND accept_date = FROM_UNIXTIME(?)};

    my $sum_select = q{SELECT embl_checksum
                       FROM acception
                       } . $where;

    my $sum_update = q{UPDATE acception
                       SET embl_checksum = ?
                       } . $where;

    my $insert = 'INSERT INTO acception('
                 . join(', ', ('id', 'is_current', @fields))
                 . q{) VALUES('NULL','Y',?,?,?,?,?,FROM_UNIXTIME(?))};

    sub _update_acception {
        my( $accn ) = @_;

        my $db = $accn->db;

        # First see if it's in the database
        my( $sum, $sid, @values ) = $accn->show_fields(@fields);
        my $sth = $db->prepare($sum_select);
        $sth->execute($sid, @values);
        my $ans = $sth->fetchall_arrayref;

        if (@$ans) {
            my $db_sum = $ans->[0][0];
            
            if ( $sum != 0) {
                if ($db_sum == 0) {
                    # Then the checksum was previously
                    # unknown, but we can now update it
                    my $upd = $db->prepare($sum_update);
                    $upd->exectue($sum, $sid, @values);
                }
                elsif ($sum != $db_sum) {
                    confess("Checksum in db '$db_sum' doesn't match object's value '$sum'");
                }
            }
        } else {
            my $uns = $db->prepare(q{UPDATE acception
                                     SET is_current = 'N'
                                     WHERE sanger_id = ?});
            $uns->execute($sid);
            
            my $ins = $db->prepare($insert);
            $ins->execute($sum, $sid, @values);
        }
    }
}

# Storage methods for the secondary_acc table
BEGIN {

    my $insert = q{INSERT INTO secondary_acc(accession, secondary)
                   VALUES(?,?)};

    sub _update_secondary_acc {
        my( $accn ) = @_;
        
        my $acc = $accn->accession;
        my $sth = $accn->db->prepare($insert);
        foreach my $sec ($accn->secondary) {
            my $ans = $accn->db->selectall_arrayref(qq{
                    SELECT * FROM secondary_acc
                    WHERE secondary = '$sec'
                });
            $sth->execute($acc, $sec) unless @$ans;
        }
    }
}

# Non-object methods

sub format_hashes {
    my( $hash ) = @_;

    my @format = ("{\n");  
    foreach my $key (sort keys %$hash) {
        my $val = $hash->{$key};
        if (ref($val) eq 'ARRAY') {
            push(@format, "  '$key' => '",
                 join(", ", map "'$_'", @$val), 
                 "'\n");
        } else {
            push(@format, "  '$key' => '$val'\n");
        }
    }
    push(@format, "}\n");

    return @format;
}

1;

__END__



=pod

=head1 NAME - Hum::Acception

=head1 DESCRIPTION

=head2 ACCEPTION TABLE

 +------------------+-----------------------------+------+-----+---------------------+----------------+
 | Field            | Type                        | Null | Key | Default             | Extra          |
 +------------------+-----------------------------+------+-----+---------------------+----------------+
 | id               | int(11)                     |      | PRI | 0                   | auto_increment |
 | sanger_id        | varchar(20)                 |      | MUL |                     |                |
 | accept_date      | datetime                    |      | MUL | 0000-00-00 00:00:00 |                |
 | sequence_version | int(11)                     |      |     | 0                   |                |
 | sequence_length  | int(11)                     |      |     | 0                   |                |
 | htgs_phase       | enum('1','2','3','4','UNK') |      |     | UNK                 |                |
 | is_current       | enum('Y','N')               |      | MUL | N                   |                |
 +------------------+-----------------------------+------+-----+---------------------+----------------+

Each addition to EMBL generates a new entry in
the ACCEPTION table.  ACCEPTION records data
associated with submissions which vary with time.

=head2 PROJECT_ACC TABLE

 +----------------+-------------+------+-----+---------+-------+
 | Field          | Type        | Null | Key | Default | Extra |
 +----------------+-------------+------+-----+---------+-------+
 | sanger_id      | varchar(20) |      | PRI |         |       |
 | project_name   | varchar(20) |      | MUL |         |       |
 | project_suffix | char(1)     | YES  |     | NULL    |       |
 | accession      | varchar(10) |      | MUL |         |       |
 | embl_name      | varchar(10) |      |     |         |       |
 +----------------+-------------+------+-----+---------+-------+

Each new entry in EMBL generates a new entry in
the PROJECT_ACC table.  PROJECT_ACC maps Sanger
EMBL identifiers (eg: "_DJ234P15") to Sanger
project names and suffixes.  (Suffixes are given
where a project is finished in more than one
piece, and are "A", "B", "C" etc...)

=head2 SECONDARY_ACC TABLE

 +-----------+-------------+------+-----+---------+-------+
 | Field     | Type        | Null | Key | Default | Extra |
 +-----------+-------------+------+-----+---------+-------+
 | accession | varchar(10) |      | MUL |         |       |
 | secondary | varchar(10) |      | MUL |         |       |
 +-----------+-------------+------+-----+---------+-------+

Shows the secondary accessions associated with
the primary accessions in the PROJECT_ACC table.

=head2 Author

James Gilbert email B<jgrg@sanger.ac.uk>
