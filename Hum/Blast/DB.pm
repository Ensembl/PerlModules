
### Hum::Blast::DB

package Hum::Blast::DB;

use strict;
use warnings;
use Carp;
use Digest::MD5;

sub new {
    my( $pkg, $path ) = @_;
    
    my $self = bless {}, $pkg;
    $self->path($path) if $path;
    return $self;
}

sub type {
    my( $self, $type ) = @_;
    
    if ($type) {
        $self->{'_type'} = $type;
    } else {
        $type = $self->{'_type'} or confess "type not set";
    }
    
    if ($type eq 'NUCLEOTIDE' or $type eq 'PROTEIN') {
        return $type;
    } else {
        confess "type must be 'NUCLEOTIDE' or 'PROTEIN' : '$type' is invalid";
    }
}

sub write_access {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        if ($flag) {
            $self->{'_READ_FROM_DISK_'} = 1;
        }
        $self->{'_write_flag'} = $flag ? 1 : 0;
    }
    return $self->{'_write_flag'};
}

sub db_list {
    return @_;
}

sub path {
    my( $self, $path ) = @_;
    
    if ($path) {
        $self->{'_path'} = $path;
    } else {
        return $self->{'_path'} || confess "path not set";
    }
}

sub build_path {
    my( $self, $build_path ) = @_;
    
    if ($build_path) {
        $self->{'_build_path'} = $build_path;
    } else {
        return $self->{'_build_path'} || confess "build_path not set";
    }
}

sub db_name {
    my( $self, $db_name ) = @_;
    
    # Set or get db_name
    if ($db_name) {
        $self->{'_db_name'} = $db_name;
    } else {
        $db_name = $self->{'_db_name'};
    }
    
    # ... or get it from the path
    unless ($db_name) {
        $db_name = $self->_file_name($self->path);
    }
    
    return $db_name;
}

# Could use this if we start building indices for
# NCBI Blast 2 only.
#sub blast_version {
#    my( $self, $blast_version ) = @_;
#    
#    if ($blast_version) {
#        $self->{'_blast_version'} = $blast_version;
#    } else {
#        $blast_version = $self->{'_blast_version'};
#    }
#    if ($blast_version == 1) {
#        return $blast_version;
#    }
#    elsif ($blast_version == 2 or ! defined $blast_version) {
#        return 2;   # Blast version 2 is the default
#    }
#    else {
#        confess "Illegal blast_version '$blast_version'";
#    }
#}

{
    my( @two_digit ) = ('00'..'31');

    sub _ace_date {
        my( $self, $time ) = @_;

        $time ||= time;

        my($mday,$mon,$year) = (localtime($time))[3,4,5];
        $year += 1900;
        ($mday,$mon) = @two_digit[$mday,$mon+1];
        return "$year-$mon-$mday";
    }
}

sub _device_number {
    my( $self, $path ) = @_;
    
    my $dir = $self->_dir_name($path);
    my $dev_num = (stat($dir))[0]
        or confess "Can't get device number for '$path' (dir='$dir')";
    return $dev_num;
}

sub _dir_name {
    my( $self, $path ) = @_;
    
    my ($dir) = $path =~ m{^(.*)/};
    $dir = '.' unless defined $dir;
    #warn "Returning dir='$dir'\n";
    return $dir;
}

sub _file_name {
    my( $self, $path ) = @_;
    
    my ($file) = $path =~ m{([^/]+)$}
        or confess "Can't parse file from '$path'";
    return $file;
}

sub do_indexing {
    my( $self ) = @_;
    
    confess "Can't index: Don't have write access"
        unless $self->write_access;

    # These three methods all fatal if not set:
    my $type    = $self->type;
    my $build   = $self->build_path;
    my $path    = $self->path;
    
    confess "Names for new and old databases are both '$path'"
        if $path eq $build;
    unless ($self->_device_number($path) == $self->_device_number($build)) {
        confess "Can't index '$path' and '$build' are on different filesystems";
    }
    
    # Make a title for the blast database
    my $title = $self->_make_db_title;
    
    my( 
        $blast_1_indexer,   # "pressdb" or "setdb"
        $is_protein,        # -p argument to "formatdb" : ("T" or "F")
        );
    if ($type eq 'NUCLEOTIDE') {
        $blast_1_indexer = 'pressdb';
        $is_protein = 'F';
    }
    elsif ($type eq 'PROTEIN') {
        $blast_1_indexer = 'setdb';
        $is_protein = 'T';
    }
    else {
        confess "bad blast db type '$type'";
    }
    
    # Check new database exists
    unless (-e $build) {
        die "No such fasta database '$build'\n";
    }
    
    my $blast_1_command = "$blast_1_indexer -t '$title' $build 2>&1 |";
    my $blast_2_command = "formatdb -t '$title' -p $is_protein -i $build -l /dev/null 2>&1 |";
    my( @outLines );
    my $error_flag = 0;
    foreach my $pipe ($blast_1_command, $blast_2_command) {
        local *PIPE;
        #warn "Running: '$pipe'";
        open PIPE, $pipe or confess "Can't open pipe ('$pipe') : $!";
        while (<PIPE>) {
            push(@outLines, $_);
        }
        close PIPE or $error_flag++;
    }
    
    if ($error_flag) {
        confess "Creation of blast database '$path' from '$build' failed:\n",
            @outLines;
    } 
}

sub rename_build_to_path {
    my( $self ) = @_;
    
    confess "Can't rename: Don't have write access"
        unless $self->write_access;
    
    my $type     = $self->type;
    my $build    = $self->build_path;
    my $path = $self->path;

    my( @extn );
    if ($type eq 'NUCLEOTIDE') {
        @extn = ('', qw{ .nhd .ntb .csq .nhr .nin .nsq });
    }
    elsif ($type eq 'PROTEIN') {
        @extn = ('', qw{ .ahd .atb .bsq .phr .pin .psq });
    }
    else {
        confess "bad blast db type '$type'";
    }
    
    # Rename new files to blast_db name
    foreach my $ex (@extn) {
        my( $from, $to ) = ("$build$ex", "$path$ex");
        rename($from, $to)
            or confess "Error renaming '$from' to '$to' : $!";
    }
    return 1;
}

sub _make_db_title {
    my( $self ) = @_;
    
    my @title = ($self->db_name);
    
    my $date      = $self->_ace_date;
    push(@title, "date=$date");
    
    my $file_size = $self->actual_build_file_size;
    push(@title, "size=$file_size");
    
    if (my $version = $self->version) {
        push(@title, "version=$version");
    }
    
    if (my @part = $self->part) {
        my $part_def = join('of', @part);
        push(@title, "part=$part_def");
    }
    
    my $md5 = $self->actual_build_md5;
    push(@title, "md5=$md5");
    
    return join('|', @title);
}

sub actual_file_size {
    my( $self ) = @_;
    
    my $path = $self->path;
    $self->{'_actual_file_size'} ||= -s $path;
    return $self->{'_actual_file_size'};
}

sub actual_build_file_size {
    my( $self ) = @_;
    
    my $path = $self->build_path;
    return -s $path;
}

sub date {
    my( $self, $date ) = @_;
    
    $self->_read_db_details;
    if ($date) {
        $self->{'_date'} = $date;
    }
    return $self->{'_date'};
}

sub version {
    my( $self, $version ) = @_;
    
    $self->_read_db_details;
    if ($version) {
        $self->{'_version'} = $version;
    }
    return $self->{'_version'};
}

sub md5 {
    my( $self, $md5 ) = @_;
    
    $self->_read_db_details;
    if ($md5) {
        $self->{'_md5'} = $md5;
    }
    return $self->{'_md5'};
}

sub actual_md5 {
    my( $self ) = @_;
    
    my $file = $self->path;
    return $self->_calculate_md5_digest($file);
}

sub actual_build_md5 {
    my( $self ) = @_;
    
    my $file = $self->build_path;
    return $self->_calculate_md5_digest($file);
}

sub _calculate_md5_digest {
    my( $self, $file ) = @_;
    
    local *FASTA_FILE;
    open FASTA_FILE, $file
        or confess "Can't read '$file' : $!";
    my $md5 = Digest::MD5->new;
    $md5->addfile(\*FASTA_FILE);
    my $hex = $md5->hexdigest
        or confess "Failed to genereate hexdigest";
    close FASTA_FILE;
    return $hex;
}

sub size {
    my( $self, $size ) = @_;
    
    $self->_read_db_details;
    if ($size) {
        $self->{'_size'} = $size;
    }
    return $self->{'_size'};
}

sub part {
    my( $self, $i, $n ) = @_;
    
    $self->_read_db_details;

    if ($i and my ($j,$k) = $i =~ /^(\d+)of(\d+)$/) {
        ($i,$n) = ($j,$k);
    }
    
    if ($i or $n) {
        if (grep ! /^\d+$/, ($i, $n)) {
            confess "expected two integers, got '$i' and '$n'"
        }
        if ($i > $n) {
            confess "Part number '$i' is greater than number of parts '$n'";
        }
        $self->{'_part'} = [$i, $n];
    }

    if (my $d = $self->{'_part'}) {
        return @$d;
    } else {
        return;
    }
}

sub _read_db_details {
    my( $self ) = @_;
    
    return if $self->{'_READ_FROM_DISK_'};
    $self->{'_READ_FROM_DISK_'} = 1;
    my $title = $self->_read_db_title;
    my( $db_name, @extras ) = split /\|/, $title;
    confess "Failed to get db_name" unless $db_name;
    $self->db_name($db_name);
    foreach my $ex (@extras) {
        my ($field, $value) = split /=/, $ex, 2;
        $self->$field($value);
    }
}

sub check_file_size {
    my( $self ) = @_;
    
    my $size   = $self->size;
    my $actual = $self->actual_file_size;
    unless ($size == $actual) {
        confess "Database file should be '$size' bytes, but is actually '$actual' bytes";
    }
}

sub check_md5_digest {
    my( $self ) = @_;
    
    my $digest = $self->md5;
    my $actual = $self->actual_md5;
    unless ($digest eq $actual) {
        confess "md5 digest from file '$actual' doesn't match md5 stored in index '$digest'";
    }
}

sub _read_db_title {
    my( $self ) = @_;
    
    my $file = $self->path;
    my $type = $self->type;
    
    # We only look at the version 1 index files,
    # which are used by blast 1.4, and wublast
    if ($type eq 'NUCLEOTIDE') {
        $file .= '.ntb';    # .nin in NCBI blast 2
    } else {
        $file .= '.atb';    # .ain in NCBI blast 2
    }
    if (my $title = $self->_get_db_title($file)) {
        return $title;
    } else {
        confess "Can't get db_title from file '$file'";
    }
}


# blast index files begin with three 32bit longs
# in network (big endian) order.  The third of them
# gives the length of the title in bytes, and the
# title starts immediately after the the third long.
sub _get_db_title {
    my( $self, $index_file ) = @_;
    local *INDX;
    
    # Open read-only (mode 0)
    if (sysopen INDX, $index_file, 0) {
        
        # Skip the first two "longs"
        seek(INDX, 8, 0) or die "Can't seek : $!";
        
        my( $title_length_long );
        $self->_safe_sysread(\*INDX, \$title_length_long, 4);
        my ($title_length) = unpack('N', $title_length_long);
        #warn "Title length = $title_length\n";
        
        # .ntb and .atb files include a null byte in the
        # length of the title (.nin and .ain don't).
        $title_length--;
        
        my( $title );
        $self->_safe_sysread(\*INDX, \$title, $title_length);
        #warn "DB title = $title\n";
        return $title;
    } else {
        return;
    }
}

sub _safe_sysread {
    my( $self, $fh, $var, $length ) = @_;
    
    my( $len );
    while ($len = sysread $fh, $$var, $length) {
        if (defined $len) {
            #warn "Read $len bytes\n";
            last;
        } else {
            next if $! =~ /^Interupted/;
            confess "System read error : $!";
        }
    }
    return $len;
}


1;

__END__

=head1 NAME - Hum::Blast::DB

=head1 SYNOPISIS

    ### Indexing a blast database ###
    my $blast_db = Hum::Blast::DB->new;
    $blast_db->db_name('human_finished');
    $blast_db->write_access(1); # To allow indexing
    $blast_db->type('NUCLEOTIDE');
    
    # Set the name of the database file on success:
    $blast_db->path('/lustre/cbi4/work1/humpub/blastdb/finished');
    
    # Set the name of the new fasta file
    $blast_db->build_path('/lustre/cbi4/work1/humpub/blastdb/finished.build');
    
    # Index for both Blast 1.4/wublast and NCBI Blast 2
    # (This is fatal on failure.)
    $blast_db->do_indexing;
    
    ### Read info from an existing blast db ###
    my $blast_db = Hum::Blast::DB->new;
    $blast_db->path('/lustre/cbi4/work1/pubseq/dbEST-2');
    
    # Get the date this was
    my $date = $blast_db->date;
    
    # This is fatal if the size stored in the index doesn't
    # match the actual size of the fasta DB file
    $blast_db->check_file_sizes;

=head1 DESCRIPTION

A Hum::Blast::DB object represents a single blast
database (a fasta file containing multiple
sequences, plus indexes for Blast 1, wublast and
NCBI blast).  It has methods for creating the
indexes, putting standard information into the
database title, and retrieving this information
from an existing index.

=head1 METHODS

=over4

=item B<new>

Returns a new Hum::Blast::DB object.

=item B<type>

    $blast_db->type('NUCLEOTIDE');
    my $type = $blast_db->type;

Must be set, so that the object knows which blast
indexing commands to use, and the names of the
index files.  Allowed values are B<NUCLEOTIDE>
and B<PROTEIN>.

=item B<write_access>

    $blast_db->write_access(1);

Set write_access to TRUE if you want to index a
blast database.

=item B<path>

    $blast_db->path('/data/blastdb/finished');

Must be set.  This is the path of the
existing indexed database, or the path of the
database once indexing is complete.

=item B<build_path>

    $blast_db->build_path('/data/blastdb/finished.build');

The name of the file to be indexed.  If indexing
is successful, it (and its index files) are
renamed to the value of B<path>.  This file
must be on the same device as B<path>.

=item B<db_name>

    $blast_db->db_name('human_finished');

The name to use for the database.  If not set, it
uses the last element of the path.

=item B<do_indexing>

Indexes the fasta file pointed to by
B<build_path>, producing indexes for all flavours
of Blast.  Any errors encountered are fatal.

=item B<rename_build_to_path>

Renames the blast databasefiles to the root given
in B<path>.

=item B<actual_file_size>

Returns the actual size of the database fasta
file.

=item B<actual_build_file_size>

Returns the actual size of the build database
fasta file.

=item B<actual_md5>

Returns the md5 digest of the database fasta
file.  This is a hexadecimal string, and is
calculated by the B<Digest::MD5> module.

=item B<actual_build_md5>

Returns the md5 digest of the build database
fasta file.  This is a hexadecimal string, and is
calculated by the B<Digest::MD5> module.

=item B<date>

Returns the current date with write_access, or
the date the db was built on without
write_access.

=item B<version>

Returns the versin of the databse (if set).

=item B<size>

Returns the stored file size.

=item B<md5>

Returns the stored md5 digest for the file.

=item B<part>

Returns two integers, the first is the current
part, and the second the total number of parts,
if the DB is part of a mulit-part database.

=item B<check_file_size>

Checks that the size of the fasta DB file stored
in the index file matches the acutal DB file. 
Fatal if they don't match.

=item B<check_md5_digest>

Checks that the md5 digest of the file matches
the value stored in the index.  Fatal if they
don't match.

=item B<db_list>

Returns itself in list context.  Provided for
compatability with B<Hum::Blast::DB::Multi>.

=back

=head1 SEE ALSO

The L<Hum::Blast::DB::Multi> module.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

