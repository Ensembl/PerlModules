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

my $cp  = prepare_track_statement(qq{
			SELECT projectname
            FROM clone_project
            WHERE clonename = ?
          });

my $p_status = prepare_track_statement(qq{
					SELECT psd.description, ps.statusdate
                    FROM project_status ps, projectstatusdict psd
                    WHERE ps.projectname = ?
                    AND ps.status=psd.id_dict
                    AND ps.iscurrent = 1
               });

sub fetch_projectname_from_clonename {
  my ($clonename) = @_;
  $cp->execute($clonename);

  return $cp->fetchrow;
}

sub fetch_project_status {
  my ($projectname) = @_;
  $p_status->execute($projectname);

  return  my($status, $statusdate) = $p_status->fetchrow;
}


1;

