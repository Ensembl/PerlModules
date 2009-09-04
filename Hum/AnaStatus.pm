
### Hum::AnaStatus

package Hum::AnaStatus;

use strict;
use warnings;
use vars qw{ @ISA @EXPORT_OK };
use Carp;
use Exporter;
use File::Path 'mkpath';
use Hum::Conf qw(HUMPUB_ROOT SPECIES_ANALYSIS_ROOT);
use Hum::Submission qw{ prepare_statement };

@ISA = ('Exporter');
@EXPORT_OK = qw{
    add_seq_id_dir 
    add_new_sequence_entry
    set_ana_sequence_not_current
    annotator_full_name
    date_dir
    make_ana_dir_from_species_chr_seqname_time
    set_annotator_uname
    get_annotator_uname
    
    is_active_task
    list_active_tasks
    active_task_count
    };

sub add_seq_id_dir {
    my( $seq_id, $ana_dir, $db_prefix ) = @_;

    $db_prefix ||= '';

    my $sth = prepare_statement(qq{
        INSERT ana_sequence( ana_seq_id
          , is_current
          , seq_id
          , analysis_directory
          , db_prefix)
        VALUES (NULL,'Y', $seq_id, '$ana_dir', '$db_prefix')
        });
    $sth->execute;
    my $ana_seq_id = $sth->{'mysql_insertid'};

    make_status_entered($ana_seq_id);
}

sub make_status_entered {
    my( $ana_seq_id ) = @_;

    # status_id of 1 = "Entered"
    my $sth = prepare_statement(qq{
        INSERT ana_status( ana_seq_id
          , is_current
          , status_date
          , status_id)
        VALUES ($ana_seq_id,'Y',NOW(),1)
        });
    $sth->execute;
}

sub add_new_sequence_entry {
    my( $seq_name, $seq_version, $cksum, $length, $dir, $chr_id ) = @_;

    $chr_id ||= 0;

    my $sth = prepare_statement(q{
        INSERT sequence( seq_id
              , sequence_name
              , sequence_version
              , embl_checksum
              , unpadded_length
              , contig_count
              , file_path
              , chromosome_id )
        VALUES (NULL,?,?,?,?,?,?,?)
        });
    $sth->execute(
        $seq_name,
        $seq_version,
        $cksum,
        $length,
        1,
        $dir,
        $chr_id );
    return $sth->{'mysql_insertid'};
}

sub set_ana_sequence_not_current {
    my( $seq_id ) = @_;

    my $sth = prepare_statement(qq{
        UPDATE ana_sequence
        SET is_current = 'N'
        WHERE seq_id = $seq_id
        });
    $sth->execute;
}

{
    my( $u_name );
    
    sub set_annotator_uname {
        $u_name = shift;
    }
    
    sub get_annotator_uname {
        unless ($u_name) {
            $u_name = (getpwuid($<))[0];
        }
        return $u_name;
    }
}

{
    my( %annotator );
    
    sub annotator_full_name {
        my( $uid ) = @_;
        
        unless (%annotator) {
            my $sth = prepare_statement(q{
                SELECT annotator_uname, full_name
                FROM ana_person
                });
            $sth->execute;
            while (my ($uid, $name) = $sth->fetchrow) {
                $annotator{$uid} = $name;
            }
        }
        
        return $annotator{$uid};
    }
}

sub make_ana_dir_from_species_chr_seqname_time {
    my( $species, $chr, $seq_name, $time ) = @_;
    
    $species ||= 'UNKNOWN';
    $chr     ||= 'UNKNOWN';
    
    my $ana_root = $SPECIES_ANALYSIS_ROOT->{$species}
      #  || '/nfs/disk100/humpub/analysis/misc';
	|| "$HUMPUB_ROOT/analysis/misc";

    $chr = "Chr_$chr";
    
    # Must have a sequence name!
    confess "No sequence given" unless $seq_name;
    
    my $date_dir = date_dir($time);
    
    my $ana_dir = "$ana_root/$chr/$seq_name/$date_dir";
    my $rawdata = "$ana_dir/rawdata";
    warn "RAWDATA: $rawdata\n";	
    mkpath($rawdata);
    
    # Make ana_dir owned by group vertann
    my $gid = (getgrnam("vertann"))[2];
    chown($<, $gid, $ana_dir);
    
    # Turns on group write access and group sticky
    chmod(02775, $ana_dir);
    
    confess "Failed to make '$rawdata'" unless -d $rawdata;
    return $ana_dir;
}

sub date_dir {
    my $time = shift || time;

    # Get time info
    my ($mday, $mon, $year) = (localtime($time))[3,4,5];

    # Change numbers to double-digit format
    ($mon, $mday) = ('00'..'31')[$mon + 1, $mday];

    # Make year
    $year += 1900;

    return "$year$mon$mday";
}

{
    my( %active_task );
    
    sub _init_active_task {
        my $sth = prepare_statement(q{
            SELECT task_name
            FROM ana_task
            WHERE is_active = 'Y'
            });
        $sth->execute;
        while (my ($task_name) = $sth->fetchrow) {
            $active_task{$task_name} = 1;
        }
    }

    sub is_active_task {
        my( $task_name ) = @_;
        
        _init_active_task() unless %active_task;
        return $active_task{$task_name} ? 1 : 0;
    }
    
    sub list_active_tasks {
        _init_active_task() unless %active_task;
        return        keys %active_task;
    }
    
    sub active_task_count {
        _init_active_task() unless %active_task;
        return scalar keys %active_task;
    }
}


1;

__END__

=head1 NAME - Hum::AnaStatus

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

