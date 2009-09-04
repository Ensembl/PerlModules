
=pod

=head1 NAME Hum::Lock

=head1 DESCRIPTION

B<Hum::Lock> is used to create lockdirs, which
are used prevent multiple incantations of the
same script running on the same data.  Directory
information should be synced over NFS, so this
should provide a reasonably robust locking
mechanism.  Lockdirs are automatically deleted
when the lock object goes out of scope, or the
script dies.

=cut

package Hum::Lock;

use strict;
use warnings;
use Carp;
use Sys::Hostname;
use Cwd qw( cwd );

# Allow processExists sub to be exported
use Exporter;
use vars qw( @EXPORT_OK @ISA );
@ISA = qw( Exporter );
@EXPORT_OK = qw( processExists );

BEGIN {
    my %psCommands = (
                      dec_osf => 'ps -A',
		      linux   => 'ps ax',
		      solaris => 'ps -A'
		      # Ignoring SGIs, since not under LSF
		      );
    # Select ps command for host type
    sub psCommand ($) {
        my $ostype = shift;
        return $psCommands{ $ostype };
    }
}

# Access methods
sub dir {
    my $lock = shift;
    return $lock->{'dir'};
}
sub home {
    my $lock = shift;
    return $lock->{'home'};
}

# The new method does all the work
sub new {
    my $pkg = shift;
    my $lockDir = shift;
    my $timeout = shift || 0;
    my $start = time();
    my $hostname = hostname();
    
    # Must have a name for the lockdir!
    unless ($lockDir) {
    	croak("No name supplied for lock directory");
    }
    
    # Give lockdir ".LOCK" extension if none supplied
    unless ($lockDir =~ /.+\.[^\.]+$/) {
    	$lockDir =~ s/\.+$//; # Remove trailing dots
    	$lockDir = $lockDir . ".LOCK";
    }
    
    # Create lock directory
    # Directory info should be sync'd over NFS
    while (1) {
    
        # Try to make a lock
        last if writeLock( $lockDir );
        
        my( $hostName, $processID );
        unless (($hostName, $processID) = readLock($lockDir)) {
            sleep 5;
            next;
        }

    	# Is the process still running?
    	my $status = processExists( $hostName, $processID );

    	if ($status eq 'RUN') {
                my $msg = "Process '$processID' still running on host '$hostName'\n";
                if ($timeout) {
                    sleep 5;
                    if (time > $start + $timeout) {
                        croak("${msg}Failed to set lock after $timeout seconds");
                    }
                } else {
    	        croak $msg;
                }
    	}
    	elsif ($status eq 'DEAD') {
            # Remove the lock
    	    trashLock( $lockDir );
    	}
    	else {
            # Can't tell if process still running, so not
            # safe to continue trying to set lock.
    	    croak("Error from processExists: $status");
    	}
    }
    
    # Create the lockfile object
    return bless {
    	    	  'dir' => $lockDir,
     		  'home' => cwd()
		  }, $pkg;
}

# Uses LSF command "lsrun" to see if a process is
# running on a remote host
sub processExists {
    my( $host, $pid ) = @_;
    my( $ostype, $ps, $ps_pipe, $RUN );
    
    # Don't need lsrun if on same host
    if ($host eq hostname()) {
        $ostype = $^O;
        $ps = psCommand($ostype);
        $ps_pipe = "$ps |";
    } else {
        $ostype = qx(lsrun -m $host perl -e 'print \$^O')
            or return "Can't determine OS type";
        $ps = psCommand($ostype);
        $ps_pipe = "lsrun -m $host $ps |";
    }

    return "Don't know correct ps command for '$ostype'" unless $ps;

    open PS, $ps_pipe
	or return "Can't open pipe '$ps_pipe' : $!";
    while (<PS>) {
        $RUN = 1 if /^\s*$pid\s/;
    }
    # Check status of lsrun ps command 
    if (close PS) {
        return $RUN ? 'RUN' : 'DEAD';
    } else {
        return $! ? "Error from ('$ps_pipe') : $!"
                  : "Error: ('$ps_pipe') exited with status '$?'";
    }
}

# These subroutines access the OWNER
# file inside the lock directory
BEGIN {

    # Name of file containing process info
    my $OWNER = 'OWNER';
    my $END_MARKER = '_END_OF_FILE_';

    sub writeLock {
        my( $dir ) = @_;
        my $hostname = hostname();
        my $owner = "$dir/$OWNER";
        local *NEWLOCK;
        
        # mkdir command actually makes lock
        if (mkdir($dir, 0777)) {
            # Record process info in owner file
            open NEWLOCK, "> $owner"
    	        or croak("Can't write to '$owner'; $!");
            print NEWLOCK "$hostname $$ $END_MARKER";
            unless (close NEWLOCK) {
                my $exit = $!;
                trashLock($dir);
                croak("Error writing to '$owner'; $exit");
            }
            return 1;
        } else {
            return;
        }
    }

    sub readLock {
        my $dir = shift;
        my $owner = "$dir/$OWNER";
        local *OLDLOCK;

        # Read host and process ID from lockfile
        open OLDLOCK, $owner or croak("Can't open owner file '$owner' : $!");
        my ($host, $pid, $end) = split / /, <OLDLOCK>, 3;
        close OLDLOCK;

        # Check that the other process has finished
        # writing to the file
        return unless $end eq $END_MARKER;

        # Check for hostname and valid process ID
        if ($host and ($pid =~ /^\d+$/)) {
            return( $host, $pid );
        } else {
    	    croak("Can't parse owner file '$owner'");
        }
    }

    sub trashLock {
        my( $dir ) = @_;
        my $owner = "$dir/$OWNER";

        unlink( $owner );
        rmdir( $dir );
    }
}

# Remove the lockfile
sub DESTROY {
    my $lock = shift;
    
    my $dir     = $lock->dir();
    my $homeDir = $lock->home();
        
    # Save the current directory
    my $saveDir = cwd();
    
    # chdir to directory where lock file was created
    chdir( $homeDir ) or warn "Can't find direcory '$homeDir'" and return;

    my( $host, $pid ) = readLock( $dir );
    
    # It's rude to remove other people's locks
    # (This prevent children removing parent's lock)
    return unless $pid == $$ and $host eq hostname();

    trashLock( $dir ) or warn "Error removing '$dir' : $!";

    chdir( $saveDir ) or warn "Couldn't chdir back to $saveDir";
}

__END__

=head1 SYNOPSIS

    use Hum::Lock;
    
    # Catch SIGTERM so that lock file is removed if killed
    $SIG{'TERM'} = sub { die "Shot through the heart!" };
    
    my $lock; # Lock will be removed when it goes out of scope.
    eval {
        # The new() method is fatal on failure
        $lock = Hum::Lock->new('anaScript.lock');
    };
    if ($@) {
        die "Can't set lock: $@\n";
    }

=head1 METHODS

=over 4

=item new

    $lock = Hum::Lock->new( $dirname );

The only call you need to use.  Creates the lock
file I<$dirname>, and returns a lock object on
success, or croaks on failure.  If I<$dirname>
doesn't contain an extension, then ".LOCK" is
appended to it (to make it obvious what the
directory is for).  The B<lsrun> command must be
available on the machine.

=item processExists

    $exists = processExists( $host, $pid );

Checks wether the process with PID I<$pid> exists
on host I<$host> using the LSF system.  Will fail
if the host concerned isn't using LSF, unless the
lock was set by the current host, in which case
LSF is bypassed.  Optionally exportable from
Hum::Lock.

=item DESTROY

The I<DESTROY> method is used to automatically
remove the lock file created when the lock object
goes out of scope, or if the script dies.  Since
the working directory of the script is recorded
in the lock object, the I<DESTROY> method should
be able to find its lock.

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

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>

