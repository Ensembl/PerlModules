
package Hum::FileUtils;

use strict;
use Carp;
use Exporter;
use File::Copy 'copy';
use File::Path 'mkpath';
use Programs 'cksum';
use vars qw( @ISA @EXPORT_OK );

@ISA = ('Exporter');
@EXPORT_OK = qw(
    mirror_copy_dir
    mirror_copy_file
    copy_and_check_file
    identical_file_checksums
    file_checksum
    run_pressdb
    );

sub mirror_copy_dir {
    my( $from, $to ) = @_;
    
    local *FROM;
    opendir FROM, $from or die "Can't opendir('$from') : $!";
    my @utime = (stat($from))[8,9];
    unless (-d $to) {
        mkpath($to);
        die "Can't mkpath('$to')" unless -d $to;
    }
    
    my %dirlist = map {$_, -d "$from/$_" ? 1 : 0}
        grep ! /^\.{1,2}$/,     # Skip "." and ".."
        readdir FROM;
    closedir FROM;
    
    foreach my $f (keys %dirlist) {
        my $from_file = "$from/$f";
        my $to_file   = "$to/$f";
        if ($dirlist{$f}) {
            # File is a directory
            safe_copy_dir($from_file, $to_file);
        } else {
            eval {
                mirror_copy_file($from_file, $to_file);
            };
            warn $@ if $@;
        }
    }
    # Preserve access and modification time on new dir
    utime(@utime, $to);
}

sub mirror_copy_file {
    my( $from_file, $to_file, $u_time ) = @_;
    
    my(@utime);
    # Check that the from file exists
    my $from_size = 0;
    if (-e $from_file) {
        ($from_size,@utime) = (stat(_))[7,8,9];
        confess "Source file '$from_file' is empty\n"
            unless $from_size;
    } else {
        confess "No such source file '$from_file'\n";
    }
    
    my $to_size = (stat($to_file))[7] || 0;
    
    unless ($to_size == $from_size
        and identical_file_checksums($from_file, $to_file)) {
        # Copy file accross, and check copy
        copy_and_check_file($from_file, $to_file);
    }
    
    # Preserve timestamp on file
    @utime = ($u_time, $u_time) if $u_time;
    utime(@utime, $to_file);
}

sub copy_and_check_file {
    my( $from_file, $to_file ) = @_;
    
    # Copy file accross
    copy($from_file, $to_file)
        or confess("Can't copy('$from_file', '$to_file') : $!");
    # Compare checksums after copy
    if (identical_file_checksums($from_file, $to_file)) {
        return 1;
    } else {
        confess("Checksums different after copy('$from_file', '$to_file')");
    }
}

sub identical_file_checksums {
    my( $x, $y ) = @_;
    
    my $x_sum = file_checksum($x);
    my $y_sum = file_checksum($y);
    
    if ($x_sum != -1 and $x_sum == $y_sum) {
        return 1;
    } else {
        return 0;
    }
}

sub file_checksum {
    my( $file ) = @_;
    
    my ($sum) = qx{cksum $file 2>/dev/null} =~ /^(\d+)/;
    return $sum ? $sum : -1;
}

sub run_pressdb {
    my( $build,     # The name of the new fasta database file
        $blast,     # The name for the blast database
        ) = @_;
    
    die "Names for new and old databases are both '$blast'"
        if $blast eq $build;
    
    # Check new database exists
    unless (-s $build) {
        die "Blast database ('$build') missing or empty\n";
    }
    
    # List of extensions for blast files
    my @extn = ('', qw( .csq .nhd .ntb ));
    
    my $pressdb = "pressdb $build 2>&1 |";
    open PRESSDB, $pressdb
        or die "Can't open pipe ('$pressdb') $!";
    my @outLines = <PRESSDB>;
    
    if (close(PRESSDB)) {
        # Rename new files to blast_db name
        foreach (@extn) {
            rename("$build$_", "$blast$_");
        }
        return 1;
    } else {
        # Save BAD file for debugging
        rename( $build, "$blast.BAD" );
        unlink( map "$build$_", @extn );
        die "Creation of blast database '$blast' from '$build' failed:\n",
            @outLines,
            "Bad database file saved as '$blast.BAD'\n";
    }
}


1;

__END__


=head1 NAME - Hum::FileUtils

=head1 DESCRIPTION

Utilities for safely copying files and
directories, and creating blast databases.

=head2 copy_and_check_file

    copy_and_check_file($from_file, $to_file);

Copies C<$from_file> to C<$to_file>.  The program
B<cksum> is used to check that the file is
identical after the copy.  Returns TRUE on
success, but is FATAL on failure.

=head2 mirror_copy_dir

    mirror_copy_dir($from_dir, $to_dir);

Recursively copies all directories and files from
directory C<$from_dir> to C<$to_dir> using
B<mirror_copy_file>.  Like a "tar pipe", access
and modification times of files and directories
are preserved.  All errors are FATAL.

=head2 mirror_copy_file

    mirror_copy_file($from_file, $to_file);
    mirror_copy_file($from_file, $to_file, $utime);

Performs the same function as
B<copy_and_check_file>, but if both C<$from_file>
and C<$to_file> exist, then it compares the
checksums of the two files, and only performs a
copy if they differ.  It also preserves the
access and modification times of the files which
it copies.

Optionally a unix time int C<$utime> can be
provided.  Both C<$from_file> and C<$to_file>
will be stamped with this time.

=head2 identical_file_checksums

    copy_and_check_file($fileA, $fileB);

Returns TRUE if both C<$fileA> and C<$fileB> have
the same checksum (as returned by the B<cksum>
program), but FALSE otherwise.

=head2

    file_checksum($file);

Returns the checksum calculated by the B<cksum>
program on file C<$file>.

=head2 run_pressdb

    run_pressdb('finished.new','finished');

Runs B<pressdb> (which creates a blast version 1
database) on the file C<finished.new>.  If this
succeeds, it is renamed C<finished>, but if it
fails it is moved to C<finished.BAD>.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk
