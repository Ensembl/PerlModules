
=pod

=head1 NAME Hum::EBI_FTP

=head1 DESCRIPTION

Inherits from I<Net::FTP>, and provides an
interface for putting embl files on the EBI ftp
site.

=cut

package Hum::EBI_FTP;

use strict;
use warnings;
use Net::FTP;
use Carp;

use base qw( Net::FTP );

sub new {
    my ($pkg, $host) = @_;

    $host ||= 'ftp-private.ebi.ac.uk';
    my $ftp = Net::FTP->new($host, Passive => 1)
      or confess "Can't connect() to '$host'; $@";
    $ftp->login() # password is in ~/.netrc
      or confess "Can't login() to '$host'; ", $ftp->message;
    $ftp->cwd('/YUFSjj8seagh6J4iGCsc/to_ena') # special directory where we put sequence
      or confess "Can't change working directory to depository; ", $ftp->message;

    return bless $ftp, $pkg;
}

sub put_project {
    my( $ftp, $project_name, $embl_file_name ) = @_;
    
    my $remote = $ftp->make_file_name($project_name);
    unless ($ftp->put($embl_file_name, $remote)) {
        $ftp->delete($remote) or warn "Couldn't delete '$remote'";
        confess "put('$embl_file_name', '$remote') failed : $@";
    }
    return $remote;
}

sub make_file_name {
    my( $ftp, $name ) = @_;
    
    for (my $cyc = 1; $cyc < 300; $cyc++) {
        my $file_name = ebi_time_string(). "_$name";
        unless (grep {$file_name eq $_} $ftp->ls()) {
            return $file_name;
        }
        sleep 2;
    }
    confess "Got stuck in loop trying to generate unique file name";
}

sub ebi_time_string {
    my $time = shift || time;
    
    my( $sec, $min, $hour, $mday, $mon, $year ) = (localtime($time))[0..5];
    ($sec, $min, $hour, $mday, $mon) =
        ('00'..'59')[$sec, $min, $hour, $mday, $mon + 1];
    $year += 1900;
    return "$year$mon$mday$hour$min$sec";
}

1;

__END__

=head1 SYNOPSIS

    my $ebi_ftp = Hum::EBI_FTP->new();
    $ebi_ftp->put_project( $project_name, $file_name );

=head1 METHODS

Methods are fatal on failure.

=over 4

=item new

Returns a new ftp connection to 'ftp1.ebi.ac.uk',
having logged in with the B<login> and
B<password> specified in the I<~/.netrc> file. 
(A differnt machine name may be provided as an
argument to new.)

=item put_project

The first argument to put_project is the name of
the project as known by the EBI, and the second
is the name of the file on the local filesystem. 
The name of the file on the remote machine will
be of the form:

    YYYYMMDDHHMMSS_Projectname

and is returned by the method.  The name is
generated automatically, and is checked to make
sure that it is unique before transfer.

=back

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>
