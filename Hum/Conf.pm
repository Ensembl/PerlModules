
package Hum::Conf;

use strict;
use vars qw( %humConf );

# Could change user in future
# _home alternates are to avoid warnings outside the sanger
my $humpub = ( getpwnam('humpub') )[7] || 'humpub_home';
my $badger = ( getpwnam('badger') )[7] || 'badger_home';
my $ftp    = ( getpwnam('ftp')    )[7] || 'ftp_home';
my $humace = ( getpwnam('humace') )[7] || 'humace_home';

# List of acedb servers and ports
my %ace_server = (
    'humace'            => [qw( humsrv1   210000 )],
    'humace-live-ro'    => [qw( humsrv1   310000 )],
    'humace-query'      => [qw( humsrv1   410000 )],
    '1ace'              => [qw( socrates  100201 )],
    '6ace'              => [qw( socrates  100206 )],
    '9ace'              => [qw( socrates  100209 )],
    '10ace'             => [qw( socrates  100210 )],
    '11ace'             => [qw( socrates  100211 )],
    '13ace'             => [qw( socrates  100213 )],
    '20ace'             => [qw( socrates  100220 )],
    '22ace'             => [qw( socrates  100222 )],
    'Xace'              => [qw( socrates  100224 )],
    );

my %chr_path = map { $_, "$humace/databases/$_" } qw( 1ace 6ace 9ace 10ace 11ace 13ace 20ace 22ace Xace );

my %ace_host = map { $_, $ace_server{$_}->[0] } keys %ace_server;
my %ace_port = map { $_, $ace_server{$_}->[1] } keys %ace_server;

my $humpub_disk1  = "${humpub}1" ;
my $humpub_disk1a = "${humpub}1a";
my $humpub_disk2  = "${humpub}2" ;
my $humpub_disk2a = "${humpub}2a";
my $humpub_disk3  = "${humpub}3" ;
my $humpub_disk3a = "${humpub}3a";
my $humpub_disk4a = "${humpub}4a";
my $humpub_disk5a = "${humpub}5a";
my $ftp_ghost     = "$humpub_disk3/data/ftp_ghost";

# TimDB legacy system
my $sanger_path="/nfs/disk100/humpub1a/unfinished_ana";
my $ext_path="/nfs/disk100/humpub2a/unfinished_ana";
my %cgp_path=map {$_,"$sanger_path/$_"} qw ( SU SF );
$cgp_path{'EU'}="$ext_path/EU";
$cgp_path{'EF'}="$ext_path/EF";

my $ftp_structure = {
    #'Arabidopsis'   => [ 'arabidopsis'              ],
    #'Drosophila'    => [ 'drosophila/sequences'     ],
    'B.floridae'    => [ 'b_floridae'               ],
    'Carp'          => [ 'carp'                     ],
    'Chicken'       => [ 'chicken'                  ],
    'Chimp'         => [ 'chimp'                    ],
    'Dog'           => [ 'dog'                      ],
    'Fugu'          => [ 'fugu'                     ],
    'Gibbon'        => [ 'gibbon'                   ],
    'Gorilla'       => [ 'gorilla'                  ],
    'Human'         => [ 'human',            'Chr_' ],
    'Mouse'         => [ 'mouse',            'Chr_' ],
    'Pig'           => [ 'pig'                      ],
    'Platypus'      => [ 'platypus'                 ],
    'Rhesus'        => [ 'rhesus'                   ],
    'Sminthopsis'   => [ 'sminthopsis'              ],
    'Tetraodon'     => [ 'tetraodon'                ],
    'Zebrafish'     => [ 'zebrafish'                ],
    'M.truncatula'  => [ 'm_truncatula'             ],
    'Wallaby'       => [ 'wallaby'                  ],
    'Opossum'       => [ 'opossum'                  ],
    };

my $humace_queue = "$humpub/humace/queue";

# Hash containing config info
%humConf = (
    ACESERVER_HOST  => \%ace_host,
    ACESERVER_PORT  => \%ace_port,
    CHR_DB_PATH     => \%chr_path,

    # FTP site variables
    HUMAN_SEQ_FTP_DIR   => "$ftp/pub/sequences/human",
    FTP_GHOST           =>  $ftp_ghost,
    FTP_ATTIC           => "$ftp_ghost/attic",
    FTP_ROOT            => "$ftp/pub/sequences",
    FTP_STRUCTURE       =>  $ftp_structure,
    SPECIES_LIST =>  [keys %$ftp_structure],

    PFETCH_SERVER_LIST => [
        [qw{ cbi2.internal.sanger.ac.uk      22100 }],
        [qw{ pubseq.internal.sanger.ac.uk    22100 }],
        ],

    PFETCH_ARCHIVE_SERVER_LIST => [
        [qw{ cbi2.internal.sanger.ac.uk      23100 }],
        [qw{ pubseq.internal.sanger.ac.uk    23100 }],
        ],

    HUMACE_DIR    => "/nfs/humace/humpub/humace",
    HUMACE_RO_DIR => '/nfs/humace/humpub/humace-live-ro',

    # The humpub disks
    HUMPUB_ROOT   => $humpub       ,
    HUMPUB_DISK1  => $humpub_disk1 ,
    HUMPUB_DISK1A => $humpub_disk1a,
    HUMPUB_DISK2  => $humpub_disk2 ,
    HUMPUB_DISK2A => $humpub_disk2a,
    HUMPUB_DISK3  => $humpub_disk3 ,
    HUMPUB_DISK3A => $humpub_disk3a,
    HUMPUB_DISK4A => $humpub_disk4a,
    HUMPUB_DISK5A => $humpub_disk5a,

    HUMPUB_BLAST  => "$humpub_disk3/data/blast",

    PUBLIC_HUMAN_DISK => '/nfs/repository/p100',
    HUMACE_DUMP   => '/nfs/humace/humpub/backup',
    HUMACE_QUEUE => $humace_queue,
    HUMACESERVER_HOST     => $ace_host{'humace'},
    HUMACESERVER_PORT     => $ace_port{'humace'},
    HUMGIFACESERVER_PORT  => $ace_port{'humace-live-ro'},
    HUMQUERYSERVER_PORT   => $ace_port{'humace-query'},
    HUMACE_CLIENT_TIMEOUT => 1200,
    HUMACE_INCREMENTAL     => "$humpub/data/Humace_Incremental/CURRENT",
    HUMACE_INCREMENTAL_DIR => "$humpub/data/Humace_Incremental",
    
    SPECIES_ANALYSIS_ROOT => {
        'Human'         => "$humpub/analysis/projects",
        'Mouse'         => "$humpub_disk1/analysis/mouse",
        'Zebrafish'     => "$humpub_disk1/analysis/zebrafish",
        'Gibbon'        => "$humpub_disk1/analysis/gibbon",
        },
    SPECIES_ACE_QUEUE => {
        'Human'         => $humace_queue,
        'Mouse'         => "/nfs/humace/humpub/musace/queue",
        'Zebrafish'     => "/nfs/humace/humpub/zface/queue",
        'Gibbon'        => "/nfs/humace/humpub/gibbace/queue",
        },
    ANALYSIS_ROOT => "$humpub/analysis/projects",
    LINK_ANALYSIS_ROOT => "$humpub/analysis/links",
    
    EMBL_FILE_DIR => "$humpub/data/EMBL",
    EMBL_SUMMARY_EMAIL => "$humpub/data/EMBL_summary_email",
    CONFIG_DEFAULT => "$humpub/scripts/haceprep.cfg",
    BADGER_ROOT => $badger,
    PACE_DIR   => "$badger/pace",
    PACE_QUEUE => "$badger/pace/queue",
    FGENESH_DIR => "$humpub/solovyev/fgenesh_run",
    GF_DATA     => "$humpub/solovyev/fgenes_run",
    DBM_FILES   =>  "$humpub/data/DBMfiles",
    IMAGES      =>  "$humpub/data/images",
    ANALYSIS_PEOPLE => [ qw( humpub th michele jgrg ak1 lw2 jla1 cas eah ) ],
    HP_TRANSACTION => "$humpub/data/hp_transaction",
    HP_TRANSACTION_LOG => "$humpub/logs/hp_transaction.log",
    DELETE_DUMP_DIR => "$humpub/data/deleted",
    WWW_CHECKING => "/nfs/intweb/server/htdocs/LocalUsers/humpub/autostatus/checking",
    WWW_SPANGLE => "/nfs/intweb/server/htdocs/LocalUsers/humpub/annotation/evidence",
    UNFIN_DATA_ROOT => $sanger_path,
    UNFIN_DATA_ROOT_CGP => \%cgp_path,
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

