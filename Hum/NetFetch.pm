
package Hum::NetFetch;

use strict;
use Exporter;
use vars qw( @EXPORT_OK );
use humConf qw( HUMPUB_ROOT );
use Hum::Lock;
use Embl;

@EXPORT_OK = qw( netfetch );

# email address of EBI email sequence server
my $NetServ = 'netserv\@ebi.ac.uk';

# procmail is set up to put the body of netserv
# messages in to this directory.  Messages get
# named "msg.<UNIQUE KEY>".
my $EMBL_emails_dir = "$HUMPUB_ROOT/data/EMBL_netserv_email";

my $TIMEOUT = 600;  # Kill ourselves after timeout

sub netfetch {
    my( $list ) = @_;

    my %Request = map { $_, 0 } ('EMAIL_LOG_FILE', @$list);

    $SIG{'ALRM'} = sub {
                        die "Timeout.  Couldn't retrieve the following:\n",
                            map "  $_\n", grep { $Request{$_} == 0 } keys %Request;
                        };
    # Set lock
    my $Lock;
    eval { $Lock = Hum::Lock->new("$EMBL_emails_dir/netfetch.lock"); };
    if ($@) {
        die "Sorry, another 'netfetch' appears to be running\n$@";
    }

    # Send email to retrieve sequences
    send_nuc_request( $NetServ, @Request_List );
    my $Submit_Time = time;

    alarm $TIMEOUT;

    # Loop until we've got all our replies
    for (;;) {

        my( @msg_files ) = get_messages( $EMBL_emails_dir, $Submit_Time );

        foreach my $msg ( @msg_files ) {
            open MSG_FILE, $msg or die "Can't open ('$msg') : $!";
            my $first_line = <MSG_FILE>;

            # Is it an EMBL file?
            if ($first_line =~ /^ID   /) {
                # Check for correct end characters
                seek( MSG_FILE, -4, 2 );
                if (<MSG_FILE> =~ m|^//$|) {
                    # Parse the entry and add it to the Requests hash
                    my( @ident );
                    seek( MSG_FILE, 0, 0 );
                    my $embl = Embl->entryFromStream(\*MSG_FILE);
                    $ident[0] = $embl->getLine('EMBL::ID')
                                     ->entryname() or die "Can't get ID from ('$msg')";
                    $ident[1] = $embl->AC()        or die "Can't get AC from ('$msg')";
                    foreach (@ident) {
                        $Request{ $_ } = $embl if exists $Request{ $_ };
                    }
                } else {
                    # File may still be being written to
                    $msg = 0;
                }
            } elsif ($first_line =~ /^$/) {
                while (<MSG_FILE>) {
                    if (/^\* File NUC:(\S+) (sent|not found)\.$/) {
                        $Request{ 'EMAIL_LOG_FILE' } = 1;
                        if ($2 eq 'not found') {
                            $Request{ $1 } = 'FAILED' if exists $Request{ $_ };
                        }
                    }
                }
                # File must be email log, or an EMBL file
                die "Invalid file ('$msg')" unless $Request{ 'EMAIL_LOG_FILE' };
            }
            if ($msg) {
                unlink( $msg ) or die "Can't unlink ('$msg')";
            }
        }
        last unless missing(\%Request);
        sleep 10;
    }

    # Warn about failed requests
    if (my @Failed = grep { $Request{$_} eq 'FAILED' } keys %Request) {
        warn "Failed to get entries for the following requests:\n", map "  $_\n", @Failed;
    }

    delete $Request{'EMAIL_LOG_FILE'};
    return \%Request;
}

sub send_nuc_request {
    my( $address, @request_list ) = @_;
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
    
    foreach (values %$list) {
        return 1 unless $_;
    }
    return;
}

1;

__END__
