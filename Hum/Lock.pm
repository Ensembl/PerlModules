
=pod

=head1 NAME Hum::Lock

=head1 DESCRIPTION

B<Hum::Lock> is used to create lockfiles, which
are used prevent multiple incantations of the
same script running on the same data.  Lockfiles
are automatically deleted when the lock object
goes out of scope, or the script dies.

=cut

package Hum::Lock;

use strict;
use Carp;
use Sys::Hostname;
use Cwd qw( cwd );

# Allow processExists sub to be exported
use Exporter;
use vars qw( @EXPORT_OK @ISA );
@ISA = qw( Exporter );
@EXPORT_OK = qw( processExists );

sub psCommand ($) {
    # Select ps command for host type
    my %psCommands = (
                      dec_osf => 'ps -A',
		      linux   => 'ps -ax',
		      solaris => 'ps -A'
		      # Ignoring SGIs, since not under LSF
		      );
    my $ostype = shift;
    return $psCommands{ $ostype };
}

# Access methods
sub file {
    my $lock = shift;
    return $lock->{'file'};
}
sub home {
    my $lock = shift;
    return $lock->{'home'};
}

# The new method does all the work
sub new {
    my $pkg = shift;
    my $lockFile = shift;

    # Must have a name for the lockfile!
    unless ($lockFile) {
    	croak("No lockfile name supplied");
    }
    
    # Give filename ".lock" extension if none supplied
    unless ($lockFile =~ /.+\.[^\.]+$/) {
    	$lockFile =~ s/\.+$//; # Remove trailing dots
	$lockFile = $lockFile . ".lock";
    }
    
    # Check for existing lockfile
    if (-e $lockFile) {
    	# Read host and process ID from lockfile
    	open LOCK, "< $lockFile" or croak("Can't open lockfile [ $lockFile ] : $!");
	my ($hostName, $processID) = split / /, <LOCK>, 2;
	close LOCK;
	
	# Check for hostname and valid process ID
	if ($hostName and ($processID =~ /^\d+$/)) {
	
	    # Is the process still running?
	    my $status = processExists( $hostName, $processID );
	    
	    if ($status eq 'RUN') {
	    	croak("Process still running [ $hostName - $processID ]\n");
	    }
	    elsif ($status eq 'DEAD') {
	    	unlink( $lockFile ) == 1
		    or croak("Can't unlink old lock [ $lockFile ] : $!");
	    }
	    else {
	    	croak("Error from processExists: $status");
	    }
	} else {
	    croak("Can't parse lockfile [ $lockFile ]");
	}
    }
    
    # Haven't returned, so create a lock file
    open NEWLOCK, "> $lockFile"
    	or croak("Can't open [ $lockFile ] for write: $!");
    print NEWLOCK hostname(), ' ', $$;
    close NEWLOCK;
    
    # Create the lockfile object
    return bless {
    	    	  file => $lockFile,
     		  home => cwd()
		  }, $pkg;
}

# Uses LSF command "lsrun" to see if a process is
# running on a remote host
sub processExists {
    my( $host, $pid ) = @_;
    
    # Get OS type for host which set lockfile
    if (my $ostype = qx(lsrun -m $host perl -e 'print \$^O')) {
    
    	# Get correct format for ps command to show all processes
    	my $psCommand = psCommand( $ostype )
	    or return "Don't know correct ps command for [ $ostype ]";
	
	open PS, "lsrun -m $host $psCommand |"
	    or return "Can't run [ lsrun -m $host $psCommand ]";
	while (<PS>) {
	    /^\s*$pid\s/ and return 'RUN'
	}
	close PS;
	
	# Check status of lsrun ps command 
	if ($?) {
	    return "Error: $? $!";
	} else {
	    return 'DEAD';
	}
    } else {
    	return "Can't determine OS type";
    }
}

# Remove the lockfile
sub DESTROY {
    my $lock = shift;
    
    my $file = $lock->file();
    my $homeDir = $lock->home();
    
    # Save the current directory
    my $saveDir = cwd();
    
    # chdir to directory where lock file was created
    chdir( $homeDir ) or warn "Can't find $homeDir"
    	and return;
    unlink( $file ) == 1 or warn "Couldn't delete $file";
    chdir( $saveDir ) or warn "Couldn't chdir back to $saveDir";
}

__END__

=head1 SYNOPSIS

    use Hum::Lock;

    my $lock; # Lock will be removed when it goes
              # out of scope.
    eval {
        # new method is fatal on failure
        $lock = Hum::Lock->new('anaScript.lock');
    };
    if ($@) {
        die "Can't set lock: $@\n";
    }
    print "Host: ", $lock->host(),
    	"\nProcessID: ", $lock->pid(), "\n";
    
Creates the lock file I<anaScript.lock>, then
prints out some details which are held in the
object.

=head1 METHODS

=over 4

=item new

    $lock = Hum::Lock->new( $filename );

The only call you need to use.  Creates the lock
file I<$filename>, and returns a lock object on
success, or croaks on failure.  If I<filename>
doesn't contain a file extension, then ".lock" is
appended to it.  The B<lsrun> command must be
available on the machine.

=item processExists

    $exists = processExists( $host, $pid );
    
Checks wether the process with PID I<$pid> exists
on host I<$host> using the LSF system.  Will fail
if the host concerned isn't using LSF.  Optionally
exportable from Hum::Lock.

=item DESTROY

The I<DESTROY> method is used to automatically
remove the lock file created when the lock object
goes out of scope, or if the script dies.

=item Lock Variables

The lock object contains a two variables, which
are accessed by the following methods:

=over 4

=item file

The name of the lock file created

=item home

The working directory of the script when the lock
file was created.

=back

=back

=head2 Author

James Gilbert email B<jgrg@sanger.ac.uk>
