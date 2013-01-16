
package Hum::Conf;

use strict;
use warnings;
use Carp;

use vars qw( %humConf );


sub _init {

    my $humpub = '/warehouse/cbi4_wh01/work1/humpub'; # TRANSIENT WAREHOUSE = slow, needs to be relocated

    my $humpub_scratch = '/lustre/scratch109/sanger/humpub'; # SCRATCH = not backed up
    
    # The \057 business is to stop webpublish choking on this file
    my $embl_seq = "\057nfs/embl_seq";

    # The Plan: build config from static strings, such as could be
    # loaded from a text file.  Make any substitutions or overrides
    # _after_ that.  Then put the result in %humConf.
    #
    # TODO: post-load substitutions like s{\$FOO}{$humConf{FOO}}, to make the lexicals above unnecessary
    # TODO: make it all Readonly - could break stuff?
    #
    # Eventual aim is for this module to be static, and for the actual
    # config changes to be made in a YAML file.

    # Hash containing config info
    my %cfg =
   (

    # FTP site variables
    FTP_GHOST           => "$embl_seq/ftp_ghost",
    FTP_ATTIC           => "$embl_seq/ftp_ghost/attic",
    FTP_ROOT            => "\057nfs/disk69/ftp/pub/sequences",

    # May be overridden by %ENV
    PFETCH_SERVER_LIST  => [
        [qw{ pfetch.sanger.ac.uk 22400 }], # zeus front end load balancer(s), by name
                           ],

    WAREHOUSE_MYSQL => '/warehouse/humpub_wh01/mysql_backup',

    # The humpub disks
    HUMPUB_ROOT   => $humpub,

    HUMPUB_BLAST  => "$humpub_scratch/data/blast",
    HUMPUB_CHROMOVIEW  => "$humpub_scratch/data/chromoview/",

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
    GRIT_SOFTWARE => '/software/grit/bin/',

    CHROMODB_CONNECTION => {
        PORT => 3323,
        HOST => 'lutra7',
        NAME => 'chromoDB',
        RO_USER => 'ottro',
        RW_USER => 'ottadmin',
        RW_PASS => 'lutralutra',
    },

    SUBMISSIONS_CONNECTION => {
        PORT => 3324,
        HOST => 'otterlive',
        NAME => 'submissions',
        RO_USER => 'ottro',
        RW_USER => 'ottadmin',
        RW_PASS => 'lutralutra',
    },

    LOUTRE_CONNECTION => {
        PORT => 3324,
        HOST => 'otterlive',
        RO_USER => 'ottro',
    },

   );

    if ($ENV{'PFETCH_SERVER_LIST'}) {
        $cfg{PFETCH_SERVER_LIST} = parse_servers($ENV{'PFETCH_SERVER_LIST'});
    }

    %humConf = %cfg;
    return 1;
}

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

_init();
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

