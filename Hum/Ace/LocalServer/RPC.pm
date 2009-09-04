
### Hum::Ace::LocalServer::RPC

package Hum::Ace::LocalServer::RPC;

use strict;
use warnings;
use Carp;
use Hum::Ace::LocalServer;
use vars '@ISA';

@ISA = ('Hum::Ace::LocalServer');


sub port {
    my( $self, $arg ) = @_;
    
    if ($arg) {
        confess("port doesn't take any arguments");
    }
    
    my( $port );
    unless ($port = $self->{'_port'}) {
        # Max rpc port number is 2 ** 32
        # Take a bit off this (just in case anything
        # else is using the same tactic), and then
        # remove the process id (2 ** 16 max).
        $port = (2 ** 32) - ((2 ** 16) * 12) - $$;
        $self->{'_port'} = $port;
    }
    return $port;
}

sub default_server_executable {
    return 'aceserver';
}

sub timeout_string {
    return '0:0:0';
}

sub additional_server_parameters {
    return;
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

sub make_server_wrm {
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


1;

__END__

=head1 NAME - Hum::Ace::LocalServer::RPC

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

