
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

@EXPORT_OK = qw( expand_project_name ref_from_query
                 find_project_directories );

=pod

=head2 expand_project_name( NAME )

Many projects names are a truncated version of
the name of the clone in the project.  We prefer
to have the full project name in humace, and this
routine returns the name of the clone if it is
the only clone linked to the project B<NAME>, or
just returns B<NAME> if it isn't.

=cut


#'

sub expand_project_name {
    my( $name ) = @_;
    
    my $ans = ref_from_query(qq(
                                 select c.clonename
                                 from clone c, clone_project cp,
                                     project p
                                 where
                                     c.clonename = cp.clonename and
                                     cp.projectname = p.projectname and
                                     p.projectname = '$name'
                                ));
    my @clone = map $_->[0], @$ans;
    
    if (@clone == 1) {
        return $clone[0];
    } else {
        return $name;
    }
}

=pod

=head2 find_project_directories( LIST_OF_PROJECT_NAMES )

Returns ref to a hash, with keys the project
names, and values the path to the project, or
undef if the path couldn't be found. 
B<find_project_directories>  croaks if it finds
more than one online path for any of the
projects.

=cut

#'

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

=head2 ref_from_query( SQL )

Returns a reference to an array of anonymous
arrays containing the results from running the
B<SQL> query on the I<Tracking> database.

=cut

{
    my( $dbh );

    sub ref_from_query {
        my( $query ) = @_;
        my( $sth, @answer );

        $dbh = WrapDBI->connect('reports', {RaiseError => 1}) unless $dbh;

        $sth = $dbh->prepare( $query );
        $sth->execute();
        return $sth->fetchall_arrayref();
    }

    END {
        $dbh->disconnect() if $dbh;
    }
}


1;

__END__

=back

=head2 Author

James Gilbert email B<jgrg@sanger.ac.uk>
