
package Hum::Submission;

=pod

=head1 NAME Hum::Submission

=head1 DESCRIPTION


=cut

use strict;
use DBI;
use Carp;
use Time::Local qw( timelocal );

{
    my( $db );
    my $host = 'caldy';

    sub new {
        my( $pkg ) = @_;

        unless ($db) {
            my $user = (getpwuid($<))[0];
            
            # Make the database connection
            $db = DBI->connect("DBI:mysql:submissions:$host", $user, undef, {RaiseError => 1})
                or die "Can't connect to submissions database on host '$host' as '$user' ",
                DBI::errstr();
        }

        my $sub = bless {}, $pkg;
        $sub->db($db);
        return $sub;
    }

    END {
        $db->disconnect if $db;
    }
}

# Generate data access functions:

BEGIN {
    my @scalar_fields = qw(
                           db
                           sanger_id       
                           sequence_version
                           sequence_length 
                           htgs_phase
                           project_name  
                           project_suffix
                           accession     
                           embl_id       
                           );

    foreach my $field (@scalar_fields) {
        no strict 'refs';
        
        *$field = sub {
            my $sub = shift;
            
            if (@_) {
                $sub->{$field} = shift;
            }
            
            return $sub->{$field};
        }
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
        #print STDERR map "$_ => $months{$_}\n", sort {$months{$a} <=> $months{$b}} keys %months;
    }
    
    sub date {
        my( $sub ) = shift;

        if (@_) {
            $_ = shift;
            my ($mysql_date);
            if (my($mday, $mon, $year) = /^(\d\d)-([A-Z]{3})-(\d{4})$/) {
                $mon = $months{$mon};
                $mysql_date = "$year-$mon-$mday";
            } elsif (/^\d+$/) {
                $mysql_date = MySQLdate($_);
            } elsif (/^\d{4}-\d\d-\d\d$/) {
                $mysql_date = $_;
            } else {
                confess "Unknown date format '$_'";
            }
            $sub->{'date'} = $mysql_date;
        }

        return $sub->{'date'};
    }
}



sub secondaries {
    my $sub = shift;
    
    if (@_) {
        $sub->{'secondaries'} = [@_];
    }

    return @{$sub->{'secondaries'}};
}

# Object methods

sub store {
    my $sub = shift;
    
    $sub->_update_project_acc;
    $sub->_update_acception;
    $sub->_update_secondary_acc;
}

sub _update_project_acc {
    my( $sub ) = @_;
    
    my $sid = $sub->sanger_id || confess "No sanger_id";

    # First see if it's in the database
    my $sth = $sub->db->prepare(qq{
                                   select * from project_acc
                                   where sanger_id = '$sid'
                                   });
    if (my $ans = $sth->fetchrow_hashref) {
        # It is in the database, so check that we
        # have the same information
        $sub->_full_intersection_check( $ans );
    } else {
        
        $sub->_store_in_table(qw( project_acc sanger_id
                                              project_name
                                              project_suffix
                                              accession
                                              embl_id ));
    }
    $sth->finish;
}

sub _update_acception {
    my( $sub ) = @_;
    
    my @fields = qw(sanger_id
                    date
                    sequence_version
                    sequence_length
                    htgs_phase);
    
}

sub _full_intersection_check {
    my( $sub, $hash ) = @_;
    
    foreach my $field (keys %$hash) {
        my $value = $hash->{$field};

        unless ($value eq $sub->$field()) {
            confess "New data: ", show_fields($sub),
                "Doesn't match db data: ", show_fields($hash);
        }
    }
}

sub _get_matching_row {
    my( $sub, $table, @columns ) = @_;
    
    my $select = "select * from $table where"
                 . join(' and ', map "$_ = '$sub->{$_}'", @columns);
    my $ans = $sub->db->fetchall_arraryref($select);
    
    return @$ans ? @{$ans->[0]} : undef;
}

sub _store_in_table {
    my( $sub, $table, @columns ) = @_;
    
    my $insert = "insert into $table ("
                 . join(', ', @columns)
                 . ') values ('
                 . join(',', map '?', @columns)
                 . ')';
    my $sth = $sub->db->prepare($insert);
    warn "Made statement: '$insert'";
    $sth->exectue(map $sub->{$_}, @columns);
}

# Non-object methods

sub show_fields {
    my( $sub ) = @_;

    my @format = ("{\n");  
    foreach my $key (sort keys %$sub) {
        my $val = $sub->{$key};
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


my $acception = $db->prepare(
    qq{
        insert into acception(
            id
            , sanger_id
            , date
            , sequence_version
            , sequence_length
            ) values('NULL',?,?,?,?)
    }
);

my $project_acc = $db->prepare(
    qq{
        insert into project_acc(
            sanger_id
            , project_name
            , project_suffix
            , accession
            , embl_id
            , htgs_phase
            ) values(?,?,?,?,?,?)
    }
);

my $secondary_acc = $db->prepare(
    qq{
        insert into secondary_acc(
            accession
            , secondary
        ) values(?,?)
    }
);



=head2 ACCEPTION TABLE

  +------------------+---------------+------+-----+------------+----------------+
  | Field            | Type          | Null | Key | Default    | Extra          |
  +------------------+---------------+------+-----+------------+----------------+
  | id               | int(11)       |      | PRI | 0          | auto_increment |
  | sanger_id        | varchar(20)   |      | MUL |            |                |
  | date             | date          |      | MUL | 0000-00-00 |                |
  | sequence_version | int(11)       |      |     | 0          |                |
  | sequence_length  | int(11)       |      |     | 0          |                |
  | htgs_phase       | enum('1','3') |      |     | 1          |                |
  +------------------+---------------+------+-----+------------+----------------+

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
  | embl_id        | varchar(10) |      |     |         |       |
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
