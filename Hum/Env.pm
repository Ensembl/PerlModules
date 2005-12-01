
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

You need to put this line B<BEFORE> you "use" any
other modules.

Remember that you need to "use lib <path>", where
B<path> contains Hum::Env.

=head2 Author

James Gilbert email B<jgrg@sanger.ac.uk>

=cut

use strict;
use Carp;

my (@libs, @path);

# Set up @INC
BEGIN {
    @libs = qw(
        /nfs/disk100/humpub/otter/ensembl-otter/modules
        /nfs/disk100/humpub/modules/ensembl/modules
        /nfs/disk100/humpub/modules/bioperl
        /nfs/disk100/humpub/modules/PerlModules
        /nfs/disk100/humpub/scripts/tk
        /nfs/disk100/humpub/modules
        /usr/local/badger/bin
        /usr/local/badger/staden/alpha-bin
        );
}
use lib @libs;

# HOME environment variable (and LOGDIR)
$ENV{HOME} = (getpwuid($<))[7];
$ENV{LOGDIR} = $ENV{HOME};

# Ensure @INC gets propagated in system calls
$ENV{PERL5LIB} = join ':', @libs;

my $staden_home = '/usr/local/badger/staden';
$ENV{'STADENROOT'} =  $staden_home;
$ENV{'STADTABL'}   = "$staden_home/tables";
$ENV{'TAGDB'}      = "$staden_home/tables/TAGDB";

# For Staden programs
{
    my $staden_lib = "$staden_home/lib/alpha-binaries";
    if ($^O) {
        if ($^O eq 'dec_osf') {
            $ENV{LD_LIBRARY_PATH} = $ENV{LD_LIBRARY_PATH}
                ? "$ENV{LD_LIBRARY_PATH}:$staden_lib"
                : $staden_lib;
        }
    } else {
        warn "Perl operating system variable (\$^O) not set";
    }
}

# List of dirs for PATH
@path = (qw(
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

if ($^O eq 'dec_osf') {
    unshift(@path, '/nfs/disk100/humpub/OSFbin');
}
elsif ($^O eq 'linux') {
    unshift(@path, '/nfs/disk100/humpub/LINUXbin');
}
else {
    confess "Unknown operating system '$^O'";
}

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

# For mkcon-gap (and therefore hcon)
$ENV{TAGDB}         = '/usr/local/badger/staden/tables/TAGDB';

# Spangle stuff
$ENV{SPANGLECGI} = "http://intweb.sanger.ac.uk/cgi-bin/users/jgrg/spangle5.cgi";
$ENV{SPANGLE}    = "/nfs/disk100/humpub/modules/PerlModules/Spangle/bin/spantest";


1;

__END__
