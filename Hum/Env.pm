
=pod

=head1 NAME Hum::Env

=head1 DESCRIPTION

B<Hum::Env> sets up the human analysis
environment for a script.  It is used in cron
jobs and CGI scripts to ensure that B<PERL5LIB>
and B<PATH> environment variables, etc... are set
up correctly.

=cut

package Hum::Env;

use strict;

my (@path, $script, $fullScript);

# Location of PERL5LIB's
$ENV{'PERL5LIB'} = join ':', qw(
				/nfs/disk100/humpub/modules/PerlModules
				/nfs/disk100/humpub/modules
				/usr/local/badger/bin
				);

# For scripts which access oracle
$ENV{'ORACLE_HOME'} = '/usr/local/oracle';
$ENV{'TWO_TASK'}    = 'sids';

# For blast
$ENV{BLASTDB}       = '/nfs/disk100/humpub/blast';
$ENV{BLASTFILTER}   = '/usr/local/pubseq/bin';
$ENV{BLASTMAT}      = '/nfs/disk100/pubseq/blastdb';
$ENV{NCBI}          = '/nfs/disk100/pubseq/blastdb';

# For halfwise
$ENV{WISECONFIGDIR} = '/nfs/disk100/pubseq/wise/wisecfg';

# List of dirs for PATH
@path = qw(
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
	   );

# Set PATH environment
$ENV{'PATH'} = join ':', @path;

1;

__END__

=head1 SYNOPSIS

    use Hum::Env;

=head2 Author

James Gilbert email B<jgrg@sanger.ac.uk>
