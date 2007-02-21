
### Hum::Ace::LocalServer

package Hum::Ace::LocalServer;

use strict;
use Carp;
use Hum::Ace::AcePerlText;
use Socket; # For working out a port which is unused
use Symbol 'gensym';
use POSIX qw(:signal_h :sys_wait_h);
use Digest::MD5 qw(md5_hex);

sub new {
    my( $pkg, $path ) = @_;
    
    my $self = bless {}, $pkg;
    $self->path($path);
    return $self;
}

sub host {
    my( $self, $arg ) = @_;
    
    if ($arg) {
        confess("host doesn't take any arguments");
    }
    return 'localhost';
}

sub port {
    my( $self, $arg ) = @_;
    
    if ($arg) {
        confess("port doesn't take any arguments");
    }
    
    my( $port );
    unless ($port = $self->{'_port'}) {
        $port = $self->_reserve_random_port;
        
        $self->{'_port'} = $port;
    }
    return $port;
}

sub forget_port {
    my ($self) = @_;

    $self->{'_port'} = undef;
}

sub user{
    my( $self, $arg ) = @_;
    $self->{'_user'} = $arg if $arg;
    return $self->{'_user'} || 'localServer';
}

sub pass{
    my( $self, $arg ) = @_;
    $self->{'_pass'} = $arg if $arg;
    return $self->{'_pass'} || 'password';
}

sub _reserve_random_port {
    my( $self ) = @_;

    # Choose an unoccupied port at random
    my $base        = 55000;
    my $port        = 0;
    my $tries       = 0;
    my $max_tries   = 1000;
    until ($port) {
        $tries++;
        $port = $base + int(rand 5000);
        print STDERR "\nTrying port '$port' ...";
        if ($self->_reserve_port($port)) {
            print STDERR " Free\n";
            last;
        } else {
            print STDERR " $!\n";
        }
        $port = 0;
        
        # Don't loop for ever!
        if ($tries >= $max_tries) {
            confess "Failed to find free port";
        }
    }
    
    return $port;
}

sub _reserve_port {
    my ($self, $port) = @_;
    
    my $tcp = getprotobyname('tcp');
    my $sock = gensym();
    socket($sock, PF_INET, SOCK_STREAM, $tcp);

    if (bind($sock, sockaddr_in($port, INADDR_ANY))) {
        $self->{'_reserved_socket'} = $sock;
        return 1;
    } else {
        return;
    }
}

sub wait_for_port_release {
    my ($self) = @_;
    
    my $timeout = 240;
    my $port = $self->port
      or confess "port not set. server not started?";
    for (my $t = 0; $t < $timeout; $t++) {
        if ($self->_reserve_port($port)) {
            warn "Port was released after $t seconds\n";
            return 1;
        }
        sleep 1;
    }
    confess "Port was not released after waiting for $timeout seconds.";
}

# Call before starting server to free the port.
sub _release_reserved_port {
    my( $self ) = @_;
    
    if (my $sock = $self->{'_reserved_socket'}) {
        close($sock);
        $self->{'_reserved_socket'} = undef;
    }
}

sub path {
    my( $self, $path ) = @_;
    
    if ($path) {
        $self->{'_path'} = $path;
    }
    return $self->{'_path'};
}

sub default_server_executable {
    return 'saceserver';
}

sub timeout_string {
    my( $self, $string ) = @_;
    
    if ($string) {
        $self->{'_timeout_string'} = $string;
    }
    return $self->{'_timeout_string'}
        || $self->default_timeout_string();

}
sub default_timeout_string{
    return '0:0:100:0';
}

sub additional_server_parameters {
    return('-readonly');
}

sub ace_handle {
    my( $self ) = @_;

    my $spid = $self->server_pid();
    return unless $spid;

    # Get cached ace handle
    my $ace = $self->{'_ace_handle'};
    
    # Test if it is valid
    my( $ping );
    eval{ $ping = $ace->ping; };

    # Connect if invalid
    unless ($ping) {
        my @param = $self->connect_parameters;
        my $max_time = 5 * 60;
        my $try_interval = 2;
        for (my $i = 0; $i < $max_time; $i += $try_interval) {
            $ace = Ace->connect(@param);
            if ($ace) {
                $ace->auto_save(0);
                last;
            } else {
                sleep $try_interval;
            }
            # tests if the server's still alive.
            # This is better than previous version with flag.
            last unless(kill 0, $spid);
        }
        if ($ace) {
            $self->{'_ace_handle'} = $ace;
        } else {
            confess("Can't connect to db with (@param) :\n", Ace->error);
        }
    }
    return $ace;
}

sub connect_parameters {
    my( $self ) = @_;
    
    my $host = $self->host;
    my $port = $self->port;
    my @param = (
                 -HOST       => $host,
                 -PORT       => $port,
                 -TIMEOUT    => 60,
        );
    if(my $user = $self->user){
        push(@param, (-USER => $user));
    }
    if(my $pass = $self->pass){
        push(@param, (-PASS => $pass));
    }
    return @param;
}

sub disconnect_client {
    my( $self ) = @_;
    
    # We do a bad thing, and mess with the AcePerl
    # object hash:
    $self->{'_ace_handle'}{'database'} = undef;
    $self->{'_ace_handle'}             = undef;
}

sub server_executable {
    my( $self, $exe ) = @_;
    
    if ($exe) {
        $self->{'_server_executable'} = $exe;
    }
    return $self->{'_server_executable'}
        || $self->default_server_executable;
}

sub server_pid {
    my( $self, $pid ) = @_;
    
    if ($pid) {
        $self->{'_server_pid'} = $pid;
    }
    return $self->{'_server_pid'};
}

sub origin_pid {
    my( $self, $pid ) = @_;
    
    if ($pid) {
        $self->{'_origin_pid'} = $pid;
    }
    return $self->{'_origin_pid'};
}

sub restart_server {
    my( $self ) = @_;
    
    $self->kill_server;
    $self->start_server;
}

sub kill_server {
    my( $self ) = @_;

    if (my $ace = $self->ace_handle) {
        $ace->raw_query('shutdown');
    }
    $self->disconnect_client;
    $self->forget_port;
}

{
    my $INFO  = {};
    my $DEBUG_THIS = 0;
    sub full_child_info{
        return $INFO;
    }
    sub start_server {
        my( $self ) = @_;
        
        $self->make_server_wrm;
        
        my $path = $self->path
            or confess "path not set";
        my $port = $self->port
            or confess "no port number";
        
        if ($self->can('_release_reserved_port')) {
            $self->_release_reserved_port;
        }

        # BUILD exec_list early
        my $exe = $self->server_executable;
        my $tim = $self->timeout_string;
        my @param = $self->additional_server_parameters;
        
        # Redirect STDOUT and STDERR from server into a log file.
        my $log_file = "$path/server.log";
        my $exec_list = "$exe @param $path $port $tim >> $log_file 2>&1";
        warn "LocalServer: $exec_list\n";

        if (my $pid = fork) {
            $self->server_pid($pid);
            $self->origin_pid($$);
            $INFO->{$pid}->{'ARGV'} = $exec_list;
            $INFO->{$pid}->{'PID'}  = $pid;
            return 1;
        }
        elsif (defined $pid) {
            $SIG{CHLD} = 'DEFAULT'; # Child DOESN'T need this!!

            print STDERR "Starting up ".`which $exe`."\n";

            warn "child: Running ($exec_list)\n" if $DEBUG_THIS;
            #close(STDIN)  unless $DEBUG_THIS;
            #close(STDOUT) unless $DEBUG_THIS;
            #close(STDERR) unless $DEBUG_THIS;
            exec $exec_list;
            warn "child: exec ($exec_list) FAILED\n ** ERRNO $!\n ** CHILD_ERROR $?\n";
            CORE::exit( 255 );
        }
        else {
            confess "Can't fork server : $!";
        }
        return 0;
    }
}
sub make_server_wrm {
    my( $self ) = @_;
    
    local ( *WRM, *PWRM );
    
    my $path = $self->path
        or confess "path not set";
    my $wspec = "$path/wspec";
    confess "No wspec directory"
        unless -d $wspec;
    my $server_wrm  = "$wspec/serverconfig.wrm";
    my $serverp_wrm = "$wspec/serverpasswd.wrm";
    unless(-e $server_wrm){
        open WRM, "> $server_wrm"
            or die "Can't create '$server_wrm' : $!";
        print WRM map "\n$_\n", 
        'WRITE NONE',
        'READ WORLD';
        close WRM;
    }
    unlink($serverp_wrm);
    unless(-e $serverp_wrm){
        my $user = $self->user;
        my $pass = $self->pass;
        my $userpass_hash = ($user && $pass ? "$user ".md5_hex("$user$pass"): '');
        open PWRM, "> $serverp_wrm"
            or die "Can't create '$serverp_wrm' : $!";
        print PWRM map "\n$_\n", 
        "admin: $user",
        'write:',
        'read:',
        $userpass_hash;# password is 'password'
        close PWRM;
    }
    return 1;
}

sub DESTROY {
    my( $self ) = @_;
    warn "DESTROY $self and reset SIGCHLD in PID $$";
    if(my $spid = $self->server_pid){
        my $opid = $self->origin_pid;
        if($opid && $opid == $$){
            $self->kill_server;
            $SIG{CHLD} = 'DEFAULT';
        }else{
            warn "Not killing server with pid $spid (not server leader '$opid' != '$$').\n";
        }
    }else{
        # When the fork occurs everything gets copied.
        # This includes the reference to the $self
        # which is likely to be held in the calling module.
        # If the exec fails then the reference STILL exists.
        # The DESTROY is then called during global destruction.
        # Trying to kill a failed to exec server is silly
        # So ... we don't ...
        # Although I've fixed this a bit with the kill 0, $pid.
    }
}

1;

__END__

=head1 NAME - Hum::Ace::LocalServer

=head1 DESCRIPTION

This is a LocalServer for local programs.

Connecting using AcePerl via tace is unreliable,
but it is always OK via a server.  This module
starts a socket server on a database, and gives
you an AcePerl handle to it.  Remember, the
database should be on a local disk, not mounted
over NFS - that is always a bad idea!

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

