
### Hum::AnaStatus

package Hum::AnaStatus;

use strict;
use vars qw{ @ISA @EXPORT_OK };
use Carp;
use Exporter;
use Hum::Submission 'prepare_statement';

@ISA = ('Exporter');
@EXPORT_OK = qw{
    add_seq_id_dir 
    add_new_sequence_entry
    set_ana_sequence_not_current
    annotator_full_name
    date_dir
    };

{
    my( $sth );

    sub add_seq_id_dir {
        my( $seq_id, $ana_dir, $db_prefix ) = @_;
        
        $db_prefix ||= '';
        
        $sth ||= prepare_statement(q{
            INSERT ana_sequence( ana_seq_id
              , is_current
              , seq_id
              , analysis_directory
              , db_prefix)
            VALUES (NULL,'Y',?,?,?)
            });
        $sth->execute($seq_id, $ana_dir, $db_prefix);
        my $ana_seq_id = $sth->{'insertid'};
        
        make_status_entered($ana_seq_id);
    }
}

{
    my( $sth );

    sub make_status_entered {
        my( $ana_seq_id ) = @_;
        
        $sth ||= prepare_statement(q{
            INSERT ana_status( ana_seq_id
              , is_current
              , status_date
              , status_id)
            VALUES (?,'Y',NOW(),1)
            });
        # status_id of 1 = "Entered"
        $sth->execute($ana_seq_id);
    }
}

{
    my( $sth );

    sub add_new_sequence_entry {
        my( $seq_name, $cksum, $length, $dir, $chr_id ) = @_;
        
        $chr_id ||= 0;
        
        $sth ||= prepare_statement(q{
            INSERT sequence( seq_id
                  , sequence_name
                  , embl_checksum
                  , unpadded_length
                  , contig_count
                  , file_path
                  , chromosome_id )
            VALUES (NULL,?,?,?,?,?,?)
            });
        $sth->execute(
            $seq_name,
            $cksum,
            $length,
            1,
            $dir,
            $chr_id );
        return $sth->{'insertid'};
    }
}

{
    my( $sth );

    sub retire_ana_sequece {
        my( $seq_name, $dir ) = @_;
        
        confess "Not yet implemented!";
    }
}

{
    my( $sth );

    sub set_ana_sequence_not_current {
        my( $seq_id ) = @_;
        
        $sth ||= prepare_statement(q{
            UPDATE ana_sequence
            SET is_current = 'N'
            WHERE seq_id = ?
            });
        $sth->execute($seq_id);
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


1;

__END__

=head1 NAME - Hum::AnaStatus

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

