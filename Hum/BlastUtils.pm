
### Hum::BlastUtils

package Hum::BlastUtils;

use strict;
use warnings;
use Carp;
use Exporter;
use vars qw{ @ISA @EXPORT_OK };
@ISA = 'Exporter';
@EXPORT_OK = qw{
    make_nucleotide_blast_indices
    make_protein_blast_indices
    blast_db_title
    blast_db_version
    blast_nucleotide_db_title
    blast_nucleotide_db_version
    blast_protein_db_title
    blast_protein_db_version
    };

sub make_nucleotide_blast_indices {
    return _make_blast_indices('nucleotide', @_ );
}

sub make_protein_blast_indices {
    return _make_blast_indices('protein', @_ );
}

sub _make_blast_indices {
    my( $type,      # "nucleotide" or "protein"
        $blast,     # The name for the blast database
        $build,     # The name of the new fasta database file
        @title_elements,
        ) = @_;
    
    die "Names for new and old databases are both '$blast'"
        if $blast eq $build;
    
    # Make a title for the blast database
    my ($name) = $blast =~ m{([^/]+)$};
    my $title = join('|', $name, ace_date(), @title_elements);
    
    my( @extn,              # List of blast db extensions
        $blast_1_indexer,   # "pressdb" or "setdb"
        $is_protein,        # -p argument to "formatdb" : ("T" or "F")
        );
    if ($type eq 'nucleotide') {
        @extn = ('', qw( .nhd .ntb .csq .nhr .nin .nsq ));
        $blast_1_indexer = 'pressdb';
        $is_protein = 'F';
    }
    elsif ($type eq 'protein') {
        @extn = ('', qw( .ahd .atb .bsq .phr .pin .psq ));
        $blast_1_indexer = 'setdb';
        $is_protein = 'T';
    }
    else {
        confess "'$type' must be either 'nucleotide' or 'protein'";
    }
    
    # Check new database exists
    unless (-e $build) {
        die "No such fasta database '$build'\n";
    }
    
    my $blast_1_command = "$blast_1_indexer -t $title $build 2>&1 |";
    my $blast_2_command = "formatdb -t $title -p $is_protein -i $build -l /dev/null 2>&1 |";
    my( @outLines );
    my $error_flag = 0;
    foreach my $pipe ($blast_1_command, $blast_2_command) {
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


sub blast_db_title {
    my( $db_file ) = @_;
    
    return _get_db_title_extn($db_file, qw{ nin ntb pin atb });
}

sub blast_db_version {
    my( $db_file ) = @_;
    
    return _get_db_version_extn($db_file, qw{ nin ntb pin atb });
}

sub blast_nucleotide_db_title {
    my( $db_file ) = @_;
    
    return _get_db_title_extn($db_file, qw{ nin ntb });
}

sub blast_nucleotide_db_version {
    my( $db_file ) = @_;
    
    return _get_db_version_extn($db_file, qw{ nin ntb });
}

sub blast_protein_db_title {
    my( $db_file ) = @_;
    
    return _get_db_title_extn($db_file, qw{ pin atb });
}

sub blast_protein_db_version {
    my( $db_file ) = @_;
    
    return _get_db_version_extn($db_file, qw{ pin atb });
}

sub _get_db_version_extn {
    my( $db_file, @extn ) = @_;
    
    my ($db_name) = $db_file =~ m{([^/]+)$};
    my $title = _get_db_title_extn($db_file, @extn);
    my ($version) = $title =~ /^([^\|]+)\|([^\|]+)/;
    if ($version) {
        return $version;
    } else {
        confess "Can't get blast db version for '$db_name'";
    }
}

sub _get_db_title_extn {
    my( $db_file, @extn ) = @_;
    
    my( $title );
    foreach my $ext (@extn) {
        last if $title = _get_db_title("$db_file.$ext");
    }
    if ($title) {
        return $title;
    } else {
        confess "Can't get blast db title for '$db_file' using file extensions (",
            join(',', map "'$_'", @extn), ")";
    }
}

# blast index files begin with three 32bit longs
# in network (big endian) order.  The third of them
# gives the length of the title in bytes, and the
# title starts immediately after the the third long.
sub _get_db_title {
    my( $index_file ) = @_;
    local *INDX;
    
    my $last_two_characters = substr($index_file, (length($index_file) - 2), 2);
    
    # Open read-only (mode 0)
    if (sysopen INDX, $index_file, 0) {
        
        # Skip the first two "longs"
        seek(INDX, 8, 0) or die "Can't seek : $!";
        
        my( $title_length_long );
        _safe_sysread(\*INDX, \$title_length_long, 4);
        my ($title_length) = unpack('N', $title_length_long);
        #warn "Title length = $title_length\n";
        
        # .atb and .ntb files include a null
        # byte in the length of the title
        $title_length-- if $last_two_characters eq 'tb';
        
        my( $title );
        _safe_sysread(\*INDX, \$title, $title_length);
        #warn "DB title = $title\n";
        return $title;
    } else {
        return;
    }
}

sub _safe_sysread {
    my( $fh, $var, $length ) = @_;
    
    my( $len );
    while ($len = sysread $fh, $$var, $length) {
        if (defined $len) {
            #warn "Read $len bytes\n";
            last;
        } else {
            next if $! =~ /^Interupted/;
            die "System read error : $!";
        }
    }
    return $len;
}



1;

__END__

=head1 NAME - Hum::BlastUtils

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

