
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
use warnings;
use Carp;

# HOME environment variable (and LOGDIR)
$ENV{HOME} = (getpwuid($<))[7];
$ENV{LOGDIR} = $ENV{HOME};

# Ensure @INC gets propagated in system calls
#$ENV{PERL5LIB} = join ':', @libs;
$ENV{PERL5LIB} = join ':', @INC;
# For blast
$ENV{BLASTDB}       = '/nfs/disk100/humpub/blast';
$ENV{BLASTFILTER}   = '/usr/local/pubseq/bin';
$ENV{BLASTMAT}      = '/nfs/disk100/pubseq/blastdb';
$ENV{NCBI}          = '/nfs/disk100/pubseq/blastdb';

1;

__END__

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>

