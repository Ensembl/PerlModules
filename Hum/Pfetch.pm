
### Hum::Pfetch

package Hum::Pfetch;

use strict;
use Carp;
use Hum::Conf 'PFETCH_SERVER_LIST';
use IO::Socket;
use Exporter;

use vars qw{@ISA @EXPORT_OK};
@ISA = ('Exporter');
@EXPORT_OK = qw{
    get_Sequences
    };

sub get_server {
    local $^W = 0;
    foreach my $host_port (@$PFETCH_SERVER_LIST) {
        my($host, $port) = @$host_port;
        my $server = IO::Socket::INET->new(
            PeerAddr => $host,
            PeerPort => $port,
            Proto    => 'tcp',
            Type     => SOCK_STREAM,
            Timeout  => 10,
            );
        if ($server) {
            $server->autoflush(1);
            return $server;
        }
    }
    confess "No pfetch servers available";
}

sub get_Sequences {
    my( @id_list ) = @_;
    
    confess "No names provided" unless @id_list;
    
    my $server = get_server();
    print $server "-q @id_list\n";
    my( @seq_list );
    for (my $i = 0; $i < @id_list; $i++) {
        chomp( my $seq_string = <$server> );
        if ($seq_string ne 'no match') {
            my $seq = Hum::Sequence->new;
            $seq->name($id_list[$i]);
            $seq->sequence_string($seq_string);
            $seq_list[$i] = $seq;
        }
    }
    return @seq_list;
}

1;

__END__

=head1 NAME - Hum::Pfetch

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

