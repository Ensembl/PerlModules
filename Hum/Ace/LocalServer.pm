
### Hum::Ace::LocalServer

package Hum::Ace::LocalServer;

use strict;
use Carp;
use Ace;

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
        if ($self->server_type eq 'RPC') {
            # Max rpc port number is 2 ** 32
            # Take a bit off this (just in case anything
            # else is using the same tactic), and then
            # remove the process id (2 ** 16 max).
            $port = (2 ** 32) - ((2 ** 16) * 12) - $$;
        } else {
            $port = 55000;
        }
        $self->{'_port'} = $port;
    }
    return $port;
}

sub path {
    my( $self, $path ) = @_;
    
    if ($path) {
        $self->{'_path'} = $path;
    }
    return $self->{'_path'};
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
    
    my $stype = $self->server_type;
    my $host = $self->host;
    my $port = $self->port;
    return (
        -HOST       => $host,
        -PORT       => $port,
        -TIMEOUT    => 60,
        );
}

sub server_type {
    my( $self, $type ) = @_;
    
    if ($type) {
        my @allowed = qw{ SOCKET RPC };
        foreach my $a (@allowed) {
            if ($type eq $a) {
                $self->{'_server_type'} = $type;
                return $type;
            }
        }
        confess "Unknown server type '$type' (allowed values are (@allowed))";
    } else {
        return $self->{'_server_type'} || 'RPC';
    }
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
    return $self->{'_server_executable'} || $self->default_server_executable;
}

sub default_server_executable {
    my( $self ) = @_;
    
    my $stype = $self->server_type;
    if ($stype eq 'RPC') {
        return 'aceserver';
    }
    elsif ($stype eq 'SOCKET') {
        return 'saceserver';
    }
    else {
        confess "Unknown server type '$stype'";
    }
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
    
    my $pid = $self->server_pid or return;
    if (kill "TERM", $pid) {
        return 1;
    } else {
        warn "Failed to kill server; pid = '$pid' : $!";
        return 0;
    }
}

sub start_server {
    my( $self ) = @_;
    
    $self->make_server_wrm;
    
    my $path = $self->path
        or confess "path not set";
    my $port = $self->port
        or confess "no port number";
    if (my $pid = fork) {
        $self->server_pid($pid);
        return 1;
    }
    elsif (defined $pid) {
        my $exe = $self->server_executable;
        my @exec_list = ($exe, $path, $port, '0:0:0');
        warn "Trying (@exec_list)";
        exec(@exec_list)
            or confess("exec(",
                join(', ', map "'$_'", @exec_list),
                ") failed : $!");
    }
    else {
        confess "Can't fork : $!";
    }
}

sub make_server_wrm {
    my( $self ) = @_;
    
    my $stype = $self->server_type;
    if ($stype eq 'RPC') {
        $self->make_rpc_server_wrm;
    }
    elsif ($stype eq 'SOCKET') {
        $self->make_socket_server_wrm;
    }
    else {
        confess "Unknown server type '$stype'";
    }
}

sub make_rpc_server_wrm {
    my( $self ) = @_;
    
    local *WRM;
    
    my $path = $self->path
        or confess "path not set";
    my $wspec = "$path/wspec";
    confess "No wspec directory"
        unless -d $wspec;
    my $server_wrm = "$wspec/server.wrm";
    return if -e $server_wrm;
    
    open WRM, "> $server_wrm"
        or die "Can't create '$server_wrm' : $!";
    print WRM "\nWRITE_ACCESS_DIRECTORY  $wspec\n",
        "\nREAD_ACCESS_DIRECTORY  PUBLIC\n\n";
    close WRM;
}

sub make_socket_server_wrm {
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
        'NO_RESTART',
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

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

