
package Hum::Env;

=pod

=head1 NAME Hum::Env

=head1 DESCRIPTION

B<Hum::Env> is used to provide a controlled
environment for scripts in the human analysis
system.  It is used in cron jobs and CGI scripts
to ensure that B<PERL5LIB> and B<PATH>
environment variables, etc... are set up
correctly.

=head1 SYNOPSIS

    use Hum::Env;

Remember that you need to "use lib <path>", where
B<path> contains Hum::Env.

=head2 Author

James Gilbert email B<jgrg@sanger.ac.uk>

=cut

use strict;

my (@libs, @path);

# Set up @INC
BEGIN {
    @libs = qw(
	       /nfs/disk100/humpub/modules/PerlModules
               /nfs/disk100/humpub/modules/bioperl-0.6
	       /nfs/disk100/humpub/modules
	       /usr/local/badger/bin
	       );
}
use lib @libs;

# HOME environment variable (and LOGDIR)
$ENV{HOME} = (getpwuid($<))[7];
$ENV{LOGDIR} = $ENV{HOME};

# Ensure @INC gets propagated in system calls
$ENV{PERL5LIB} = join ':', @libs;

my $staden_home = '/usr/local/badger/staden';

# For Staden programs
if ($^O eq 'dec_osf') {
    $ENV{LD_LIBRARY_PATH} = "$ENV{LD_LIBRARY_PATH}:$staden_home/lib/alpha-binaries";
}

# List of dirs for PATH
@path = (qw(
	    /nfs/disk100/humpub/OSFbin
	    /nfs/disk100/humpub/scripts
	    /usr/local/pubseq/scripts
	    /usr/local/badger/bin
	    /usr/local/pubseq/bin
	    /nfs/disk100/pubseq/compugen/OSF/exe
	    /usr/local/oracle/bin
	    /usr/local/lsf/bin
	    /usr/local/bin
	    /bin
	    /usr/sbin
	    /usr/bin
	    /usr/bin/X11
	    /usr/etc
	    /usr/bsd
	    ), "$staden_home/bin");

# Set PATH environment
$ENV{PATH} = join ':', @path;

# For scripts which access oracle
$ENV{ORACLE_HOME} = '/usr/local/oracle';
$ENV{TWO_TASK}    = 'sids';

# For blast
$ENV{BLASTDB}       = '/nfs/disk100/humpub/blast';
$ENV{BLASTFILTER}   = '/usr/local/pubseq/bin';
$ENV{BLASTMAT}      = '/nfs/disk100/pubseq/blastdb';
$ENV{NCBI}          = '/nfs/disk100/pubseq/blastdb';

# For halfwise
$ENV{WISECONFIGDIR} = '/nfs/disk100/pubseq/wise/wisecfg';

1;

__END__
