
### Hum::Ace::LocalServer

package Hum::Ace::LocalServer;

use strict;
use Carp;
use Ace;
use Socket; # For working out a port which is unused
use Symbol 'gensym';

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

sub _reserve_random_port {
    my( $self ) = @_;
    
    my $tcp = getprotobyname('tcp');
    my $sock = gensym();
    socket($sock, PF_INET, SOCK_STREAM, $tcp);

    # Choose an unoccupied port at random
    my $base        = 55000;
    my $port        = 0;
    my $tries       = 0;
    my $max_tries   = 1000;
    until ($port) {
        $tries++;
        $port = $base + int(rand 5000);
        print STDERR "\nTrying port '$port' ...";
        if (bind($sock, sockaddr_in($port, INADDR_ANY))) {
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
    
    $self->{'_reserved_socket'} = $sock;
    
    return $port;
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
    return '0:1:0';
}

sub additional_server_parameters {
    return('-silent');
}

sub ace_handle {
    my( $self ) = @_;
    
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
    return (
        -HOST       => $host,
        -PORT       => $port,
        -TIMEOUT    => 60,
        );
}

sub disconnect_client {
    my( $self ) = @_;
    
    $self->{'_ace_handle'} = undef;
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

sub restart_server {
    my( $self ) = @_;
    
    $self->disconnect_client;
    $self->kill_server;
    $self->start_server;
}

sub kill_server {
    my( $self ) = @_;

    my $ace = $self->ace_handle;
    $ace->raw_query('shutdown now');
    $ace = undef;
    $self->disconnect_client;
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
    
    if (my $pid = fork) {
        $self->server_pid($pid);
        return 1;
    }
    elsif (defined $pid) {
        my $exe = $self->server_executable;
        my $tim = $self->timeout_string;
        my @exec_list = ($exe, $path, $port, $tim);
        if (my @param = $self->additional_server_parameters) {
            push(@exec_list, @param);
        }
        warn "Running (@exec_list)\n";
        exec(@exec_list)
            or confess("exec(",
                join(', ', map "'$_'", @exec_list),
                ") failed : $!");
    }
    else {
        confess "Can't fork server : $!";
    }
}

sub make_server_wrm {
    my( $self ) = @_;
    
    local *WRM;
    
    my $path = $self->path
        or confess "path not set";
    my $wspec = "$path/wspec";
    confess "No wspec directory"
        unless -d $wspec;
    my $server_wrm = "$wspec/serverconfig.wrm";
    return if -e $server_wrm;
    
    open WRM, "> $server_wrm"
        or die "Can't create '$server_wrm' : $!";
    print WRM map "\n$_\n", 
        'WRITE NONE',
        'READ WORLD';
    close WRM;
}

sub DESTROY {
    my( $self ) = @_;
    
    $self->kill_server;
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

