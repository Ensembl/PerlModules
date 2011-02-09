
package Hum::Acception;

use strict;
use warnings;
use DBI;
use Carp;
use Hum::Submission 'prepare_cached_statement';
use Hum::Tracking 'prepare_cached_track_statement';
use POSIX ();


sub new {
    my( $pkg, $sanger_id ) = @_;

    my $self = bless {}, $pkg;
    return $self;
}

{
    my @two_figure = ('00'..'31');
    
    # Convert MySQL date to unix time int
    sub dateMySQL {
        my( $my_date ) = @_;
        my( $year, $mon, $mday ) = split /-/, $my_date;
        $year -= 1900;
        return POSIX::mktime( 0, 0, 0, $mday, $mon, $year );
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
        my $self = shift;

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
            $self->{'accept_date'} = $unix;
        }

        return $self->{'accept_date'};
    }
}

sub embl_checksum {
    my( $self, $check ) = @_;
    
    # Allow adding 0 to embl_checksum field
    if (defined $check) {
        $self->{'_embl_checksum'} = $check;
    }
    return $self->{'_embl_checksum'};
}

sub secondary {
    my $self = shift;

    if (@_) {
        $self->{'_secondary'} = [@_];
    }
    return $self->{'_secondary'} ? @{$self->{'_secondary'}} : ();
}

sub add_secondary {
    my( $self, $sec ) = @_;

    push( @{$self->{'_secondary'}}, $sec ) if $sec;
}

sub sanger_id {
    my( $self, $sanger_id ) = @_;
    
    if ($sanger_id) {
        $self->{'_sanger_id'} = $sanger_id;
    }
    return $self->{'_sanger_id'};
}

sub sequence_version {
    my( $self, $sequence_version ) = @_;
    
    if ($sequence_version) {
        $self->{'_sequence_version'} = $sequence_version;
    }
    return $self->{'_sequence_version'};
}

sub sequence_length {
    my( $self, $sequence_length ) = @_;
    
    if ($sequence_length) {
        $self->{'_sequence_length'} = $sequence_length;
    }
    return $self->{'_sequence_length'};
}

sub project_name {
    my( $self, $project_name ) = @_;
    
    if ($project_name) {
        $self->{'_project_name'} = $project_name;
    }
    return $self->{'_project_name'};
}

sub project_suffix {
    my( $self, $project_suffix ) = @_;
    
    if ($project_suffix) {
        $self->{'_project_suffix'} = $project_suffix;
    }
    return $self->{'_project_suffix'};
}

sub accession {
    my( $self, $accession ) = @_;
    
    if ($accession) {
        $self->{'_accession'} = $accession;
    }
    return $self->{'_accession'};
}

sub embl_name {
    my( $self, $embl_name ) = @_;
    
    if ($embl_name) {
        $self->{'_embl_name'} = $embl_name;
    }
    return $self->{'_embl_name'};
}

sub htgs_phase {
    my( $self, $htgs_phase ) = @_;
    
    if ($htgs_phase) {
        $self->{'_htgs_phase'} = $htgs_phase;
    }
    return $self->{'_htgs_phase'};
}

{
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
            FROM (project_acc p
              , acception a)
            LEFT JOIN secondary_acc s
              ON p.accession = s.accession
            WHERE p.sanger_id = a.sanger_id
              AND p.project_name = ?
              AND a.is_current = 'Y'
            };

    sub by_project {
        my( $pkg, $project ) = @_;

        my $sth = prepare_cached_statement($select);
        $sth->execute($project);
        
        my( %proj );
        while (my $h = $sth->fetchrow_hashref) {
            my( $self );
            if ($self = $proj{$h->{'sanger_id'}}) {
                # We've already had a row of data for this sanger_id
                $self->add_secondary($h->{'secondary'});
            } else { 
                # Make a new Acception, and store in hash
                $self = $pkg->new;
                map $self->$_($h->{$_}), keys %$h;
                $proj{$h->{'sanger_id'}} = $self;
            }
        }
        # Return the new objects
        return values %proj;
    }
}

{
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
            FROM (project_acc p
              , acception a)
            LEFT JOIN secondary_acc s
              ON p.accession = s.accession
            WHERE p.sanger_id = a.sanger_id
              AND p.sanger_id = ?
              AND a.is_current = 'Y'
            };

    sub by_sanger_id {
        my( $pkg, $id ) = @_;

        my $sth = prepare_cached_statement($select);
        $sth->execute($id);
        
        my( $self );
        while (my $h = $sth->fetchrow_hashref) {
            if ($self) {
                $self->add_secondary($h->{'secondary'});
            } else { 
                $self = $pkg->new;
                map $self->$_($h->{$_}), keys %$h;
            }
        }
        return $self;
    }
}



# Object methods

sub store {
    my( $self ) = @_;
    
    # Store data in the three tables associated with
    # this project
    $self->_update_project_acc;
    $self->_update_acception;
    $self->_update_secondary_acc;
}

sub show_fields {
    my( $self, @fields ) = @_;
    
    return map $self->$_(), @fields;
}

sub _matches_hash {
    my( $self, $hash ) = @_;
    
    my $intersects = 1;
    foreach my $field (keys %$hash) {
        local $^W = 0;
        my $value = $hash->{$field};

        unless ($value eq $self->$field()) {
            $intersects = 0;
            last;
        }
    }
    return $intersects;
}

# Storage methods for the project_acc table
{

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
        my( $self ) = @_;

        my $sid = $self->sanger_id || confess "No sanger_id";

        # First see if it's in the database
        my $sth = prepare_cached_statement(qq{
            SELECT *
            FROM project_acc
            WHERE sanger_id = ?
            });
        $sth->execute($sid);
        my $ans = $sth->fetchrow_hashref;

        if ($ans) {
            # It is in the database, so check that we
            # have the same information
            unless ($self->_matches_hash( $ans )) {
                confess "New data: ", format_hashes($self),
                    "Doesn't match db data: ", format_hashes($ans);
            }
        } else {
            my $sth = prepare_cached_statement($insert);
            $sth->execute($self->show_fields(@fields));
        }
    }
}

# Storage methods for the acception table
{

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
        my( $self ) = @_;

        # First see if it's in the database
        my( $sum, $sid, @values ) = $self->show_fields(@fields);
        my $sth = prepare_cached_statement($sum_select);
        $sth->execute($sid, @values);
        my $ans = $sth->fetchall_arrayref;

        if (@$ans) {
            my $db_sum = $ans->[0][0];
            
            if ( $sum != 0) {
                if ($db_sum == 0) {
                    # Then the checksum was previously
                    # unknown, but we can now update it
                    my $upd = prepare_cached_statement($sum_update);
                    $upd->exectue($sum, $sid, @values);
                }
                elsif ($sum != $db_sum) {
                    confess("Checksum in db '$db_sum' doesn't match object's value '$sum'");
                }
            }
        } else {
            my $uns = prepare_cached_statement(q{
                UPDATE acception
                SET is_current = 'N'
                WHERE sanger_id = ?
                });
            $uns->execute($sid);
            
            my $ins = prepare_cached_statement($insert);
            $ins->execute($sum, $sid, @values);
        }
    }
}

# Storage methods for the secondary_acc table
sub _update_secondary_acc {
    my( $self ) = @_;

    my $acc = $self->accession;
    my $sth = prepare_cached_statement(q{
        REPLACE INTO secondary_acc(accession, secondary)
        VALUES(?,?)
        });
    foreach my $sec ($self->secondary) {
        $sth->execute($acc, $sec);
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

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>
