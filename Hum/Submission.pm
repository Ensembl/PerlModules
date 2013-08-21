
package Hum::Submission;

use strict;
use warnings;
use DBI;
use Carp;
use POSIX ();
use Exporter;
use vars qw( @ISA @EXPORT_OK );
use Net::Netrc;
use Hum::Conf qw(SUBMISSIONS_CONNECTION);

@ISA       = ('Exporter');
@EXPORT_OK = qw( sub_db
  ref_from_query
  acc_data
  create_lock
  destroy_lock
  die_if_dumped_recently
  set_dumped_flag
  prepare_statement
  prepare_cached_statement
  sanger_name
  accession_from_sanger_name
  sanger_id_from_accession
  project_name_and_suffix_from_sequence_name
  project_name_from_accession
  submission_disconnect
  is_dumped
  acetime
  acedate
  timeace
  ghost_path
  MySQLdate
  dateMySQL
  MySQLdatetime
  datetimeMySQL
  header_supplement_code
  accession_from_project_name
  species_from_project_name
  seq_id_from_project_name
  sanger_id_from_project_name
  sanger_id_from_project_name_and_accession
  chromosome_from_project_name
);

=pod

=head2 ref_from_query( SQL )

Returns a reference to an array of anonymous
arrays containing the results from running the
B<SQL> query on the database.  

=cut

sub ref_from_query {
    my ($query) = @_;

    my $dbh = sub_db();

    my $sth = $dbh->prepare($query);
    $sth->execute;
    return $sth->fetchall_arrayref;
}

# sub_db returns the database handle
{
    my ($db);

    sub sub_db () {
        unless ($db) {
            my $host   = $SUBMISSIONS_CONNECTION->{HOST};
            my $port   = $SUBMISSIONS_CONNECTION->{PORT};
            my $dbname = $SUBMISSIONS_CONNECTION->{NAME};

            my ($user, $password);
            if (my $netrc = 'Net::Netrc'->lookup($host)) {
                $user     = $netrc->login;
                $password = $netrc->password;
            }
            else {
                $user     = $SUBMISSIONS_CONNECTION->{RO_USER};
                $password = undef;
            }

            # Make the database connection
            $db =
              DBI->connect("DBI:mysql:host=$host;port=$port;database=$dbname",
                $user, $password, { RaiseError => 1, PrintError => 0 })
              or die "Can't connect to submissions database as '$user' ",
              DBI::errstr();
        }
        return $db;
    }

    my (@active_statement_handles);

    sub prepare_statement {
        my ($text) = @_;

        my $sth = sub_db()->prepare($text);
        push(@active_statement_handles, $sth);
        return $sth;
    }

    sub prepare_cached_statement {
        my ($text) = @_;

        my $sth = sub_db()->prepare_cached($text);

        #push(@active_statement_handles, $sth);
        return $sth;
    }

    sub submission_disconnect {
        foreach my $sth (@active_statement_handles) {
            $sth->finish if $sth;
        }
        $db->disconnect if $db;
        $db = undef;
    }

    END {
        submission_disconnect();
    }
}

sub acc_data {
    my ($sid) = @_;

    my $get_acc_data = prepare_statement(
        qq{
        SELECT a.accession
          , a.embl_name
          , s.secondary
        FROM project_acc a
        LEFT JOIN secondary_acc s
          ON a.accession = s.accession
        WHERE a.sanger_id = '$sid'
        }
    );
    $get_acc_data->execute;

    my ($acc, $name, $s, @sec);
    while (my $ans = $get_acc_data->fetchrow_arrayref) {
        ($acc, $name, $s) = @$ans;
        push(@sec, $s) if $s;
    }
    if (defined($acc) and $acc eq 'UNKNOWN') {
        $acc = undef;
    }
    return ($acc, $name, @sec);
}

sub header_supplement_code {
    my ($key, $sanger_id) = @_;

    my $sth = prepare_statement(
        q{
        SELECT h.header_code
        FROM project_header_supplement phs
          , header_supplement h
        WHERE phs.header_id = h.header_id
          AND h.header_key = ?
          AND phs.sanger_id = ?
        }
    );
    $sth->execute($key, $sanger_id);

    my (@subs);
    while (my ($str) = $sth->fetchrow) {
        my $code = eval $str;
        if ($@) {
            confess "Code '$str' did not compile : $@";
        }
        else {
            push(@subs, $code);
        }
    }
    return @subs;
}

sub create_lock {
    my ($name, $expiry_interval) = @_;

    # Default to cleaning up old locks older than 2 days
    $expiry_interval ||= 2 * 24 * 60 * 60;
    my $expired_time = time - $expiry_interval;

    #warn "expire=$expired_time\n";
    confess "Can't create lock without a name" unless $name;

    my $cleanup_lock = prepare_statement(
        qq{
        DELETE FROM general_lock
        WHERE lock_name = ?
          AND lock_time < FROM_UNIXTIME(?)
        }
    );

    my $create_lock = prepare_statement(
        qq{
        INSERT INTO general_lock(lock_name, lock_time)
        VALUES (?, NOW())
        }
    );

    # This is a bit "belt and braces".  It will work
    # whether {RaiseError => 1} is set or not
    my ($success);
    eval {
        $cleanup_lock->execute($name, $expired_time);
        $create_lock->execute($name);
        $success = $create_lock->rows;
    };

    if ($success and !$@) {
        return 1;
    }
    else {
        confess "Failed to create lock '$name':\n$@";
    }
}

sub destroy_lock {
    my ($name) = @_;

    confess "Can't create lock without a name" unless $name;

    my $destroy_lock = prepare_statement(
        qq{
        DELETE FROM general_lock
        WHERE lock_name = '$name'
        }
    );

    # This is a bit "belt and braces".  It will work
    # wether {RaiseError => 1} is set or not
    my ($success);
    eval {
        $destroy_lock->execute;
        $success = $destroy_lock->rows;
    };

    if ($success and !$@) {
        return 1;
    }
    else {
        confess "Failed to destroy lock '$name':\n$@";
    }
}

sub die_if_dumped_recently {
    my ($project, $hr) = @_;

    my $last_dump = prepare_statement(q{
        SELECT UNIX_TIMESTAMP(d.dump_time)
          , d.dump_time
        FROM project_acc a
          , project_dump d
        WHERE a.sanger_id = d.sanger_id
          AND a.project_name = ?
    });
    $last_dump->execute($project);

    if (my ($dump_int, $dump_time) = $last_dump->fetchrow) {
        my $limit = time() - ($hr * 60 * 60);
        if ($dump_int > $limit) {
            die "Project '$project' was last dumped on '$dump_time', which is less than ${hr}h ago";
        }
    }
    return 1;
}

sub set_dumped_flag {
    my ($project) = @_;

    my $sth = prepare_statement(q{
        UPDATE project_check
        SET dumped_flag = 'Y'
        WHERE project_name = ?
    });
    $sth->execute($project);

    return 1;
}

sub is_dumped {
    my ($project) = @_;

    my $last_dump = prepare_statement(q{
        SELECT d.dump_time
        FROM project_acc a
          , project_dump d
        WHERE a.sanger_id = d.sanger_id
          AND a.project_name = ?
    });
    $last_dump->execute($project);

    if (my ($dump_time) = $last_dump->fetchrow) {
        return 1;
    }
    return 0;
}

{

    my @two_figure = ('00' .. '59');

    # Convert acedb style timestring (2000-03-19_16:20:45) to unix time int
    sub timeace {
        my ($acetime) = @_;

        my ($year, $mon, $mday, $hour, $min, $sec) =
          $acetime =~ /(\d{4})-(\d\d)-(\d\d)_(\d\d):(\d\d):(\d\d)/
          or confess "Can't parse acedb time string '$acetime'";
        $year -= 1900;
        $mon--;
        return POSIX::mktime($sec, $min, $hour, $mday, $mon, $year);
    }

=head2 acetime

    # Generate a acedb time string for now
    $time = acetime();

Generates an acedb time string (such as
"1998-06-04_17:31:51") for inclusion in an ace file, taking
a time string as input, or defaulting to current time.

=cut

    sub acetime {
        my ($time) = @_;

        $time ||= time;

        # Get time info
        my ($sec, $min, $hour, $mday, $mon, $year) =
          (localtime($time))[ 0 .. 5 ];

        # Change numbers to double-digit format
        ($mon, $mday, $hour, $min, $sec) =
          @two_figure[ ($mon + 1), $mday, $hour, $min, $sec ];

        # Make year
        $year += 1900;

        return "$year-$mon-${mday}_$hour:$min:$sec";
    }

    sub acedate {
        my ($time) = @_;

        $time ||= time;

        # Get time info
        my ($mday, $mon, $year) =
          (localtime($time))[ 3 .. 5 ];

        # Change numbers to double-digit format
        ($mon, $mday) = @two_figure[ ($mon + 1), $mday ];

        # Make year
        $year += 1900;

        return "$year-$mon-$mday";
    }

    # Convert unix time int to MySQL date
    sub MySQLdate {
        my ($time) = @_;

        unless (defined $time) {
            $time = time;
        }
        my ($mday, $mon, $year) = (localtime($time))[ 3, 4, 5 ];
        $year += 1900;
        $mon  += 1;
        return sprintf("%04d-%02d-%02d", $year, $mon, $mday);
    }

    # Convert MySQL date to unix time int
    sub dateMySQL {
        my ($mydate) = @_;

        my ($year, $mon, $mday) = $mydate =~ /(\d{4})-(\d\d)-(\d\d)/
          or confess "Can't parse '$mydate'";
        $year -= 1900;
        $mon  -= 1;
        return POSIX::mktime(0, 0, 0, $mday, $mon, $year);
    }

    # Convert unix time int to MySQL datetime
    sub MySQLdatetime {
        my ($time) = @_;

        unless (defined $time) {
            $time = time;
        }
        my ($sec, $min, $hour, $mday, $mon, $year) = localtime($time);
        $year += 1900;
        $mon  += 1;
        return sprintf("%04d-%02d-%02d %02d:%02d:%02d",
            $year, $mon, $mday, $hour, $min, $sec);
    }

    # Convert MySQL datetime to unix time int
    sub datetimeMySQL {
        my ($mydatetime) = @_;

        my ($year, $mon, $mday, $hour, $min, $sec) =
          $mydatetime =~ /(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/
          or confess "Can't parse '$mydatetime'";
        $year -= 1900;
        $mon  -= 1;
        return POSIX::mktime($sec, $min, $hour, $mday, $mon, $year);
    }

    my (%months);
    {
        my $i = 1;
        %months = map { $_, $two_figure[ $i++ ] } qw( JAN FEB MAR APR MAY JUN
          JUL AUG SEP OCT NOV DEC );
    }

    # Fossil from old Acception module
    sub accept_date {
        my ($accn) = shift;

        if (@_) {
            $_ = shift;

            my ($unix);

            # Date in MySQL default date format
            if (/^\d{4}-\d\d-\d\d$/) {
                $unix = dateMySQL($_);
            }

            # EMBL format date
            elsif (my ($mday, $mon, $year) = /^(\d\d)-([A-Z]{3})-(\d{4})$/) {
                $mon  = $months{$mon};
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

{
    my (%species_chr);

    sub _init_species_chr_hash {

        # Zero the hash
        %species_chr = ();

        my $sth = prepare_statement(
            q{
            SELECT chromosome_id
              , species_name
              , chr_name
            FROM species_chromosome
            }
        );
        $sth->execute;
        while (my ($chr_id, $species, $chr) = $sth->fetchrow) {
            $species_chr{$species}{$chr} = $chr_id;
        }
    }

    sub chromosome_id_from_species_and_chr_name {
        my ($species, $chr) = @_;

        $species ||= 'UNKNOWN';
        $chr     ||= 'UNKNOWN';

        # Initialize the static hash the first time we are called
        _init_species_chr_hash() unless %species_chr;

        return $species_chr{$species}{$chr};
    }

    sub add_new_species_chr {
        my ($species, $chr) = @_;

        $species ||= 'UNKNOWN';
        $chr     ||= 'UNKNOWN';

        # Make sure we are in sync with the database
        _init_species_chr_hash();

        my $chr_id = $species_chr{$species}{$chr};
        if (defined $chr_id) {
            warn
"id ('$chr_id') already exists for species='$species' and chr='$chr'";
        }
        else {
            my $sth = prepare_statement(
                q{
                INSERT species_chromosome(chromosome_id
                  , species_name
                  , chr_name)
                VALUES (NULL,?,?)
                }
            );
            $sth->execute($species, $chr);
            $species_chr{$species}{$chr} = $sth->{'mysql_insertid'};
        }
        return $species_chr{$species}{$chr};
    }
}

sub project_name_from_accession {
    my ($acc) = @_;

    my $sth = prepare_statement(
        qq{
        SELECT project_name
        FROM project_acc
        WHERE accession = '$acc'
        }
    );
    $sth->execute;
    my ($name) = $sth->fetchrow;
    $name ||= undef;
    return $name;
}

sub sanger_name {
    my ($acc) = @_;

    my $sth = prepare_statement(
        qq{
        SELECT s.sequence_name
        FROM project_acc a
          , project_dump d
          , sequence s
        WHERE a.sanger_id = d.sanger_id
          AND d.seq_id = s.seq_id
          AND d.is_current = 'Y'
          AND a.accession = '$acc'
        }
    );
    $sth->execute;
    my ($name) = $sth->fetchrow;
    $name ||= "Em:$acc";
    return $name;
}

sub accession_from_sanger_name {
    my ($name) = @_;

    my $sth = prepare_statement(
        qq{
        SELECT a.accession
        FROM project_acc a
          , project_dump d
          , sequence s
        WHERE a.sanger_id = d.sanger_id
          AND d.seq_id = s.seq_id
          AND d.is_current = 'Y'
          AND s.sequence_name = '$name'
        }
    );
    $sth->execute;
    my ($acc) = $sth->fetchrow;
    return $acc;
}

sub project_name_and_suffix_from_sequence_name {
    my ($name) = @_;

    my $sth = prepare_statement(
        qq{
        SELECT a.project_name
          , a.project_suffix
        FROM project_acc a
          , project_dump d
          , sequence s
        WHERE a.sanger_id = d.sanger_id
          AND d.seq_id = s.seq_id
          AND d.is_current = 'Y'
          AND s.sequence_name = '$name'
        }
    );
    $sth->execute;
    my ($project, $suffix) = $sth->fetchrow;
    return ($project, $suffix);
}

sub accession_from_project_name {
    my ($name) = @_;

    my $sth = prepare_statement(
        qq{
        SELECT accession
        FROM project_acc
        WHERE project_name = '$name'
        }
    );
    $sth->execute;
    my ($accession) = $sth->fetchrow;
    return ($accession);
}

sub chromosome_from_project_name {
    my ($name) = @_;

    my $sth = prepare_statement(
        qq{
        SELECT SC.chr_name
        FROM sequence S,
            project_acc PA,
            project_dump PD,
            species_chromosome SC
        WHERE PA.project_name='$name'
            AND PA.sanger_id=PD.sanger_id
            AND PD.is_current='Y'
            AND S.seq_id=PD.seq_id
            AND S.chromosome_id=SC.chromosome_id
        }
    );
    $sth->execute;
    my ($chr_name) = $sth->fetchrow;
    return ($chr_name);
}

sub seq_id_from_project_name {
    my ($name) = @_;

    my $sth = prepare_statement(
        qq{
        SELECT PD.seq_id
        FROM project_acc PA,
            project_dump PD
        WHERE PA.project_name='$name'
            AND PA.sanger_id=PD.sanger_id
            AND PD.is_current='Y';
        }
    );
    $sth->execute;
    my ($seq_id) = $sth->fetchrow;
    return ($seq_id);
}

sub sanger_id_from_project_name {
    my ($name) = @_;

    my $sth = prepare_statement(
        qq{
        SELECT PD.sanger_id
        FROM project_acc PA,
            project_dump PD
        WHERE PA.project_name='$name'
            AND PA.sanger_id=PD.sanger_id
            AND PD.is_current='Y';
        }
    );
    $sth->execute;
	my @sanger_ids;
    while(my ($sanger_id) = $sth->fetchrow) {
		push(@sanger_ids, $sanger_id);
	}
	
	if(scalar @sanger_ids == 1) {
		return $sanger_ids[0];
	}
	else {
		warn "Could not identify a unique Sanger ID for project " . $name . "\n";
	    return;
	}
}

sub sanger_id_from_project_name_and_accession {
    my ($name, $accession) = @_;

    my $sth = prepare_statement(
        qq{
        SELECT PD.sanger_id
        FROM project_acc PA,
            project_dump PD
        WHERE PA.project_name='$name'
            AND PA.accession='$accession'
            AND PA.sanger_id=PD.sanger_id
            AND PD.is_current='Y';
        }
    );
    $sth->execute;
	my @sanger_ids;
    while(my ($sanger_id) = $sth->fetchrow) {
		push(@sanger_ids, $sanger_id);
	}
	
	if(scalar @sanger_ids == 1) {
		return $sanger_ids[0];
	}
	else {
		warn "Could not identify a unique Sanger ID for project " . $name . " and accession $accession\n";
	    return;
	}
}

sub species_from_project_name {
    my ($name) = @_;

    my $sth = prepare_statement(
        qq{
        SELECT SC.species_name
        FROM sequence S,
            project_acc PA,
            project_dump PD,
            species_chromosome SC
        WHERE PA.project_name='$name'
            AND PA.sanger_id=PD.sanger_id
            AND PD.is_current='Y'
            AND S.seq_id=PD.seq_id
            AND S.chromosome_id=SC.chromosome_id
        }
    );
    $sth->execute;
    my ($species) = $sth->fetchrow;
    return ($species);
}

### Unused and untested
sub sanger_id_from_accession {
    my ($acc) = @_;

    my $sth = prepare_cached_statement(
        q{
        SELECT sanger_id
        FROM project_acc
        WHERE accession = ?
        }
    );
    $sth->execute($acc);

    my (@sid);
    while (my ($sanger) = $sth->fetchrow) {
        push(@sid, $sanger);
    }
    if (@sid == 1) {
        return $sid[0];
    }
    elsif (@sid) {
        confess "Got multiple sanger IDs for '$acc':\n", map "  '$_'\n", @sid;
    }
    else {
        return;
    }
}

1;

__END__


=head1 NAME - Hum::Submission

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk
