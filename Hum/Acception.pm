
package Hum::Submission;

use strict;
use DBI;
use Carp;
use Time::Local qw( timelocal );

{
    my( $db );
    my $host = 'caldy';

    sub new {
        my( $pkg, $sanger_id ) = @_;

        unless ($db) {
            my $user = (getpwuid($<))[0];
            
            # Make the database connection
            $db = DBI->connect("DBI:mysql:submissions:$host", $user, undef, {RaiseError => 1})
                or die "Can't connect to submissions database on host '$host' as '$user' ",
                DBI::errstr();
        }

        my $sub = bless {}, $pkg;
        $sub->db($db);
        $sub->sanger_id($sanger_id) if $sanger_id;
        return $sub;
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
        my( $sub ) = shift;

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
            $sub->{'accept_date'} = $unix;
        }

        return $sub->{'accept_date'};
    }
}

sub secondary {
    my $sub = shift;
    
    if (@_) {
        $sub->{'secondary'} = [@_];
    }

    return $sub->{'secondary'} ? @{$sub->{'secondary'}} : ();
}


# Generate the other data access functions using closures

BEGIN {
        
    # List of fields we want scalar access fuctions to
    my @scalar_fields = qw(
        db
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
    foreach my $field (@scalar_fields) {
        no strict 'refs';
        
        # Don't overwrite existing functions
        die "'$field()' already defined" if defined (&$field);
        
        *$field = sub {
            my $sub = shift;
            
            if (@_) {
                $sub->{$field} = shift;
            }
            
            return $sub->{$field};
        }
    }
}



# Object methods

sub store {
    my( $sub ) = @_;
    
    $sub->_update_project_acc;
    $sub->_update_acception;
    $sub->_update_secondary_acc;
}

sub retrieve {
    my( $sub ) = @_;
    
    my $sid = $sub->sanger_id
        or confess "Can't retrieve data without sanger_id";
    $sub->_retrieve_project_acc;
    $sub->_retrieve_acception;
    $sub->_retrieve_secondary_acc;
}

BEGIN {

    my @fields = qw(
        sanger_id       
        accept_date     
        sequence_version
        sequence_length 
        htgs_phase      
    );

    my $insert = 'INSERT INTO acception('
                 . join(', ', ('id', @fields))
                 . q{) VALUES('NULL',?,FROM_UNIXTIME(?),?,?,?)};

    sub _store_acception {
        my( $sub ) = @_;

        my $sth = $sub->db->prepare($insert);
        $sth->execute($sub->show_fields(@fields));
    }

    sub _update_acception {
        my( $sub ) = @_;

        # First see if it's in the database
        my( $sid, $date, $sv, $length, $phase ) = $sub->show_fields(@fields);
        my $sth = $sub->db->prepare(qq{SELECT * FROM project_acc
                                       WHERE sanger_id = '$sid'
                                         AND accept_date = FROM_UNIXTIME('$date')
                                         AND sequence_version = '$sv'
                                         AND sequence_length = '$length'
                                         AND htgs_phase = '$phase'});
        my $ans = $sth->fetchall_arrayref;
        $sub->_store_acception unless @$ans;
    }
}

BEGIN {

    my @fields = qw(
        sanger_id
        project_name
        project_suffix
        accession
        embl_name
    );

    my $field_list = join(', ', @fields);

    my $insert = "INSERT INTO project_acc($field_list) VALUES(?,?,?,?,?)";

    my $select = qq{SELECT $field_list
                    FROM project_acc
                    WHERE sanger_id = ?};

    sub _store_project_acc {
        my( $sub ) = @_;

        my $sth = $sub->db->prepare($insert);
        $sth->execute($sub->show_fields(@fields));
    }

    sub _retrieve_project_acc {
        my( $sub ) = @_;
        
        my $sth = $sub->db->prepare($select);
        $sth->execute($sub->sanger_id);
        if (my $ans = $sth->fetchrow_arrayref) {
            foreach my $f (@fields) {
                my $d = shift @$ans;
                next if $f eq 'sanger_id';
                $sub->$f($d);
            }
            return 1;
        } else {
            return;
        }
    }

    sub _update_project_acc {
        my( $sub ) = @_;

        my $sid = $sub->sanger_id || confess "No sanger_id";

        # First see if it's in the database
        my $sth = $sub->db->prepare(qq{ select * from project_acc
                                        where sanger_id = '$sid' });
        $sth->execute;
        my $ans = $sth->fetchrow_hashref;

        if ($ans) {
            # It is in the database, so check that we
            # have the same information
            unless ($sub->_matches( $ans )) {
                confess "New data: ", format_hashes($sub),
                    "Doesn't match db data: ", format_hashes($ans);
            }
        } else {
            $sub->_store_project_acc;
        }
    }
}

BEGIN {

    my @fields = qw(
        accession
        secondary
    );

    my $insert = 'INSERT INTO secondary_acc('
                 . join(', ', @fields)
                 . ') VALUES(?,?)';

    sub _update_secondary_acc {
        my( $sub ) = @_;
        
        my $acc = $sub->accession;
        my $sth = $sub->db->prepare($insert);
        foreach my $sec ($sub->secondary) {
            my $ans = $sub->db->selectall_arrayref(qq{
                    SELECT * FROM secondary_acc
                    WHERE secondary = '$sec'
                });
            $sth->execute($acc, $sec) unless @$ans;
        }
    }
}

sub show_fields {
    my( $sub, @fields ) = @_;
    
    return map $sub->$_(), @fields;
}

sub _matches {
    my( $sub, $hash ) = @_;
    
    my $intersects = 1;
    foreach my $field (keys %$hash) {
        local $^W = 0;
        my $value = $hash->{$field};

        unless ($value eq $sub->$field()) {
            $intersects = 0;
            last;
        }
    }
    return $intersects;
}

sub _get_matching_row {
    my( $sub, $table, @columns ) = @_;
    
    my $select = "select * from $table where"
                 . join(' and ', map "$_ = '$sub->{$_}'", @columns);
    my $ans = $sub->db->fetchall_arraryref($select);
    
    return @$ans ? @{$ans->[0]} : undef;
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

=head1 NAME - Hum::Submission

=head1 DESCRIPTION

=head2 ACCEPTION TABLE

 +------------------+---------------+------+-----+---------------------+----------------+
 | Field            | Type          | Null | Key | Default             | Extra          |
 +------------------+---------------+------+-----+---------------------+----------------+
 | id               | int(11)       |      | PRI | 0                   | auto_increment |
 | sanger_id        | varchar(20)   |      | MUL |                     |                |
 | accept_date      | datetime      |      | MUL | 0000-00-00 00:00:00 |                |
 | sequence_version | int(11)       |      |     | 0                   |                |
 | sequence_length  | int(11)       |      |     | 0                   |                |
 | htgs_phase       | enum('1','3') |      |     | 1                   |                |
 +------------------+---------------+------+-----+---------------------+----------------+


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
 | accession | varchar(10) |      | PRI |         |       |
 | secondary | varchar(10) |      | MUL |         |       |
 +-----------+-------------+------+-----+---------+-------+

Shows the secondary accessions associated with
the primary accessions in the PROJECT_ACC table.

=head2 Author

James Gilbert email B<jgrg@sanger.ac.uk>
