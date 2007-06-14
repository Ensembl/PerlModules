
package Hum::Conf;

use strict;
use Carp;

use vars qw( %humConf );

# Could change user in future
my $humpub = '/lustre/cbi4/work1/humpub';

my $ftp_ghost = "$humpub/ftp_ghost";

my $pfetch_server_list;
if ($ENV{'PFETCH_SERVER_LIST'}) {
    $pfetch_server_list = parse_servers($ENV{'PFETCH_SERVER_LIST'});
} else {
    $pfetch_server_list = [
        [qw{ cbi3.internal.sanger.ac.uk      22400 }],
        ];
}

# Hash containing config info
%humConf = (

    # FTP site variables
    FTP_GHOST           =>  $ftp_ghost,
    FTP_ATTIC           => "$ftp_ghost/attic",
    FTP_ROOT            => "/nfs/disk69/ftp/pub/sequences",

    PFETCH_SERVER_LIST         => $pfetch_server_list,

    # The humpub disks
    HUMPUB_ROOT   => $humpub,

    HUMPUB_BLAST  => "$humpub/data/blast",

    PUBLIC_HUMAN_DISK => '/nfs/repository/p100',

    SPECIES_ANALYSIS_ROOT => {
        'Human'         => "$humpub/analysis/projects",
        'Mouse'         => "$humpub/analysis/mouse",
        'Zebrafish'     => "$humpub/analysis/zebrafish",
        'Gibbon'        => "$humpub/analysis/gibbon",
        },
    # hardly used	
    ANALYSIS_ROOT => "$humpub/analysis/projects",
    

    EMBL_FILE_DIR => "$humpub/data/EMBL",
    CONFIG_DEFAULT => "$humpub/scripts/haceprep.cfg",
    );

sub import {
    my ($callpack) = caller(0); # Name of the calling package
    my $pack = shift; # Need to move package off @_

    # Get list of variables supplied, or else
    # all of Hum::Conf:
    my @vars = @_ ? @_ : keys( %humConf );
    return unless @vars;

    # Predeclare global variables in calling package
    eval "package $callpack; use vars qw("
         . join(' ', map { '$'.$_ } @vars) . ")";
    die $@ if $@;


    foreach (@vars) {
	if ( defined $humConf{ $_ } ) {
            no strict 'refs';
	    # Exporter does a similar job to the following
	    # statement, but for function names, not
	    # scalar variables:
	    *{"${callpack}::$_"} = \$humConf{ $_ };
	} else {
	    die "Error: Hum::Conf : $_ not known\n";
	}
    }
}

sub parse_servers {
    my ($str) = @_;
    
    my $list = [];
    foreach my $serv_port (split /[\s,]+/, $str) {
        my ($server, $port) = $serv_port =~ /^([\w\.\-]+):(\d+)$/
            or confess "Can't parser server:port from '$serv_port' from '$str'";
        push @$list, [$server, $port];
    }
    
    unless (@$list) {
        confess "Failed to parse any server:port information from '$str'";
    }
    
    return $list;
}

1;


__END__

=head1 NAME

Hum::Conf - imports global variables used by human sequence analysis

=head1 SYNOPSIS

    use Hum::Conf;
    use Hum::Conf qw( HUMACESERVER_HOST HUMACESERVER_PORT );

=head1 DESCRIPTION

Hum::Conf is based upon ideas from the standard
perl Env environment module.

It imports and sets a number of standard global
variables into the calling package, which are
used in many scripts in the human sequence
analysis system.  The variables are first
decalared using "use vars", so that it can be
used when "use strict" is in use in the calling
script.  Without arguments all the standard
variables are set, and with a list, only those
variables whose names are provided are set.  The
module will die if a variable which doesn't
appear in its C<%Hum::Conf> hash is asked to be
set.

The variables can also be references to arrays or
hashes.

Edit C<%Hum::Conf> to add or alter variables.

All the variables are in capitals, so that they
resemble environment variables.

=head1 SEE ALSO

L<listHumConf> - a script which prints a nicely
fomatted list of the variables known to
Hum::Conf.

=head1 AUTHOR

B<James Gilbert> email jgrg@sanger.ac.uk

