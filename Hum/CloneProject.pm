package Hum::CloneProject;

# author: jgrg@sanger.ac.uk

use strict;
use warnings;
use Hum::Tracking qw{prepare_track_statement};
use Exporter;

use vars qw( @ISA @EXPORT_OK );
@ISA = qw( Exporter );
@EXPORT_OK = qw(fetch_projectname_from_clonename
                fetch_project_status);

my ($cp, $p_status);

sub _cp {
    return $cp ||= prepare_track_statement(qq{
			SELECT projectname
            FROM clone_project
            WHERE clonename = ?
          });
}

sub _p_status {
    return $p_status ||= prepare_track_statement(qq{
					SELECT psd.description, ps.statusdate
                    FROM project_status ps, projectstatusdict psd
                    WHERE ps.projectname = ?
                    AND ps.status=psd.id_dict
                    AND ps.iscurrent = 1
               });
}

sub fetch_projectname_from_clonename {
  my ($clonename) = @_;
  my $sth = _cp();
  $sth->execute($clonename);

  return $sth->fetchrow;
}

sub fetch_project_status {
  my ($projectname) = @_;
  die "Requires list context" unless wantarray;

  my $sth = _p_status();
  $sth->execute($projectname);

  return  my($status, $statusdate) = $sth->fetchrow;
}


1;

__END__

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>
