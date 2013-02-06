
package Hum::Tracking;

=pod

=head1 NAME Hum::Tracking

=head1 DESCRIPTION

Contains a number of utility routines for
reading information from the Sanger oracle
I<Tracking> database.

=head1 SYNOPSIS

    use Hum::Tracking qw( expand_project_name );

=head1 SUBROUTINES

=over 4

=cut

use strict;
use warnings;
use WrapDBI;
use Exporter;
use POSIX ();
use Carp;

use vars qw( @ISA @EXPORT_OK );

@ISA = qw( Exporter );

@EXPORT_OK = qw(
  verbatim_chromosome_from_project
  clone_from_project
  clone_from_accession
  clone_type_seq_reason
  current_project_status_number
  set_project_status
  session_id
  chromosome_from_project
  entry_name
  expand_project_name
  intl_clone_name
  find_project_directories
  finished_accession
  fishData
  has_current_project_link
  is_assigned_to_finisher
  is_finished
  is_full_shotgun_complete
  is_private
  is_shotgun_complete
  library_and_vector
  library_and_vector_from_parent_project
  library_from_clone
  localisation_data
  online_path_from_project
  parent_project
  prepare_track_statement
  prepare_cached_track_statement
  project_from_clone
  project_finisher
  project_type
  project_team_leader
  record_accession_data
  record_finished_length
  ref_from_query
  sanger_id_to_project
  species_from_project
  track_db
  track_db_user
  track_db_commit
  track_db_rollback
  unfinished_accession
  iso2time
  time2iso
);

=head2 current_project_status_number( PROJECT )

Returns the current numerical status of the
project.

=cut

{
    my ($sth);

    sub current_project_status_number {
        my ($project) = @_;

        $sth ||= prepare_track_statement(
            q{
            SELECT status
            FROM project_status
            WHERE projectname = ?
              AND iscurrent = 1
            }
        );
        $sth->execute($project);
        my ($status) = $sth->fetchrow;
        return $status || 0;
    }
}

=head2 set_project_status ( PROJECT )

Updates project_status table with the status value specified

=cut

{
    my ($set_not_current, $set_status);

    sub set_project_status {
        my ($project_name, $status, $remark) = @_;

        $remark ||= '';
        my $operator = getpwuid(($<)[0]);
        my ($program) = $0 =~ m{([^/]+)$};

        $set_not_current ||= prepare_track_statement(
            q{
            UPDATE project_status
            SET iscurrent = 0
            WHERE projectname = ?
            }
        );

        $set_status ||= prepare_track_statement(
            qq{
            INSERT INTO project_status( projectname
                  , status
                  , statusdate
                  , iscurrent
                  , program
                  , operator
                  , sessionid
                  , remark )
            VALUES ( ?, ?, SYSDATE, 1, ?,?,?,?)
            }
        );

        eval {
            $set_not_current->execute($project_name);
            $set_status->execute($project_name, $status, $program, $operator, session_id(), $remark,);
        };

        if ($@) {
            track_db_rollback();
            die $@;
        }
        else {
            track_db_commit();
        }
    }
}

=head2 session_id ( PROJECT )

Returns the next session_id

=cut

{
    my ($sid);

    sub session_id {
        unless ($sid) {
            my $sth = prepare_track_statement(
                q{
                SELECT seq_session.nextval
                FROM dual
                }
            );
            $sth->execute;
            ($sid) = $sth->fetchrow;
        }
        return $sid;
    }
}

=head2 is_finished( PROJECT )

Returns the current status (always TRUE) if the
project currently has one of the finished
statuses.

=cut

{
    my ($sth);

    sub is_finished {
        my ($project) = @_;

        $sth ||= prepare_track_statement(
            q{
            SELECT status
            FROM project_status
            WHERE projectname = ?
              AND status IN(20,34,35,32,21,22,23,44,48)
              AND iscurrent = 1
            }
        );
        $sth->execute($project);
        my ($status) = $sth->fetchrow;
        return $status;
    }
}

{
    my ($sth, $sth_parent);

    sub is_private {
        my ($project, $is_parent) = @_;
        my $this_sth;
        my $sql = q{SELECT DISTINCT isprivate FROM project};

        if ($is_parent) {
            $this_sth = $sth_parent ||= prepare_track_statement($sql . ' WHERE parent_project = ?');
        }
        else {
            $this_sth = $sth ||= prepare_track_statement($sql . ' WHERE projectname = ?');
        }
        $this_sth->execute($project);
        my ($is_private) = $this_sth->fetchrow;
        return $is_private;
    }
}

=pod

=head2 is_shotgun_complete

Returns TRUE if the project has ever had a status
of Shotgun_complete or Half_shotgun_complete.

=cut

{
    my ($count_shotgun);

    sub is_shotgun_complete {
        my ($project) = @_;

        $count_shotgun ||= prepare_track_statement(
            qq{
            SELECT COUNT(*)
            FROM project_status 
            WHERE status IN(15,30)
            AND projectname = ?
            }
        );
        $count_shotgun->execute($project);

        return $count_shotgun->fetchrow_arrayref->[0];
    }
}

=pod

=head2 is_full_shotgun_complete

Returns TRUE if the project has ever had a status
of Shotgun_complete.

=cut

{
    my ($count_full_shotgun);

    sub is_full_shotgun_complete {
        my ($project) = @_;

        $count_full_shotgun ||= prepare_track_statement(
            qq{
            SELECT COUNT(*)
            FROM project_status 
            WHERE status = 15
            AND projectname = ?
            }
        );
        $count_full_shotgun->execute($project);

        return $count_full_shotgun->fetchrow_arrayref->[0];
    }
}

=pod

=head2 is_assigned_to_finisher

Returns TRUE if the project has ever had a status
of "Assigned to finisher" or "Assigned to prefinisher".

=cut

{
    my ($count_assigned);

    sub is_assigned_to_finisher {
        my ($project) = @_;

        $count_assigned ||= prepare_track_statement(
            qq{
            SELECT COUNT(*)
            FROM project_status 
            WHERE status IN(17,18)
            AND projectname = ?
            }
        );
        $count_assigned->execute($project);

        return $count_assigned->fetchrow_arrayref->[0];
    }
}

=pod

=head2 has_current_project_link

Returns TRUE if the project has a current entry
in the project_link table.

=cut

{
    my ($count_links);

    sub has_current_project_link {
        my ($project) = @_;

        $count_links ||= prepare_track_statement(
            q{
            SELECT COUNT(*)
            FROM project_link
            WHERE projectname = ?
              AND is_current = 1
            }
        );
        $count_links->execute($project);

        return $count_links->fetchrow_arrayref->[0];
    }
}

=pod

=head2 library_and_vector( PROJECT )

Given the name of a PROJECT, returns the name of
the library and the name of the library vector
(plasmid).  Returns undef on failure.

=cut

{
    my ($sth, $sth_parent);

    sub library_and_vector {
        my ($project) = @_;

        $sth ||= prepare_track_statement(
            q{
            SELECT NVL(l.external_libraryname, l.libraryname)
              , l.vectorname
              , l.description
            FROM clone_project cp
              , clone c
              , library l
            WHERE cp.clonename = c.clonename
              AND c.libraryname = l.libraryname
              AND cp.projectname = ?
            }
        );
        $sth->execute($project);
        my ($lib, $vec, $desc) = $sth->fetchrow;

        # Catch bad vector and library names
        if ((!$lib) || ($lib =~ /(^NONE$|UNKNOWN)/i)) {
            ($lib, $vec, $desc) = (undef, undef, undef);
        }
        return ($lib, $vec, $desc);
    }

    sub library_and_vector_from_parent_project {
        my ($project) = @_;
        my $lib_hash;

        $sth_parent ||= prepare_track_statement(
            q{
            SELECT REPLACE(c.clonename, l.internal_prefix, concat(l.external_prefix, '-'))
              , NVL(l.external_libraryname, l.libraryname)
              , l.vectorname
              , l.description
            FROM clone_project cp
              , clone c
              , project p
              , library l
            WHERE cp.clonename = c.clonename
              AND c.libraryname = l.libraryname
              AND cp.projectname = p.projectname
              AND p.parent_project = ?
            }
        );
        $sth_parent->execute($project);
        while (my ($clone, $lib, $vec, $desc) = $sth_parent->fetchrow) {

            # Catch bad vector and library names
            if ($lib =~ /(^NONE$|UNKNOWN)/i) {
                ($lib, $vec, $desc) = (undef, undef, undef);
            }
            $lib_hash->{$clone} = [ $lib, $vec, $desc ];

        }

        return $lib_hash;
    }
}

=pod

=head2 ref_from_query( SQL )

Returns a reference to an array of anonymous
arrays containing the results from running the
B<SQL> query on the I<Tracking> database.  This
is the interface to the tracking database for all
of B<Tracking.pm>.

=cut

sub ref_from_query {
    my ($query) = @_;

    my $dbh = track_db();

    my $sth = $dbh->prepare($query);
    $sth->execute();
    return $sth->fetchall_arrayref();
}

=pod

=head2 track_db

Cache and return a B<DBI> handle to the Tracking database.

Note that once this is created, further changes to configuration will
have no effect.

Also when using L<WrapDBI>s WRAPDBI_TEST_CONFIG environment variable,
note that it only has effect if set before C<use WrapDBI> is called by
I<any> module.

=head2 prepare_track_statement

    my $sth = prepare_track_statement($sql);

Returns a prepared statement handle for the
tracking database.  Each prepared statement is
added to a list of statements, and finish is
called on each of these statements during an END
block, to ensure a graceful exit.

=cut

{
    my ($dbh, $user, @active_statements);

    sub track_db {
        my $u = track_db_user();
        $dbh ||= WrapDBI->connect(
            $u,
            {
                RaiseError  => 1,
                AutoCommit  => 0,
                LongReadLen => 1024 ** 2,
            }
        );

        return $dbh || confess "Can't connect as user '$u'";
    }

    sub track_db_commit {
        $dbh->commit if $dbh;
    }

    sub track_db_rollback {
        $dbh->rollback if $dbh;
    }

    sub track_db_user {
        my ($arg) = @_;

        if ($arg) {
            if ($dbh) {
                confess "Trying to set user to '$arg' but already connected as user '$user'\n",
                    "Call track_db_user(\$user) before track_db() or prepare_track_statement()";
            }
            $user = $arg;
        }
        $user ||= 'reports';
        return $user;
    }

    sub prepare_track_statement {
        my ($query) = @_;

        #warn $query;

        my $sth = track_db()->prepare($query);
        push(@active_statements, $sth);    ### Could be cause of open cursors error?
        ### ... *is* the cause of open cursors error!
        ### Try moving your prepare statments outside any loop.

        #warn "Now ", scalar(@active_statements), " active statements\n";
        return $sth;
    }

    sub prepare_cached_track_statement {
        my ($query) = @_;

        #warn $query;

        my $sth = track_db()->prepare_cached($query);
        push(@active_statements, $sth);
        return $sth;
    }

    END {

        # Close statements gracefully
        foreach my $s (@active_statements) {
            $s->finish if $s;
        }

        ### This disconnect has a side effect of calling commit.
        ### We probably shouldn't have it in there.
        # Then disconnect
        $dbh->disconnect() if $dbh;
    }
}

=pod

=head2 expand_project_name( NAME )

Many projects names are a truncated version of
the name of the clone in the project.  We prefer
to have the full project name in humace, and this
routine returns the name of the clone if it is
the only clone linked to the project B<NAME>, or
just returns B<NAME>.

=cut

sub expand_project_name {
    my ($name) = @_;

    my $ans = ref_from_query(
        qq(
        SELECT clonename
        FROM clone_project
        WHERE projectname = '$name'
        )
    );

    if (@$ans == 1) {
        return $ans->[0][0];
    }
    else {
        return $name;
    }
}

=pod

=head2 clone_from_accession

Returns the corresponding clone name for the
given accession, or undef.

=cut

{
    my ($get_clone);

    sub clone_from_accession {
        my ($accession) = @_;

        $get_clone ||= prepare_track_statement(
            q{
            SELECT cs.clonename
            FROM sequence s
              , clone_sequence cs
            WHERE s.seq_id = cs.seq_id
              AND cs.is_current = 1
              AND s.accession = ?
            }
        );
        $get_clone->execute($accession);

        if (my ($clone) = $get_clone->fetchrow) {
            return $clone;
        }
        else {
            return;
        }
    }
}

=pod

=head2 clone_from_project

Returns the corresponding clone name for the
given project name if there is only one, or undef.

=cut

{
    my ($get_clone);

    sub clone_from_project {
        my ($project) = @_;

        $get_clone ||= prepare_track_statement(
            q{
            SELECT clonename
            FROM clone_project
            WHERE projectname = ?
            }
        );
        $get_clone->execute($project);

        if (my ($clone) = $get_clone->fetchrow) {
            return $clone;
        }
        else {
            return;
        }
    }
}

=pod

=head2 clone_type_seq_reason

Returns the corresponding clone type and sequencing reason for the
given project name, or undef.

=cut

{
    my ($get_type_reason);

    sub clone_type_seq_reason {
        my ($project) = @_;

        $get_type_reason ||= prepare_track_statement(
            q{
            SELECT ctd.description
              , srd.description
            FROM clone_project cp
              , clone c
              , clonetypedict ctd
              , seqreasondict srd
            WHERE cp.clonename = c.clonename
              AND c.clone_type = ctd.id_dict
              AND c.seq_reason = srd.id_dict
              AND cp.projectname = ?
            }
        );
        $get_type_reason->execute($project);

        if (my ($type, $reason) = $get_type_reason->fetchrow) {
            return ($type, $reason);
        }
        else {
            return;
        }
    }
}

=pod

=head2 primer_pair

Returns the primer pair used for obtaining the PCR product with the given project name, or undef.

=cut

{
    my ($get_primer_pair);

    sub primer_pair {
        my ($project) = @_;

        $get_primer_pair ||= prepare_track_statement(
            q{
            SELECT p1.primerseq
              , p2.primerseq 
            FROM primer p1
              , primer p2
              , pcr_product pp
              , pcrproduct_status pps 
              , clone_project cp
            WHERE pp.primer_1 = p1.id_primer
              AND pp.primer_2 = p2.id_primer 
              AND pp.dna_source = cp.projectname 
              AND pp.id_pcrproduct = pps.id_pcrproduct
              AND pps.status = 1 
              AND pps.iscurrent = 1
              AND cp.projectname = ?
            }
        );
        $get_primer_pair->execute($project);

        if (my ($primer1, $primer2) = $get_primer_pair->fetchrow) {
            return ($primer1, $primer2);
        }
        else {
            return;
        }
    }
}

=pod

=head2 project_from_clone

Returns the corresponding project name for a
given clone name if there is only one, or undef.

=cut

sub project_from_clone {
    my ($clone) = @_;

    my $ans = ref_from_query(
        qq(
        SELECT projectname
        FROM clone_project
        WHERE clonename = '$clone'
        )
    );

    if (@$ans == 1) {
        return $ans->[0][0];
    }
    else {
        return;
    }
}

=pod

=head2 parent_project

Returns the corresponding parent project name for a
given project name or undef.

=cut

{
    my ($get_parent);

    sub parent_project {
        my ($project) = @_;

        $get_parent ||= prepare_track_statement(
            q{
                SELECT parent_project
                FROM project
                WHERE projectname = ?
                }
        );
        $get_parent->execute($project);
        if (my ($parent) = $get_parent->fetchrow) {
            return $parent;
        }
        else {
            return;
        }
    }
}

=pod

=head2 STRING = intl_clone_name( STRING )

Given the name of a clone, returns the
International Clone name for that clone.

=cut

{
    my ($sth, %clone_intl);

    sub intl_clone_name {
        my ($clone) = @_;

        confess "Missing clone argument" unless $clone;

        my ($intl);
        unless ($intl = $clone_intl{$clone}) {
            $sth ||= prepare_track_statement(
                q{
                SELECT l.internal_prefix
                  , l.external_prefix
                FROM clone c
                  , library l
                WHERE l.libraryname = c.libraryname
                  AND c.clonename = ?
                }
            );
            $sth->execute($clone);
            my ($int, $ext) = $sth->fetchrow;
            $sth->finish;

            $intl = $clone;
            if ($int and $ext) {
                if($int eq 'NONE') {$int = ''}
                substr($intl, 0, length($int)) = "$ext-";
            }
            $clone_intl{$clone} = $intl;
        }

        return $intl;
    }
}

=pod

=pod

=head2 find_project_directories( LIST_OF_PROJECT_NAMES )

Returns ref to a hash, with keys the project
names, and values the path to the project, or
undef if the path could not be found. 
B<find_project_directories>  croaks if it finds
more than one online path for any of the
projects.

=cut

sub find_project_directories {
    my @name_list = @_;
    confess "No names supplied" unless @name_list;
    my %dir = map { $_, undef } @name_list;
    my $projects = join(',', map "'$_'", @name_list);

    my $ans = ref_from_query(
        qq(
        SELECT p.projectname
          , o.online_path
        FROM project p
          , online_data o
        WHERE p.id_online = o.id_online
          AND o.is_available = 1
          AND p.projectname IN($projects)
        )
    );

    # Store results in %dir
    for (my $i = 0; $i < @$ans; $i++) {
        my ($name, $dir) = @{ $ans->[$i] };

        # Check that we don't get multiple online paths for one project
        if ($dir{$name}) {
            confess "Multiple directories for '$name' : ", map "  '$_->[1]'\n", grep $_->[0] eq $name, @$ans;
        }
        else {
            $dir{$name} = $dir;
        }
    }

    return \%dir;
}

=pod

=head2 finised_accession( PROJECT, SUFFIX )

Returns the accession number for the finished
sequence corresponding to project B<PROJECT> and
suffix B<SUFFIX>.  If B<SUFFIX> is not TRUE, then
it queries for an empty suffix.  Multiple
matches, or no matches, are fatal.

=cut

sub finished_accession {
    my ($project, $suffix) = @_;

    my $query = qq( SELECT accession
                    FROM finished_submission
                    WHERE projectname = '$project'
                      AND suffix );
    if ($suffix) {
        $query .= qq( = '$suffix' );
    }
    else {
        $query .= qq( IS NULL );
    }

    my $ans = ref_from_query($query);
    if (@$ans == 1) {
        return $ans->[0][0];
    }
    elsif (@$ans > 1) {
        die "Mulitple accessions found for '$project' and suffix '$suffix' : ", join(', ', map "'$_->[0]'", @$ans);
    }
    else {
        die "No accession found for projectname '$project' and suffix '$suffix'";
    }
}

=pod

=head2 entry_name( ACCESSION )

Returns the EMBL ID corresponding to the
ACCESSION supplied.

=cut

sub entry_name {
    my ($acc) = @_;

    # Get the entryname for this accession

    my $ans = ref_from_query(
        qq( 
                                SELECT name
                                FROM embl_submission
                                WHERE accession = '$acc'
                                )
    );
    my ($entry_name);
    if (@$ans > 1) {
        die "Multiple names for accession '$acc' : ", join(', ', map "'$_->[0]'", @$ans);
    }
    elsif (@$ans == 0) {
        $entry_name = 'ENTRYNAME';
    }
    else {
        $entry_name = $ans->[0][0];
    }

    return $entry_name;
}

=pod

=head2 unfinished_accession( PROJECT, DUMMY_FLAG )

Returns the accession number for the unfinished
sequence corresponding to project B<PROJECT>.  If
B<DUMMY_FLAG> is TRUE, then the appropriate dummy
accession number for EMBL is returned.  No
matches, or multiple matches, are otherwise
fatal.

=cut

sub unfinished_accession {
    my ($project, $dummy_flag) = @_;

    my $query = qq( 
                    SELECT accession
                    FROM unfinished_submission
                    WHERE projectname = '$project'
                    );

    my $ans = ref_from_query($query);
    if (@$ans == 1) {
        return $ans->[0][0];
    }
    elsif (@$ans > 1) {
        die "Mulitple accessions found for '$project' : ", join(', ', map "'$_->[0]'", @$ans);
    }
    else {
        if ($dummy_flag) {
            return 'ACCESSION';
        }
        else {
            die "No accession found for projectname '$project'";
        }
    }
}

=head2 (ACC, INSTITUTE_CODE) = external_draft_info( PROJECT )

For clones finished by the Sanger Centre, but
where the draft sequence was produced elsewhere.

=cut

{
    my ($sth, $sth_parent);

    sub external_draft_info {
        my ($project, $is_parent) = @_;
        my $this_sth;
        if ($is_parent) {
            $this_sth = $sth_parent ||= prepare_track_statement(
                q{
            SELECT DISTINCT s.remark
            FROM project_status s, project p
            WHERE s.status = 26
            AND s.projectname = p.projectname
            AND p.parent_project = ?    
            }
            );
        }
        else {
            $this_sth = $sth ||= prepare_track_statement(
                q{
            SELECT remark
            FROM project_status
            WHERE status = 26
              AND projectname = ?   
            }
            );
        }
        $this_sth->execute($project);
        while (my ($remark) = $this_sth->fetchrow) {
            next unless $remark;
            my ($centre, $acc) = $remark =~ /^(\w+)\s+\((\w+)\)/;
            return ($acc, $centre) if $acc and $centre;
        }
        return;
    }
}

=pod

=head2 (CHR, MAP) = localisation_data( PROJECT )

Returns the chromosome and cytogenetic location
(if FISH has been done on the project) for
project named PROJECT.

=cut

sub localisation_data {
    my ($project) = @_;

    return (chromosome_from_project($project), fishData($project));
}

{
    my ($get_chr, $get_clone2chr);

    sub chromosome_from_project {
        my ($project) = @_;

        $get_chr ||= prepare_track_statement(
            q{
            SELECT cd.chromosome
            FROM chromosomedict cd
              , clone c
              , clone_project cp
            WHERE cd.id_dict = c.chromosome
              AND c.clonename = cp.clonename
              AND cp.projectname = ?
            }
        );
        $get_chr->execute($project);

        my ($chr) = $get_chr->fetchrow;
        if ($chr and $chr !~ /^u/i) {
            return $chr;
        }
        else {
            return;
        }
    }

    sub verbatim_chromosome_from_project {
        my ($project) = @_;

        $get_chr ||= prepare_track_statement(
            q{
            SELECT cd.chromosome
            FROM chromosomedict cd
              , clone c
              , clone_project cp
            WHERE cd.id_dict = c.chromosome
              AND c.clonename = cp.clonename
              AND cp.projectname = ?
            }
        );
        $get_chr->execute($project);

        my ($chr) = $get_chr->fetchrow;
        if ($chr) {
            return $chr;
        }
        else {
            return;
        }
    }

    sub clone_to_chromosome_from_parent_project {
        my ($project) = @_;
        my $hash;

        $get_clone2chr ||= prepare_track_statement(
            q{
            SELECT replace(c.clonename,l.internal_prefix,concat(external_prefix,'-')), cd.chromosome
            FROM chromosomedict cd,
                clone c,
                clone_project cp,
                project p,
                library l
            WHERE cd.id_dict = c.chromosome
            AND c.clonename = cp.clonename
            AND cp.projectname =  p.projectname
            AND p.parent_project = ?
            AND c.libraryname = l.libraryname
            }
        );
        $get_clone2chr->execute($project);

        while (my ($clone, $chr) = $get_clone2chr->fetchrow) {
            $hash->{$clone} = $chr;
        }

        return $hash;
    }
}

{
    my ($get_fish);

    # Get most recent fish result from tracking db
    sub fishData {
        my ($project) = @_;

        $get_fish ||= prepare_track_statement(
            q{
            SELECT remark
            FROM project_status
            WHERE status = 9
              AND projectname = ?
            ORDER BY statusdate DESC
            }
        );
        $get_fish->execute($project);

        my ($map);
        if (my ($remark) = $get_fish->fetchrow) {
            $map = fishParse($remark)
              or warn "Can't parse fish tag ('$remark')\n";
        }

        if ($map) {
            return $map;
        }
        else {
            return;
        }
    }
}

sub fishParse {
    my ($fishLine) = @_;
    $fishLine =~ s/\s+$//;    # Remove trailing space
    $fishLine =~ s/\//-/g;    # Replace slashes with dashes
    my (@catch);
    if (@catch = $fishLine =~ /^[0-9XY]{0,2}([pq])(\d*\.?\d+)\s*(-)\s*[0-9XY]{0,2}[pq](\d*\.?\d+)$/) {
    }
    elsif (@catch = $fishLine =~ /^[0-9XY]{0,2}([pq])(\d*\.?\d+)\s*(-)\s*[pq]{0,1}(\d*\.?\d+)$/) {
    }
    elsif (@catch = $fishLine =~ /^[0-9XY]{0,2}([pq])(\d*\.?\d+)$/) {
    }
    else {
        return;
    }
    return join('', @catch);
}

{
    my ($get_species, $get_species_parent);

    sub species_from_project {
        my ($project) = @_;

        $get_species ||= prepare_track_statement(
            q{
            SELECT c.speciesname
            FROM clone c
              , clone_project cp
            WHERE c.clonename = cp.clonename
              AND cp.projectname = ?
            }
        );
        $get_species->execute($project);

        if (my ($species) = $get_species->fetchrow) {
            return $species;
        }
        else {
            return;
        }
    }

    sub species_from_parent_project {
        my ($project) = @_;

        my $s;

        $get_species_parent ||= prepare_track_statement(
            q{
            SELECT DISTINCT c.speciesname
            FROM clone c,
                clone_project cp,
                project p
            WHERE c.clonename = cp.clonename
            AND cp.projectname = p.projectname
            AND p.parent_project = ?
            }
        );
        $get_species_parent->execute($project);

        while (my ($species) = $get_species_parent->fetchrow) {
            push @$s, $species;
        }

        return join(",", @$s);
    }
}

sub library_from_clone {
    my ($clone) = @_;

    my $sth = prepare_cached_track_statement(
        q{
        SELECT libraryname
        FROM clone
        WHERE clonename = ?
        }
    );
    $sth->execute($clone);
    my ($lib) = $sth->fetchrow;
    $sth->finish;
    return $lib;
}

{
    my ($get_online_path);

    sub online_path_from_project {
        my ($project) = @_;

        $get_online_path ||= prepare_track_statement(
            q{
            SELECT o.online_path
            FROM project p
              , online_data o
            WHERE p.id_online = o.id_online
              AND o.is_available = 1
              AND p.projectname = ?
            }
        );
        $get_online_path->execute($project);

        if (my ($path) = $get_online_path->fetchrow) {
            return $path;
        }
        else {
            return;
        }
    }
}

=pod

=head2 project_finisher( PROJECT );

Returns the finisher for a project in EMBL author
format (eg: "J. Smith").

=cut

{
    my ($get_finisher);

    sub project_finisher {
        my ($project) = @_;

        $get_finisher ||= prepare_track_statement(
            q{
            SELECT p.forename
              , p.surname
            FROM project_role pr
              , team_person_role tpr
              , person p
            WHERE pr.id_role = tpr.id_role
              AND tpr.id_person = p.id_person
              AND pr.projectname = ?
              AND tpr.roletype = 'Finishing'
            ORDER BY pr.assigned_from DESC        
            }
        );
        $get_finisher->execute($project);

        if (my ($forename, $surname) = $get_finisher->fetchrow) {

            # Abbreviate forename
            $forename =~ s/^(.).+/$1\./ or return;
            return ("$surname $forename");
        }
        else {
            confess "No finisher for project '$project'";
        }
    }
}

=pod

=head2 project_team_leader( PROJECT );

Returns the team leader for a project in EMBL author
format (eg: "J. Smith").

=cut

{
    my ($get_team_leader);

    sub project_team_leader {
        my ($project) = @_;

        $get_team_leader ||= prepare_track_statement(
            q{
            SELECT p.forename
              , p.surname
            FROM project_owner o
              , team t
              , person p
            WHERE o.teamname = t.teamname
              AND t.teamleader = p.id_person
              AND o.projectname = ?
            ORDER BY o.owned_from DESC
            }
        );
        $get_team_leader->execute($project);

        if (my ($forename, $surname) = $get_team_leader->fetchrow) {

            # Abbreviate forename
            $forename =~ s/^(.).+/$1\./ or return;
            return ("$surname $forename");
        }
        else {
            confess "No team leader for project '$project'";
        }
    }
}

=head2 sanger_id_to_project

    ($proj, $suffix) = sanger_id_to_project($sanger_id);

Takes a sanger ID (eg: '') and attempts to get
the project name for it by consulting the project
table in oracle.  B<$suffix> is undef if
$sanger_id doesn't have a suffix.  Method is
fatal if project name isn't found, or if there is
more than one match in the project table.

=cut

{
    my ($get_project_name);

    sub sanger_id_to_project {
        my ($sid) = @_;

        my ($PROJ, $suffix) = $sid =~ /^_(.+?)(?:__([A-Z]))?$/;

        $get_project_name ||= prepare_track_statement(
            q{
            SELECT projectname
            FROM project
            WHERE UPPER(projectname) = ?
            }
        );
        $get_project_name->execute($PROJ);

        my $ans = $get_project_name->fetchall_arrayref;

        my ($proj);
        if (@$ans) {
            if (@$ans > 1) {
                die "Ambiguous matches to '$sid' ('$PROJ') : ", join(', ', map "'$_->[0]'", @$ans), "\n";
            }
            $proj = $ans->[0][0];
        }
        else {
            die "Can't get project name for '$sid' ('$PROJ')";
        }

        return ($proj, $suffix);
    }
}

#         ID_DICT  DESCRIPTION                     
#         -------  --------------------------------
#         1        Entered                         
#         2        Selected for sequencing         
#         3        Received                        
#         4        Streaked                        
#         5        DNA made                        
#         6        Sent to fingerprinting          
#         7        Fingerprinted                   
#         8        Sent for FISHing                
#         9        FISHed                          
#         10       Library made                    
#         11       Library testing                 
#         12       Library tested                  
#         13       Shotgun                         
#         14       Shotgun on hold                 
#         15       Shotgun complete                
#         16       Assembly start                  
#         17       Assigned to prefinisher         
#         18       Assigned to finisher            
#         19       Contiguous                      
#         20       Finished                        
#         21       Analysed                        
#         22       Submitted to EMBL               
#         23       Archived                        
#         24       Cancelled                       
#         26       On hold                         
#         30       Half shotgun complete           
#         31       Cleared for library making      
#         32       Submitted for analysis          
#         33       Selected for top-up             
#         34       Submitted for QC checking       
#         35       QC Checked                      
#         36       Selected for auto-prefinishing  
#         37       Auto-prefinishing complete      
#         38       Project closed                  
#         39       Transferred to Illumina         
#         40       Sequencescape Workflow Commenced
#         41       Sequencescape Workflow Completed
#         42       GRC Placeholder Clone           
#         43       Pooled Clone Assigned           
#         44       Pooled Clone Finished           
#         45       Externally Finished             
#         46       SS Indexed Workflow Completed   
#         47       Indexed Clone Assigned          
#         48       Indexed Clone Finished          
#         49       Indexed Manually Improved       



{
    my $guess_type;

    my %status_type = (
        15 => 'GAP4',           # Shotgun complete
        16 => 'GAP4',           # Assembly start
        30 => 'GAP4',           # Half shotgun complete
        53 => 'GAP4',           # Read into Gap4

        43 => 'POOLED',         # Pooled Clone Assigned
        44 => 'POOLED',         # Pooled Clone Finished

        46 => 'MULTIPLEXED',    # SS Indexed Workflow Complete
        47 => 'MULTIPLEXED',    # Indexed Clone Assinged
        48 => 'MULTIPLEXED',    # Indexed Clone Finished
        49 => 'MULTIPLEXED',    # Indexed Manually Improved
        52 => 'MULTIPLEXED',    # Read into Gap5
        
        );

    sub project_type {
        my ($project) = @_;

        $guess_type ||= prepare_track_statement(q{
            SELECT child_p.projectname child
              , ps.status
            FROM project p
              , project_status ps
              , project child_p
            WHERE p.projectname = ps.projectname
              AND p.projectname = child_p.parent_project (+)
              AND p.projectname = ?
            ORDER BY ps.statusdate ASC
        });
        $guess_type->execute($project);

        my $type;
        while (my ($child, $status) = $guess_type->fetchrow) {
            if ($child) {
                $type = 'PROJECT_POOL'; 
            }
            elsif (my $t = $status_type{$status}) {
                $type = $t;
            }
        }
        
        return $type;
    }
}

=head2 time2iso and iso2time

Convert to ISO format time, eg:

  2002-11-08 10:39:41

from a UNIX time int and back.  If no argument is
given to time2iso it uses the current time.

=cut

sub time2iso {
    my ($time) = @_;

    my ($sec, $min, $hour, $mday, $mon, $year) = localtime($time);
    return sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec);
}

sub iso2time {
    my $iso = shift || die "No iso time given";

    my ($year, $mon, $mday, $hour, $min, $sec) = $iso =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/
      or confess "Can't parse ISO time string '$iso'";
    $year -= 1900;
    $mon--;
    return POSIX::mktime($sec, $min, $hour, $mday, $mon, $year);
}

=head2 record_finished_length

    record_finished_length(PROJECT_NAME, LENGTH)

Updates the INTERNAL_LENGTH_BP column of the
PROJECT table with the given length.

=cut

{
    my ($lock, $record);

    sub record_finished_length {
        my ($project, $length) = @_;

        # Check we're given a vanilla integer
        unless ($length =~ /^\d+$/) {
            confess "Non-integer length ('$length')";
        }

        $lock ||= prepare_track_statement(
            qq{
            SELECT rowid
            FROM project
            WHERE projectname = ?
            FOR UPDATE
            }
        );

        $record ||= prepare_track_statement(
            qq{
            UPDATE project
            SET internal_length_bp = ?
            WHERE rowid = ?
            }
        );

        eval {
            $lock->execute($project);
            my ($rowid) = $lock->fetchrow
              or confess "No ROWID for project '$project'";
            $record->execute($length, $rowid);
            $record->rows or confess "zero rows affected\n";
        };

        if ($@) {
            confess "Error updating internal_length_bp:\n$@";
        }
        else {
            track_db_commit();
        }

        return 1;
    }
}

=head2 record_accession_data

    record_accession_data( PROJECT_NAME, SUFFIX,
        HTGS_PHASE, ACCESSION, EMBL_ID, LENGTH );

Populates the EMBL_SUBMISSION and either the
UNFINISHED_SUBMISSION or FINISHED_SUBMISSION
table, depending on whether HTGS_PHASE is B<1> or
B<3> respectively.  B<track_db_commit> is called
if no errors are encountered.

=cut

sub record_accession_data {
    my ($project, $suffix, $phase, $acc, $embl_name, $length) = @_;

    die "unknown htgs_phase '$phase'" unless $phase =~ /^[123]$/;
    unless ($project and $acc and $embl_name and $length) {
        confess "Missing argument";
    }

    eval {
        _store_embl_submission($acc, $embl_name, $length);

        if ($phase == 3) {
            _store_finished_submission($project, $acc, $suffix);
        }
        else {
            _store_unfinished_submission($project, $acc);
        }
    };
    if ($@) {
        track_db_rollback();
        confess $@;
    }
    else {
        track_db_commit();
    }
}

{
    my ($sub_get, $sub_ins, $sub_upd);

    sub _store_embl_submission {
        my ($acc, $embl_name, $length) = @_;

        # Do we have an entry for this accession?
        $sub_get ||= prepare_track_statement(
            q{
            SELECT 1
              , name
              , length_bp
            FROM embl_submission
            WHERE accession = ?
            }
        );
        $sub_get->execute($acc);
        my ($exists, $db_name, $db_length) = $sub_get->fetchrow;
        if ($exists) {
            local $^W = 0;

            # Update the entry if the embl id or length are different
            if ($length ne $db_length or $embl_name ne $db_name) {
                warn "Updating entry for accession $acc\n";
                $sub_upd ||= prepare_track_statement(
                    q{
                    UPDATE embl_submission
                    SET name = ?
                      , length_bp = ?
                    WHERE accession = ?
                    }
                );
                $sub_upd->execute($embl_name, $length, $acc);
            }
        }
        else {
            warn "New accession $acc\n";

            # Insert a new entry
            $sub_ins ||= prepare_track_statement(
                q{
                INSERT INTO embl_submission( accession
                      , name
                      , length_bp )
                VALUES (?,?,?)
                }
            );
            $sub_ins->execute($acc, $embl_name, $length);
        }
    }
}

{
    my ($unf_count, $unf_ins);

    sub _store_unfinished_submission {
        my ($project, $acc) = @_;

        # Update unfinished_submission
        $unf_count ||= prepare_track_statement(
            q{
            SELECT count(*)
            FROM unfinished_submission
            WHERE projectname = ?
            AND accession = ?
            }
        );
        $unf_count->execute($project, $acc);
        my ($count) = $unf_count->fetchrow;
        unless ($count) {
            warn "inserting new unfinished $acc for $project\n";
            $unf_ins ||= prepare_track_statement(
                q{
                INSERT INTO unfinished_submission( projectname
                      , accession )
                VALUES(?,?)
                }
            );
            $unf_ins->execute($project, $acc);
        }
    }
}

{
    my ($fin_get, $fin_ins, $fin_upd);

    sub _store_finished_submission {
        my ($project, $acc, $suffix) = @_;

        $fin_get ||= prepare_track_statement(
            q{
            SELECT 1, suffix
            FROM finished_submission
            WHERE projectname = ?
            AND accession = ?
            }
        );
        $fin_get->execute($project, $acc);
        my ($exists, $db_suffix) = $fin_get->fetchrow;
        unless ($exists) {
            warn "inserting new finished $acc for $project\n";
            $fin_ins ||= prepare_track_statement(
                q{
                INSERT INTO finished_submission( projectname
                      , accession
                      , suffix )
                VALUES(?,?,?)
                }
            );
            $fin_ins->execute($project, $acc, $suffix);
        }
        elsif (($suffix || 'NULL') ne ($db_suffix || 'NULL')) {

            # This may never happen, so hasn't been tested
            warn "updating suffix for finished $acc for $project\n";
            $fin_upd ||= prepare_track_statement(
                q{
                UPDATE finished_submission
                SET suffix = ?
                WHERE projectname = ?
                  AND accession = ?
                }
            );
            $fin_upd->execute($suffix, $project, $acc);
        }
    }
}

1;

__END__

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>

