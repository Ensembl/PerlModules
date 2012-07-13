
### Hum::Pfetch

package Hum::Pfetch;

use strict;
use warnings;
use Carp;
use Hum::EMBL;
use Hum::StringHandle;
use Hum::Conf qw{ PFETCH_SERVER_LIST };
use IO::Socket;
use LWP;
use HTTP::Cookies::Netscape;
use URI::Escape qw{ uri_escape };
use Exporter;

use vars qw{@ISA @EXPORT_OK};
@ISA = ('Exporter');
@EXPORT_OK = qw{
    do_query
    get_Sequences
    get_descriptions
    get_lengths
    get_EMBL_entries
    };

sub do_query {
    my ($query) = @_;
    
    if (my $url = $ENV{'PFETCH_WWW'}) {
        return pfetch_response_handle($url, $query);
    } else {
        my $server = get_server();
        print $server $query;
        return $server;
    }
}

sub pfetch_response_handle {
    my ($url, $query) = @_;
    
    ### Could re-arrange this so that it works with Bio::Otter::Lace::Client
    ### to prompt the user for their password once the cookie has expired.
    my $jar_file = $ENV{'OTTERLACE_COOKIE_JAR'}
        or die "OTTERLACE_COOKIE_JAR not set\n";

    my $req_str = "request=" . uri_escape($query);

    my $pfetch = LWP::UserAgent->new;
    $pfetch->env_proxy;     # Pick up any proxy settings from environment
    $pfetch->protocols_allowed([qw{ http https }]);
    $pfetch->agent('hum_pfetch/0.1 ');
    push @{ $pfetch->requests_redirectable }, 'POST';
    $pfetch->cookie_jar(HTTP::Cookies::Netscape->new( file => $jar_file ));

    my $request = HTTP::Request->new;
    $request->method('POST');
    $request->uri($url);
    $request->content($req_str);

    my $response = $pfetch->request($request);
    if ($response->is_success) {
        return Hum::StringHandle->new($response->content_ref);
    } else {
        confess $response->message, "\nError running web based pfetch: URL='$url' POST='$req_str'";
    }
}

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
        # warn "Trying '$host:$port'\n";
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
    
    my $fh = do_query("-q @id_list\n");
    my( @seq_list, @missing_i );
    for (my $i = 0; $i < @id_list; $i++) {
        chomp( my $seq_string = <$fh> );
        if ($seq_string eq 'no match' or length($seq_string) ==0) {
            # Add to list of indexes of missing sequences
            push(@missing_i, $i);
            $seq_list[$i] = undef;
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
    
    my $fh = do_query("-D @id_list\n");
    my( @desc_list );
    for (my $i = 0; $i < @id_list; $i++) {
        chomp( my $desc = <$fh> );
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
    
    my $fh = do_query("-l @$name_lp\n");

	my $length_hp = {};

    for (my $i = 0; $i < @$name_lp; $i++) {
		my $name = $name_lp->[$i];
        my $length = <$fh>;
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
    
    my $fh = do_query("-F @id_list\n");
    my( @entries );
    for (my $i = 0; $i < @id_list; $i++) {
        my $entry = <$fh>;
        if ($entry eq "no match\n") {
            $entries[$i] = undef;
        } else {
            while (<$fh>) {
                $entry .= $_;
                last if m{^//};
            }
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

