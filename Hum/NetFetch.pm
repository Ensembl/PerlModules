
package Hum::NetFetch;

use strict;
use warnings;
use Carp;
use Exporter;
use vars qw( @EXPORT_OK @ISA );
use LWP::UserAgent;

use Hum::Conf qw( HUMPUB_ROOT );
use Hum::Lock;
use Hum::EMBL;

@ISA = qw( Exporter );
@EXPORT_OK = qw( wwwfetch wwwfetch_EMBL_object );

my $embl_simple_url = 'http://www.ebi.ac.uk/cgi-bin/dbfetch?db=emblsva&format=default&style=raw&id=';

sub wwwfetch {
    my( $ac ) = @_;
    my $get = "$embl_simple_url$ac";
    warn "get=$get\n";

    my $ua = LWP::UserAgent->new;
    $ua->env_proxy;
    #$ua->proxy(http  => 'http://webcache.sanger.ac.uk:3128');
    my $req = HTTP::Request->new(GET => $get);        
    my $embl =  $ua->request($req)->content;

    unless (defined $embl) {
        die "No response from '$get'";
    }
    elsif (substr($embl, 0, 5) ne 'ID   ') {
        die "Entry for '$ac' not found by request '$get'"
    } else {
        return $embl;
    }
}

sub wwwfetch_EMBL_object {
    my ($acc) = @_;
    
    my $txt;
    eval {
        $txt = wwwfetch($acc);
    };
    if ($@) {
        warn $@;
        return;
    }
    else {
        my $parser = Hum::EMBL->new;
        my $embl = $parser->parse(\$txt)  
            or confess "nothing returned from parsing '$txt'";
        return $embl;        
    }
}

1;

__END__

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>

