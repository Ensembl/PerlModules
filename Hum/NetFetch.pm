
package Hum::NetFetch;

use strict;
use Exporter;
use vars qw( @EXPORT_OK @ISA );
use LWP::Simple qw( get );
use Hum::Conf qw( HUMPUB_ROOT );
use Hum::Lock;

@ISA = qw( Exporter );
@EXPORT_OK = qw( wwwfetch );

# email address of EBI email sequence server
my $NetServ = 'netserv\@ebi.ac.uk';

# procmail is set up to put the body of netserv
# messages in to this directory.  Messages get
# named "msg.<UNIQUE KEY>".
my $EMBL_emails_dir = "$HUMPUB_ROOT/data/EMBL_netserv_email";

BEGIN {
    my $embl_simple_url = 'http://www.ebi.ac.uk/cgi-bin/emblfetch?style=raw&format=embl&id=';
    
    sub wwwfetch {
        my( $ac ) = @_;
        my $get = "$embl_simple_url$ac";
        my $embl = get($get);
        unless (defined $embl) {
            die "No response from '$get'";
        }
        elsif (! $embl) {
            die "Entry for '$ac' not found by request '$get'"
        } else {
            return $embl;
        }
    }
}


1;

__END__
