
package Hum::NetFetch;

use strict;
use Exporter;
use vars qw( @EXPORT_OK @ISA );
use LWP::Simple qw( get );
use humConf qw( HUMPUB_ROOT );
use Hum::Lock;
use Embl;

@ISA = qw( Exporter );
@EXPORT_OK = qw( netfetch wwwfetch );

# email address of EBI email sequence server
my $NetServ = 'netserv\@ebi.ac.uk';

# procmail is set up to put the body of netserv
# messages in to this directory.  Messages get
# named "msg.<UNIQUE KEY>".
my $EMBL_emails_dir = "$HUMPUB_ROOT/data/EMBL_netserv_email";

BEGIN {
    my $embl_simple_url = 'http://www.ebi.ac.uk/cgi-bin/emblfetch';
    
    sub wwwfetch {
        my( $ac ) = @_;
        my $embl = get("$embl_simple_url?$ac")
            or die "No response from '$embl_simple_url'";
        die "Entry for '$ac' not found by server '$embl_simple_url'"
            if $embl =~ /no entries found/i;
        
        # Remove html markup
        $embl =~ s   {^<PRE>}{} or die "Can't remove leading '<PRE>' tag";
        $embl =~ s{\n</PRE>$}{} or die "Can't remove trailing '</PRE>' tag";
        $embl =~ s{<A HREF=.+?>([^<]+)</A>}{$1}g;
        
        return $embl;
    }
}
sub netfetch {
    my( $list, $TIMEOUT ) = @_;

    my %Request = ();

    return \%Request unless @$list;

    %Request = map { $_, 0 } ('EMAIL_LOG_FILE', @$list);

    $TIMEOUT ||= 1200;   # Kill ourselves after timeout
    $SIG{'ALRM'} = sub {
                        die "Timeout.\nCouldn't retrieve:\n",
                            map "  $_\n", grep { $Request{$_} == 0 } keys %Request;
                        };
    
    # Set lock
    my $Lock;
    eval { $Lock = Hum::Lock->new("$EMBL_emails_dir/netfetch.lock"); };
    if ($@) {
        die "Sorry, another 'netfetch' appears to be running\n$@";
    }

    # Send email to retrieve sequences
    send_nuc_request( $NetServ, @$list );
    my $Submit_Time = time;

    alarm $TIMEOUT;

    # Loop until we've got all our replies
    for (;;) {

        my( @msg_files ) = get_messages( $EMBL_emails_dir, $Submit_Time );

        foreach my $msg ( @msg_files ) {
        
            local *MSG_FILE;
            open MSG_FILE, $msg or die "Can't open ('$msg') : $!";
            my $first_line = <MSG_FILE>;

            # Is it an EMBL file?
            if ($first_line =~ /^ID   /) {
                # Check for correct end characters
                seek( MSG_FILE, -4, 2 );
                my $end = join '', <MSG_FILE>;
                if ($end =~ m|^//\s*$|) {
                    # Parse the entry and add it to the Requests hash
                    my( @ident );
                    seek( MSG_FILE, 0, 0 );
                    my $embl = Embl->entryFromStream(\*MSG_FILE);
                    # Get the entry name and all accession numbers
                    $ident[0] = $embl->getLine('EMBL::ID')
                                     ->entryname() or die "Can't get ID from ('$msg')";
                    push( @ident, @{$embl->getLine('EMBL::AC')->accessionList()});
                    
                    {
                        my( $placed_flag );
                        foreach my $name (@ident) {
                            if (exists $Request{ $name }) {
                                $Request{ $name } = $embl;
                                $placed_flag = 1;
                            }
                        }
                        unless ($placed_flag) {
                            warn "Couldn't place entry: ",
                                join(', ', map "'$_'", @ident), "\n";
                        }
                    }
                } else {
                    # File may still be being written to
                    #warn "End didn't match: $end";
                    $msg = 0;
                }
            } else {
                seek( MSG_FILE, 0, 0 );
                while (<MSG_FILE>) {
                    # * File NUC:bK285F3 not found.
                    #      * File NUC:bK285F3 not found.
                    if (/^\* File NUC:(\S+) (sent|not found)/) {
                        $Request{ 'EMAIL_LOG_FILE' } = 1;
                        if ($2 eq 'not found') {
                            $Request{ $1 } = 'FAILED' if exists $Request{ $1 };
                        }
                    }
                }
                $msg = 0 unless $Request{ 'EMAIL_LOG_FILE' };
            }
            if ($msg) {
                unlink( $msg ) or die "Can't unlink ('$msg')";
            }
        }
        last unless missing(\%Request);
        sleep 10;
    }
    
    alarm 0;

    # Warn about failed requests
    if (my @Failed = grep { $Request{$_} eq 'FAILED' } keys %Request) {
        warn "Failed to get entries for the following requests:\n", map "  $_\n", @Failed;
    }

    delete $Request{'EMAIL_LOG_FILE'};
    return \%Request;
}

sub send_nuc_request {
    my( $address, @request_list ) = @_;
    local *NETSRV;
     open NETSRV, "| mailx $address" or die "Can't open mailx to ('$address') : $!";
    print NETSRV "\nSIZE 1900\n"; # Sanger email size limit
    print NETSRV map "GET NUC:$_\n", @request_list;
    close NETSRV or die "Error sending mail: $!";
}

# Returns list of files in $dir newer than $time
sub get_messages {
    my( $dir, $time ) = @_;

    opendir MSG, $dir or die "Weird stuff - can't opendir ('$dir')";
    my %msgs = map { $_, (stat($_))[9] } # make hash of FILENAME => MODIFICATION TIME
               map "$dir/$_", grep /^msg\./, readdir MSG;
    closedir MSG;
    return grep { $msgs{$_} > $time } keys %msgs;
}

# Returns true if any of the requested entries
# haven't yet arrived or failed
sub missing {
    my( $list ) = @_;
    
    foreach my $v (values %$list) {
        return 1 unless $v;
    }
    return;
}

1;

__END__
