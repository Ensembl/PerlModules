
### Hum::Blast::DB

package Hum::Blast::DB;

use strict;
use Carp;

sub new {
    my( $pkg, $filename ) = @_;
    
    my $self = bless {}, $pkg;
    $self->filename($filename) if $filename;
    return $self;
}

sub write_access {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        if ($flag) {
            $self->{'_READ_FROM_DISK_'} = 1;
        }
        $self->{'_flag'} = $flag ? 1 : 0;
    }
    return $self->{'_flag'};
}

sub filename {
    my( $self, $filename ) = @_;
    
    if ($filename) {
        $self->{'_filename'} = $filename;
    } else {
        return $self->{'_filename'} || confess "filename not set";
    }
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

sub db_name {
    my( $self, $db_name ) = @_;
    
    # Set or get db_name
    if ($db_name) {
        $self->{'_db_name'} = $db_name;
    } else {
        $db_name = $self->{'_db_name'};
    }
    
    # ... or get it from the filename
    unless ($db_name) {
        my $filename = $self->filename;
        ($db_name) = $filename =~ m{([^/]+)$};
        confess "Couldn't make db_name from filename '$filename'" 
            unless $db_name;
    }
    
    return $db_name;
}

sub build_filename {
    my( $self, $build_filename ) = @_;
    
    if ($build_filename) {
        $self->{'_build_filename'} = $build_filename;
    } else {
        return $self->{'_build_filename'} || confess "build_filename not set";
    }
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
    my( $self, $filename ) = @_;
    
    my ($dir) = $filename =~ m{^(.*/)};
    $dir = '.' unless defined $dir;
    my $dev_num = (stat($dir))[0]
        or confess "Can't get device number for '$filename' (dir='$dir')";
    return $dev_num;
}

sub do_indexing {
    my( $self ) = @_;
    
    confess "Can't index: Don't have write access"
        unless $self->write_access;

    # These three methods all fatal if not set:
    my $type     = $self->type;
    my $build    = $self->build_filename;
    my $filename = $self->filename;
    
    confess "Names for new and old databases are both '$filename'"
        if $filename eq $build;
    unless ($self->_device_number($filename) == $self->_device_number($build)) {
        confess "Can't index '$filename' and '$build' are on different filesystems";
    }
    
    # Make a title for the blast database
    my $title = $self->_make_db_title;
    
    my( @extn,              # List of blast db extensions
        $blast_1_indexer,   # "pressdb" or "setdb"
        $is_protein,        # -p argument to "formatdb" : ("T" or "F")
        );

    if ($type eq 'NUCLEOTIDE') {
        @extn = ('', qw( .nhd .ntb .csq .nhr .nin .nsq ));
        $blast_1_indexer = 'pressdb';
        $is_protein = 'F';
    }
    elsif ($type eq 'PROTEIN') {
        @extn = ('', qw( .ahd .atb .bsq .phr .pin .psq ));
        $blast_1_indexer = 'setdb';
        $is_protein = 'T';
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
    
    my $bad_db = "$filename.BAD";
    if ($error_flag) {
        # Save BAD file for debugging
        rename( $build, $bad_db  );
        unlink( map "$build$_", @extn );
        die "Creation of blast database '$filename' from '$build' failed:\n",
            @outLines,
            "Bad database file saved as '$bad_db'\n";
    } else {
        # Rename new files to blast_db name
        foreach (@extn) {
            rename("$build$_", "$filename$_");
        }
        unlink($bad_db);
        return 1;
    }    
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
    
    if (my @parts = $self->parts) {
        my $part_def = join('of', @parts);
        push(@title, "parts=$part_def");
    }
    
    return join('|', @title);
}

sub actual_file_size {
    my( $self ) = @_;
    
    my $filename = $self->filename;
    return -s $filename;
}

sub actual_build_file_size {
    my( $self ) = @_;
    
    my $filename = $self->build_filename;
    return -s $filename;
}

sub date {
    my( $self, $date ) = @_;
    
    $self->read_db_details;
    if ($date) {
        $self->{'_date'} = $date;
    }
    return $self->{'_date'};
}

sub version {
    my( $self, $version ) = @_;
    
    $self->read_db_details;
    if ($version) {
        $self->{'_version'} = $version;
    }
    return $self->{'_version'};
}

sub size {
    my( $self, $size ) = @_;
    
    $self->read_db_details;
    if ($size) {
        $self->{'_size'} = $size;
    }
    return $self->{'_size'};
}

sub parts {
    my( $self, $i, $n ) = @_;
    
    $self->read_db_details;

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
        $self->{'_parts'} = [$i, $n];
    }

    if (my $d = $self->{'_parts'}) {
        return @$d;
    } else {
        return;
    }
}

sub check_file_size {
    my( $self ) = @_;
    
    my $size = $self->size;
    my $actual = $self->actual_file_size;
    unless ($size == $actual) {
        confess "Database file should be '$size' bytes, but is actually '$actual' bytes";
    }
}

sub read_db_details {
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

sub _read_db_title {
    my( $self ) = @_;
    
    my $file = $self->filename;
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
    $blast_db->db_name('dbEST');
    $blast_db->write_access(1); # To allow indexing
    $blast_db->parts(2,6);      # File 2 of 6
    $blast_db->type('NUCLEOTIDE');
    
    # Set the name of the database file on success:
    $blast_db->filename('/nfs/disk100/pubseq/dbEST-2');
    
    # Set the name of the new fasta file
    $blast_db->build_filename('/nfs/disk100/pubseq/build/dbEST-2');
    
    # Index for both 1.4/wublast and NCBI Blast 2
    # (This is fatal on failure.)
    $blast_db->do_indexing;
    
    
    ### Read info from an existing blast db ###
    my $blast_db = Hum::Blast::DB->new;
    $blast_db->filename('/nfs/disk100/pubseq/dbEST-2');
    
    # Get the date this was
    my $date = $blast_db->date;
    
    # This is fatal if the 
    $blast_db->check_file_sizes;
    

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

