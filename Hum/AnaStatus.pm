
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
    };

{
    my( $sth );

    sub add_seq_id_dir {
        my( $seq_id, $ana_dir ) = @_;
        
        $sth ||= prepare_statement(q{
            INSERT ana_sequence( ana_seq_id
                  , is_current
                  , seq_id
                  , analysis_directory)
            VALUES (NULL,'Y',?,?)
            });
        $sth->execute($seq_id, $ana_dir);
    }
}

{
    my( $sth );

    sub add_new_sequence_entry {
        my( $seq_name, $cksum, $length, $dir ) = @_;
        
        $sth ||= prepare_statement(q{
            INSERT sequence( seq_id
                  , sequence_name
                  , embl_checksum
                  , unpadded_length
                  , contig_count
                  , file_path )
            VALUES (NULL,?,?,?,?,?)
            });
        $sth->execute(
            $seq_name,
            $cksum,
            $length,
            1,
            $dir
            );
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


1;

__END__

=head1 NAME - Hum::AnaStatus

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

