
### Hum::AnaStatus::AceDatabase

package Hum::AnaStatus::AceDatabase;

use strict;
use warnings;
use Carp;
use Hum::Submission 'prepare_statement';
use Ace;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

{
    my( %species_table, %species_AceDatabase );

    sub new_from_species_name {
        my( $pkg, $species ) = @_;
    
        unless (%species_table) {
            # species_ace_db table is very small,
            # so the least expensive thing to do
            # is just fetch it all.
            my $sth = prepare_statement(q{
                SELECT species_name
                  , host
                  , port
                  , path
                  , queue
                FROM species_ace_db
                });
            $sth->execute;
            while (my ($name, $host, $port, $path, $queue) = $sth->fetchrow) {
                $species_table{$name} = [$host, $port, $path, $queue];
            }
        }
        
        if (my $ace = $species_AceDatabase{$species}) {
            return $ace;
        } else {
            my $data = $species_table{$species}
                or confess "No species_ace_db entry for '$species'";
            my($host, $port, $path, $queue) = @$data;
            
            $ace = $pkg->new;
            $ace->host($host);
            $ace->port($port);
            $ace->path($path);
            $ace->queue($queue);
            
            # Only make 1 object per species
            $species_AceDatabase{$species} = $ace;
            
            return $ace;
        }
    }
}

sub host {
    my( $self, $host ) = @_;
    
    if ($host) {
        $self->{'_host'} = $host;
    }
    return $self->{'_host'};
}

sub port {
    my( $self, $port ) = @_;
    
    if ($port) {
        confess "Illegeal port '$port'"
            unless $port =~ /^\d+$/;
        $self->{'_port'} = $port;
    }
    return $self->{'_port'};
}

sub path {
    my( $self, $path ) = @_;
    
    if ($path) {
        $self->{'_path'} = $path;
    }
    return $self->{'_path'};
}

sub queue {
    my( $self, $queue ) = @_;
    
    if ($queue) {
        $self->{'_queue'} = $queue;
    }
    return $self->{'_queue'};
}

sub db_handle {
    my( $self, $cycles ) = @_;

    $cycles ||= 40;

    if (my $dbh = $self->{'_db_handle'}) {
        return $dbh;
    } else {
        my $host = $self->host;
        my $port = $self->port;
        if ($host and $port) {
            for (my $i = 0; $i < $cycles; $i++) {
                last if $dbh = Ace->connect(
                    -HOST => $host,
		    -PORT => $port,
                    );
                sleep 30;
            }
            unless ($dbh) {
                # Give up after more than 20 min of trying
                confess "Couldn't connect to acedb host '$host' on port '$port'";
            }
        }
        elsif (my $path = $self->path) {
            $dbh = Ace->connect(
                -PATH   => $path,
                ) or confess "Can't connect to acedb at '$path'";
        }
        else {
            confess "Need host and port (or path) to connect";
        }
        
        # Defaults for database handles
        $dbh->auto_save(0);
        $dbh->date_style('ace');
        
        $self->{'_db_handle'} = $dbh;
        return $dbh;
    }
}

# This won't work if something else still has a
# reference to the AcePerl handle.
sub disconnect {
    my( $self ) = @_;

    $self->{'_db_handle'} = undef;
}


1;

__END__

=head1 NAME - Hum::AnaStatus::AceDatabase

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

