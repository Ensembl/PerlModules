
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
                library_and_vector
                ref_from_query
                expand_project_name
                clone_from_project
                project_from_clone
                find_project_directories
                entry_name
                finished_accession
                unfinished_accession
                localisation_data
                external_clone_name
                project_finisher
                project_team_leader
                );


sub library_and_vector {
    my( $project ) = @_;
    
    my $ans = ref_from_query(qq(
                                select l.libraryname, l.vectorname
                                from clone_project cp, clone c, library l
                                where
                                    cp.clonename = c.clonename and
                                    c.libraryname = l.libraryname and
                                    cp.projectname = '$project' ));
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

{
    my( $dbh );

    sub ref_from_query {
        my( $query ) = @_;

        $dbh = WrapDBI->connect('reports', {RaiseError => 1}) unless $dbh;

        my $sth = $dbh->prepare( $query );
        $sth->execute();
        return $sth->fetchall_arrayref();
    }

    END {
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
                                 select clonename
                                 from clone_project
                                 where projectname = '$name'
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

sub clone_from_project {
    my( $proj ) = @_;
    
    my $ans = ref_from_query(qq(
                                 select clonename
                                 from clone_project
                                 where projectname = '$proj'
                                ));
    
    if (@$ans == 1) {
        return $ans->[0][0];
    } else {
        return;
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
                                 select projectname
                                 from clone_project
                                 where clonename = '$clone'
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
                                 select p.projectname, c.clonename,
                                     l.internal_prefix, l.external_prefix
                                 from clone c, clone_project cp,
                                     project p, library l
                                 where
                                     l.libraryname = c.libraryname and
                                     c.clonename = cp.clonename and
                                     cp.projectname = p.projectname and
                                     p.projectname in($proj_list)
                                ));
        
    my %proj = map { $_->[0], [@{$_}[1,2,3]] } @$ans;
    
    # Fill in any clone names missing from %proj
    my @missing = grep ! $proj{$_}, @projects;
    if (@missing) {
        my $miss_list = join(',', map "'$_'", @missing);
        my $ans = ref_from_query(qq(
                                     select projectname, clonename
                                     from clone_project
                                     where projectname in($miss_list)  ));
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
                                 select p.projectname, o.online_path
                                 from project p, online_data o
                                 where
                                     p.id_online = o.id_online and
                                     o.is_available = 1 and
                                     p.projectname in ($projects)
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
    
    my $query = qq( select accession
                    from finished_submission
                    where projectname = '$project' 
                      and suffix );
    if ($suffix) {
        $query .= qq( = '$suffix' );
    } else {
        $query .= qq( is null );
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

    my $ans = ref_from_query(qq( select name
                                 from embl_submission
                                 where accession = '$acc' ));
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
    
    my $query = qq( select accession
                    from unfinished_submission
                    where projectname = '$project' );

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
    
    # Get the chromosome from the tracking db
    my( $chr );
    {
        my $ans = ref_from_query(qq(
                                    select cd.chromosome
                                    from chromosomedict cd,
                                        clone c, clone_project cp
                                    where cd.id_dict = c.chromosome
                                        and c.clonename = cp.clonename
                                        and cp.projectname = '$project' ));
        if (@$ans) {
	    $chr = $ans->[0][0];
	} else {
            die "Chromosome unknown for project '$project'";
        }
    }

    # Get most recent fish result from tracking db
    my( $fish, $map );
    {
        my $ans = ref_from_query(qq(
                                    select remark
                                    from project_status
                                    where status = 9
                                    and projectname = '$project'
                                    order by statusdate desc ));
        eval{ $fish = $ans->[0][0] };
        if ($fish) {
            $map = fishParse( $fish )
		or warn "Can't parse fish tag [ $fish ]\n";
	} else {
            warn "No fish data for project '$project'\n";
        }
    }

    return( $chr, $map );
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

=pod

=head2 project_finisher( PROJECT );

Returns the finisher for a project in EMBL author
format (eg: "J. Smith").

=cut


sub project_finisher {
    my( $project ) = @_;

    my $query = qq(
                   select p.forename, p.surname
                   from project_role pr, team_person_role tpr, person p
                   where pr.id_role = tpr.id_role and
                         tpr.id_person = p.id_person and
                         pr.projectname = '$project' and
                         tpr.roletype = 'Finishing'
                   order by pr.assigned_from desc
                   );
    my $ans = ref_from_query( $query );
    
    my( $forename, $surname );
    if (@$ans) {
        ( $forename, $surname ) = @{$ans->[0]};
    } else {
        die "No finisher for project '$project'";
    }
    
    # Abbreviate forename
    $forename =~ s/^(.).+/$1\./ or return;
    return( "$surname $forename" );
}


=pod

=head2 project_team_leader( PROJECT );

Returns the team leader for a project in EMBL author
format (eg: "J. Smith").

=cut


sub project_team_leader {
    my( $project ) = @_;

    my $query = qq(
                   select p.forename, p.surname
                   from project_owner o, team t, person p
                   where o.teamname = t.teamname and
                         t.teamleader = p.id_person and
                         o.projectname = '$project'
                   order by o.owned_from desc
                   );
    my $ans = ref_from_query( $query );
    
    my( $forename, $surname );
    if (@$ans) {
        ( $forename, $surname ) = @{$ans->[0]};
    } else {
        die "No team leader for project '$project'";
    }
    
    # Abbreviate forename
    $forename =~ s/^(.).+/$1\./ or return;
    return( "$surname $forename" );
}



1;

__END__

=back

=head2 Author

James Gilbert email B<jgrg@sanger.ac.uk>
