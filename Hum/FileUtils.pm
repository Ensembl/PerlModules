
package Hum::FileUtils;

use strict;
use warnings;
use Carp;
use Exporter;
use File::Copy 'copy';
use File::Path 'mkpath', 'rmtree';
use Sys::Hostname 'hostname';
use Hum::Programs 'cksum';
use vars qw( @ISA @EXPORT_OK );

@ISA = ('Exporter');
@EXPORT_OK = qw(
    ace_date
    paranoid_print
    delete_blast_db
    mirror_copy_dir
    mirror_copy_file
    copy_and_check_file
    identical_file_checksums
    file_checksum
    run_pressdb
    system_with_separate_stdout_and_stderr_using_sed
    );

sub paranoid_print {
    my( $dest_dir, $file, @data ) = @_;
    
    my $host          = hostname();
    my $tmp_file      = "$file.$$.$host.copy-tmp";
    my $tmp_path      =      "/tmp/$tmp_file";
    my $tmp_dest_path = "$dest_dir/$tmp_file";
    my $dest_path     = "$dest_dir/$file";
    
    local *TMP_PATH;
    open TMP_PATH, "> $tmp_path"
        or confess "Can't write to '$tmp_path' : $!";
    print TMP_PATH @data
        or confess "Error printing to '$tmp_path' : $!";
    close TMP_PATH
        or confess "Error printing to '$tmp_path' : $!";
    copy_and_check_file($tmp_path, $tmp_dest_path);
    unlink($tmp_path);
    rename($tmp_dest_path, $dest_path)
        or confess "Error renaming '$tmp_dest_path' to '$dest_path' : $!";
    return 1;
}

sub mirror_copy_dir {
    my( $from, $to, $flag_make_link ) = @_;

    # if flag_make_link is set, and a file is a link
    # makes a new link rather than a duplicate file
    
    my %from_dir = dir_hash($from);
    my @utime = (stat($from))[8,9];
    unless (-d $to) {
        mkpath($to);
        die "Can't mkpath('$to')" unless -d $to;
    }
    
    foreach my $f (keys %from_dir) {
        my $from_file = "$from/$f";
        my $to_file   = "$to/$f";
        if ($from_dir{$f} eq 'd') {
            # File is a directory
            mirror_copy_dir($from_file, $to_file, $flag_make_link );
        } else {
            mirror_copy_file($from_file, $to_file, 0, $flag_make_link );
        }
    }
    
    my %to_dir = dir_hash($to);
    while (my($f, $type) = each %to_dir) {
        unless($from_dir{$f}) {
            remove_entry("$to/$f", $type);
        }
    }
    
    # Preserve access and modification time on new dir
    utime(@utime, $to);
}

sub remove_entry {
    my( $path, $type ) = @_;
    
    if ($type eq 'f') {
        unlink($path);
    }
    elsif ($type eq 'd') {
        rmtree($path);
    }
    else {
        confess("Unknown type '$type'");
    }
}

sub dir_hash {
    my( $dir ) = @_;
    
    local *DIR;
    opendir(DIR, $dir) or die "Can't opendir('$dir') : $!";
    my %dirhash = map {$_, (-d "$dir/$_") ? 'd' : 'f'}
        grep ! /^\.{1,2}$/,     # Skip "." and ".."
        readdir DIR;
    closedir DIR;
    return %dirhash;
}

sub mirror_copy_file {
    my( $from_file, $to_file, $u_time, $flag_make_link ) = @_;
    
    my(@utime);
    # Check that the from file exists
    # (if file is a link then missing file generates a warning only)
    my $from_size = 0;

    # set flag if file is a link and link creating mode
    my $flag_link;
    if ($flag_make_link && -l $from_file) {
	$flag_link=1;
    }

    my $flag_link_missing;
    if(!-e $from_file) {
	if($flag_link){
	    # warning only - perfectly valid to copy dead links
	    carp "Source file of link '$from_file' missing - continue\n";
	    $flag_link_missing=1;
	}else{
	    # fatal - disk error or disk change
	    confess "No such source file '$from_file'\n";
	}
    }

    if($flag_link){
	# don't check file if this is a link, but make an identical link
	# on remote file system
	# NOTE THIS WILL NOT WORK WITH SOME RELATIVE LINKS
	# but this is tested for and fails
	my $link=readlink($from_file);
	symlink($link,$to_file);
	if(!$flag_link_missing && !-e $to_file){
	    # fatal - link copy failed
	    confess "Link no longer points to source file '$from_file'\n";
	}
    } else {
	# compare previous file, if exists
        ($from_size,@utime) = (stat(_))[7,8,9];
    
	my $to_size = (stat($to_file))[7] || 0;
	
	# don't think this should ever happen
	if ($from_size == 0 and $from_size != $to_size) {
	    confess "Source file '$from_file' is empty\n",
            "but '$to_file' is not ('$to_size')";
	}
    
	unless ($to_size == $from_size
		and identical_file_checksums($from_file, $to_file)) {
	    # Copy file across, and check copy
	    copy_and_check_file($from_file, $to_file);
	}
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

sub system_with_separate_stdout_and_stderr_using_sed {
	my ($cmd) = @_;
	
	my @all = `($cmd | sed -e 's/^/stdout: /') 2>&1`;
	my (@outlines, @errlines);
	for (@all) { push @{ s/stdout: // ? \@outlines : \@errlines }, $_ }
	
	return(\@outlines, \@errlines);
}

sub file_checksum {
    my( $file ) = @_;
    
    my ($sum) = qx{cksum $file 2>/dev/null} =~ /^(\d+)/;
    return defined($sum) ? $sum : -1;
}

{
    # List of extensions for blast files
    my @extn = ('', qw( .csq .nhd .ntb .nhr .nin .nsq ));

    sub run_pressdb {
        my( $build,     # The name of the new fasta database file
            $blast,     # The name for the blast database
            ) = @_;

        my ($name) = $blast =~ m{([^/]+)$};
        $name = "$name.". ace_date();

        die "Names for new and old databases are both '$blast'"
            if $blast eq $build;

        # Check new database exists
        unless (-e $build) {
            die "No such fasta database '$build'\n";
        }

        my @extn = ('', qw( .csq .nhd .ntb .nhr .nin .nsq ));

        my $pressdb  = "pressdb -t $name $build 2>&1 |";
        my $formatdb = "formatdb -t $name -p F -i $build -l /dev/null 2>&1 |";
        my( @outLines );
        my $error_flag = 0;
        foreach my $pipe ($pressdb, $formatdb) {
            local *PIPE;
            open PIPE, $pipe or confess "Can't open pipe ('$pipe') : $!";
            while (<PIPE>) {
                push(@outLines, $_);
            }
            close PIPE or $error_flag++;
        }

        my $bad_db = "$blast.BAD";
        if ($error_flag) {
            # Save BAD file for debugging
            rename( $build, $bad_db  );
            unlink( map "$build$_", @extn );
            die "Creation of blast database '$blast' from '$build' failed:\n",
                @outLines,
                "Bad database file saved as '$blast.BAD'\n";
        } else {
            # Rename new files to blast_db name
            foreach (@extn) {
                rename("$build$_", "$blast$_");
            }
            unlink($bad_db);
            return 1;
        }
    }

    sub delete_blast_db {
        my( $db_file ) = @_;
        
        return unlink( map "$db_file$_", @extn );
    }
}

{
    my( @two_digit ) = ('00'..'31');
    sub ace_date {
        my( $time ) = @_;

        $time ||= time;

        my($mday,$mon,$year) = (localtime($time))[3,4,5];
        $year += 1900;
        ($mday,$mon) = @two_digit[$mday,$mon+1];
        return "$year-$mon-$mday";
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
are preserved.  Any directories or files present
in C<$from_dir> but not in C<$to_dir> will be
removed from C<$to_dir>.  All errors are FATAL.

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

=head2 system_with_separate_stdout_and_stderr_using_sed

	my ($stdout_listref, $stderr_listref) = system_with_separate_stdout_and_stderr_using_sed($command);
	
Implementation of the method for separating stdout and sterr of a 
system command found in section 16.9 of the Perl Cookbook.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk
