
### Hum::Pfetch

package Hum::Pfetch;

use strict;
use Carp;
use Hum::EMBL;
use Hum::Conf qw{ PFETCH_SERVER_LIST };
use IO::Socket;
use Exporter;

use vars qw{@ISA @EXPORT_OK};
@ISA = ('Exporter');
@EXPORT_OK = qw{
    get_Sequences
    get_descriptions
    get_lengths
    get_EMBL_entries
    };

sub get_server {
    return _connect_to_server(
        'pfetch',
        $PFETCH_SERVER_LIST);
}

sub _connect_to_server {
    my( $type, $server_list ) = @_;
    local $^W = 0;
    
    foreach my $host_port (@$server_list) {
        my($host, $port) = @$host_port;
        #warn "Trying '$host:$port'\n";
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
    confess "No $type servers available";
}

sub get_Sequences {
    my( @id_list ) = @_;
    
    confess "No names provided" unless @id_list;
    
    my $server = get_server();
    print $server "-q @id_list\n";
    my( @seq_list, @missing_i );
    for (my $i = 0; $i < @id_list; $i++) {
        chomp( my $seq_string = <$server> );
        if ($seq_string eq 'no match') {
            # Add to list of indexes of missing sequences
            push(@missing_i, $i);
        } else {
            my $seq = Hum::Sequence->new;
            $seq->name($id_list[$i]);
            $seq->sequence_string($seq_string);
            $seq_list[$i] = $seq;
        }
    }
    
    return @seq_list;
}

sub get_descriptions {
    my( @id_list ) = @_;
    
    confess "No names provided" unless @id_list;
    
    my $server = get_server();
    print $server "-D @id_list\n";
    my( @desc_list );
    for (my $i = 0; $i < @id_list; $i++) {
        chomp( my $desc = <$server> );
        if ($desc eq 'no match') {
            $desc_list[$i] = undef;
        } else {
            $desc_list[$i] = $desc;
        }
    }
    return @desc_list;
}

sub get_lengths { # : list_reference -> hash_reference
	my $name_lp = shift @_;
    
    confess "No names provided" unless @$name_lp;
    
    my $server = get_server();
    print $server "-l @$name_lp\n";

	my $length_hp = {};

    for (my $i = 0; $i < @$name_lp; $i++) {
		my $name = $name_lp->[$i];
        my $length = <$server>;
		if(! $length) {
			warn "The length of $name is missing";
		}
        chomp $length;
        if ($length ne 'no match') {
			$length_hp->{$name} = $length;
        }
    }
    return $length_hp;
}

sub get_EMBL_entries {
    my( @id_list ) = @_;
    
    confess "No names provided" unless @id_list;
    
    my $parser = Hum::EMBL->new;
    
    my $server = get_server();
    print $server "-F @id_list\n";
    my( @entries );
    for (my $i = 0; $i < @id_list; $i++) {
        my $entry = join '', <$server>;
        if ($entry eq "no match\n") {
            $entries[$i] = undef;
        } else {
            my $embl = $parser->parse(\$entry)  
                or confess "nothing returned from parsing '$entry'";
            $entries[$i] = $embl;
        }
    }
    return @entries;
}

1;

__END__

=head1 NAME - Hum::Pfetch

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

