
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
use WrapDBI;
use Exporter;
use Carp;

use vars qw( @ISA @EXPORT_OK );

@ISA = qw( Exporter );

@EXPORT_OK = qw(
                clone_from_project
                chromosome_from_project
                entry_name
                expand_project_name
                external_clone_name
                find_project_directories
                finished_accession
                fishData
                is_finished
                is_shotgun_complete
                library_and_vector
                localisation_data
                online_path_from_project
                project_from_clone
                project_finisher
                project_team_leader
                ref_from_query
                sanger_id_to_project
                species_from_project
                track_db
                unfinished_accession
                );

my( @active_statements );   # A list of open statements

=pod

=head2 is_finished( PROJECT )

Returns the current status (always TRUE) if the
project currently has one of the finished
statuses.

=cut

sub is_finished {
    my( $project ) = @_;
    
    my $ans = ref_from_query(qq(
        SELECT status
        FROM project_status
        WHERE projectname = '$project'
          AND status IN(20,21,22,23,27,28,29)
          AND iscurrent = 1
        ));
    
    return @$ans ? $ans->[0][0] : 0;
}

=pod

=head2 is_shotgun_complete

Returns TRUE if the project has ever had a status
of Shotgun_complete or Half_shotgun_complete.

=cut

sub is_shotgun_complete {
    my( $project ) = @_;

    my $ans = ref_from_query(qq(
        SELECT COUNT(*)
        FROM project_status 
        WHERE status IN(15,30)
        AND projectname = '$project'
        ));

    return $ans->[0][0];
}

=pod

=head2 library_and_vector( PROJECT )

Given the name of a PROJECT, returns the name of
the library and the name of the library vector
(plasmid).  Returns undef on failure.

=cut

sub library_and_vector {
    my( $project ) = @_;
    
    my $ans = ref_from_query(qq(                           
        SELECT l.libraryname
          , l.vectorname
        FROM clone_project cp
          , clone c
          , library l
        WHERE cp.clonename = c.clonename
          AND c.libraryname = l.libraryname
          AND cp.projectname = '$project'
        ));
    if (@$ans) {
        return(@{$ans->[0]});
    } else {
        return;
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
    my( $query ) = @_;

    my $dbh = track_db();

    my $sth = $dbh->prepare( $query );
    $sth->execute();
    return $sth->fetchall_arrayref();
}

=pod

=head2 track_db

Returns a B<DBI> handle to the Tracking database.

=cut


{
    my( $dbh );

    sub track_db {
        $dbh = WrapDBI->connect('reports', {RaiseError => 1}) unless $dbh;
        
        return $dbh;
    }

    END {
        # Close statements gracefully
        foreach my $s (@active_statements) {
            $s->finish if $s;
        }
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
    my( $name ) = @_;
    
    my $ans = ref_from_query(qq(
        SELECT clonename
        FROM clone_project
        WHERE projectname = '$name'
        ));
    
    if (@$ans == 1) {
        return $ans->[0][0];
    } else {
        return $name;
    }
}

=pod

=head2 clone_from_project

Returns the corresponding clone name for the
given project name if there is only one, or undef.

=cut

{
    my( $get_clone );

    sub clone_from_project {
        my( $project ) = @_;

        unless ($get_clone) {
            $get_clone = track_db()->prepare(q{
                SELECT clonename
                FROM clone_project
                WHERE projectname = ?
                });
            push(@active_statements, $get_clone);
        }   
        $get_clone->execute($project);
        
        if (my($clone) = $get_clone->fetchrow) {
            return $clone;
        } else {
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
    my( $clone ) = @_;
    
    my $ans = ref_from_query(qq(
        SELECT projectname
        FROM clone_project
        WHERE clonename = '$clone'
        ));
    
    if (@$ans == 1) {
        return $ans->[0][0];
    } else {
        return;
    }
}


=pod

=head2 HASH_REF = external_clone_name( LIST )

Given a list of project names, it returns a
reference to a hash, the keys of which are the
Sanger project names, and the values the
internationally approved convention for naming
clones.

If the list only contains one element, then the
single external clone name is returned; not a 
reference to a hash.

=cut

sub external_clone_name {
    my( @projects ) = @_;
    
    my $proj_list = join(',', map "'$_'", @projects) or return;
    
    my $ans = ref_from_query(qq(
        SELECT cp.projectname
          , c.clonename
          , l.internal_prefix
          , l.external_prefix
        FROM clone c
          , clone_project cp
          , library l
        WHERE l.libraryname = c.libraryname
          AND c.clonename = cp.clonename
          AND cp.projectname IN($proj_list)
        ));
        
    my %proj = map { $_->[0], [@{$_}[1,2,3]] } @$ans;
    
    # Fill in any clone names missing from %proj
    my @missing = grep ! $proj{$_}, @projects;
    if (@missing) {
        my $miss_list = join(',', map "'$_'", @missing);
        my $ans = ref_from_query(qq(
            SELECT projectname
              , clonename
            FROM clone_project
            WHERE projectname IN($miss_list)
            ));
        if (@$ans) {
            foreach (@$ans) {
                $proj{$_->[0]} = [$_->[1]];
            }
        }
    }
    
    foreach my $p (keys %proj) {
        my( $clone, $int, $ext ) = @{$proj{$p}};
        
        if ($int) {
            $clone =~ s/^$int// or confess "Can't remove '$int' from '$clone'";
        } else {
            $clone = uc $clone;
        }
        
        # Clones with unknown external extensions get "XX"
        $proj{$p} = $ext ? "$ext-$clone" : "XX-$clone";
    }
    
    return \%proj;
}

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
    my %dir = map {$_, undef} @name_list;
    my $projects = join(',', map "'$_'", @name_list);
    
    my $ans = ref_from_query(qq(
                                SELECT p.projectname
                                  , o.online_path
                                FROM project p
                                  , online_data o
                                WHERE p.id_online = o.id_online
                                  AND o.is_available = 1
                                  AND p.projectname IN($projects)
                                ));

    # Store results in %dir
    for (my $i = 0; $i < @$ans; $i++) {
        my( $name, $dir ) = @{$ans->[$i]};
        
        # Check that we don't get multiple online paths for one project
        if ($dir{$name}) {
            croak "Multiple directories for '$name' : ",
                map "  '$_->[1]'\n",
                grep $_->[0] eq $name, @$ans;
        } else {
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
    my( $project, $suffix ) = @_;
    
    my $query = qq( SELECT accession
                    FROM finished_submission
                    WHERE projectname = '$project'
                      AND suffix );
    if ($suffix) {
        $query .= qq( = '$suffix' );
    } else {
        $query .= qq( IS NULL );
    }

    my $ans = ref_from_query( $query );
    if (@$ans == 1) {
        return $ans->[0][0];
    } elsif (@$ans > 1) {
        die "Mulitple accessions found for '$project' and suffix '$suffix' : ",
            join(', ', map "'$_->[0]'", @$ans);
    } else {
        die "No accession found for projectname '$project' and suffix '$suffix'";
    }
}


=pod

=head2 entry_name( ACCESSION )

Returns the EMBL ID corresponding to the
ACCESSION supplied.

=cut

sub entry_name {
    my( $acc ) = @_;
    
    # Get the entryname for this accession

    my $ans = ref_from_query(qq( 
                                SELECT name
                                FROM embl_submission
                                WHERE accession = '$acc'
                                ));
    my( $entry_name );
    if (@$ans > 1) {
        die "Multiple names for accession '$acc' : ",
            join(', ', map "'$_->[0]'", @$ans);
    } elsif (@$ans == 0) {
        $entry_name = 'ENTRYNAME';
    } else {                 
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
    my( $project, $dummy_flag ) = @_;
    
    my $query = qq( 
                    SELECT accession
                    FROM unfinished_submission
                    WHERE projectname = '$project'
                    );

    my $ans = ref_from_query( $query );
    if (@$ans == 1) {
        return $ans->[0][0];
    } elsif (@$ans > 1) {
        die "Mulitple accessions found for '$project' : ",
            join(', ', map "'$_->[0]'", @$ans);
    } else {
        if ($dummy_flag) {
            return 'AL000000';
        } else {
            die "No accession found for projectname '$project'";
        }
    }
}

=pod

=head2 (CHR, MAP) = localisation_data( PROJECT )

Returns the chromosome and cytogenetic location
(if FISH has been done on the project) for
project named PROJECT.

=cut


sub localisation_data {
    my( $project ) = @_;
    
    return(chromosome_from_project($project), fishData($project));
}

# A lot of these subroutines should be written this way:
{
    my( $get_chr );

    sub chromosome_from_project {
        my( $project ) = @_;

        unless ($get_chr) {
            my $track_db = track_db();
            $get_chr = $track_db->prepare(q{
                SELECT cd.chromosome
                FROM chromosomedict cd
                  , clone c
                  , clone_project cp
                WHERE cd.id_dict = c.chromosome
                  AND c.clonename = cp.clonename
                  AND cp.projectname = ?
                });
            push(@active_statements, $get_chr);
        }
        $get_chr->execute($project);

        if (my($chr) = $get_chr->fetchrow) {
	    return $chr;
        } else {
            die "Chromosome unknown for project '$project'";
        }
    }
}

{
    my( $get_fish );
    
    # Get most recent fish result from tracking db
    sub fishData {
        my( $project ) = @_;

        unless ($get_fish) {
            my $track_db = track_db();
            $get_fish = $track_db->prepare(q{
                SELECT remark
                FROM project_status
                WHERE status = 9
                  AND projectname = ?
                ORDER BY statusdate DESC
                });
            push(@active_statements, $get_fish);
        }
        $get_fish->execute($project);
        
        my( $map );
        if (my($remark) = $get_fish->fetchrow) {
            $map = fishParse( $remark )
                or warn "Can't parse fish tag ('$remark')\n";
        }

        if ($map) {
            return $map;
        } else {
            return;
        }
    }
}


sub fishParse {
    my ($fishLine) = @_;
    $fishLine =~ s/\s+$//; # Remove trailing space
    $fishLine =~ s/\//-/g; # Replace slashes with dashes
    my (@catch);
    if (@catch = $fishLine =~
	/^[0-9XY]{0,2}([pq])(\d*\.?\d+)\s*(-)\s*[0-9XY]{0,2}[pq](\d*\.?\d+)$/) {
    } elsif (@catch = $fishLine =~
	     /^[0-9XY]{0,2}([pq])(\d*\.?\d+)\s*(-)\s*[pq]{0,1}(\d*\.?\d+)$/) {
    } elsif (@catch = $fishLine =~
	     /^[0-9XY]{0,2}([pq])(\d*\.?\d+)$/) {
    } else {
	return;
    }
    return join '', @catch;
}

{
    my( $get_species );
    
    sub species_from_project {
        my( $project ) = @_;
        
        unless ($get_species) {
            my $track_db = track_db();
            $get_species = $track_db->prepare(q{
                SELECT c.speciesname
                FROM clone c
                  , clone_project cp
                 WHERE c.clonename = cp.clonename
                  AND cp.projectname = ?
                });
            push(@active_statements, $get_species);
        }
        $get_species->execute($project);
        
        if (my($species) = $get_species->fetchrow) {
            return $species;
        } else {
            return;
        }
    }
}

{
    my( $get_online_path );
    
    sub online_path_from_project {
        my( $project ) = @_;
        
        unless ($get_online_path) {
            $get_online_path = track_db()->prepare(q{
            SELECT o.online_path
            FROM project p
              , online_data o
            WHERE p.id_online = o.id_online
              AND o.is_available = 1
              AND p.projectname = ?
            });
            push(@active_statements, $get_online_path);
        }
        $get_online_path->execute($project);
        
        if (my($path) = $get_online_path->fetchrow) {
            return $path;
        } else {
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
    my( $get_finisher );

    sub project_finisher {
        my( $project ) = @_;

        unless ($get_finisher) {
            my $track_db = track_db();
            $get_finisher = $track_db->prepare(q{
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
                });
            push(@active_statements, $get_finisher);
        }
        $get_finisher->execute($project);

        if (my( $forename, $surname ) = $get_finisher->fetchrow) {
            # Abbreviate forename
            $forename =~ s/^(.).+/$1\./ or return;
            return( "$surname $forename" );
        } else {
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
    my( $get_team_leader );

    sub project_team_leader {
        my( $project ) = @_;

        unless ($get_team_leader) {
            my $track_db = track_db();
            $get_team_leader = $track_db->prepare(q{
                SELECT p.forename
                  , p.surname
                FROM project_owner o
                  , team t
                  , person p
                WHERE o.teamname = t.teamname
                  AND t.teamleader = p.id_person
                  AND o.projectname = ?
                ORDER BY o.owned_from DESC
                });
            push(@active_statements, $get_team_leader);
        }
        $get_team_leader->execute($project);

        if (my( $forename, $surname ) = $get_team_leader->fetchrow) {
            # Abbreviate forename
            $forename =~ s/^(.).+/$1\./ or return;
            return( "$surname $forename" );
        } else {
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
    my( $get_project_name );

    sub sanger_id_to_project {
        my( $sid ) = @_;

        my( $PROJ, $suffix ) = $sid =~ /^_(.+?)(?:__([A-Z]))?$/;

        unless ($get_project_name) {
            $get_project_name = track_db()->prepare(q{
                SELECT projectname
                FROM project
                WHERE UPPER(projectname) = ?
                });
            push(@active_statements, $get_project_name);
        }
        $get_project_name->execute($PROJ);
        
        my $ans = $get_project_name->fetchall_arrayref;
        
        my( $proj );
        if (@$ans) {
            if (@$ans > 1) {
                die "Ambiguous matches to '$sid' ('$PROJ') : ", join(', ', map "'$_->[0]'", @$ans), "\n";
            }
            $proj = $ans->[0][0];
        } else {
            die "Can't get project name for '$sid' ('$PROJ')";
        }
        
        return($proj, $suffix);
    }
}


1;

__END__

=back

=head2 Author

James Gilbert email B<jgrg@sanger.ac.uk>
