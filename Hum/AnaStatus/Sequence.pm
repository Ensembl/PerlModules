
### Hum::AnaStatus::Sequence

package Hum::AnaStatus::Sequence;

use strict;
use Carp;
use Hum::Submission qw( prepare_statement );
use Hum::AnaStatus::AceFile;

sub new_from_sequence_name {
    my ($pkg, $seq_name) = @_;
    
    my $self = bless {}, $pkg;

    my $sth = prepare_statement(q{
        SELECT a.analysis_directory
          , a.analysis_priority
          , a.seq_id
          , a.ana_seq_id
          , status.status_id
          , status.status_date
          , s.embl_checksum
        FROM sequence s
          , ana_sequence a
        LEFT JOIN ana_status status
          ON a.ana_seq_id = status.ana_seq_id
        LEFT JOIN ana_sequence_person person
          ON a.ana_seq_id = person.ana_seq_id                        
        WHERE s.seq_id = a.seq_id
          AND a.is_current = 'Y'
          AND s.sequence_name = ?
        });


    $sth->execute($seq_name);
    
    # The reference of the first array refers to the row, and the second 
    # array referes to the value of each attribute in the row.
    # values are in the same order than in the select statement
    my $ans = $sth->fetchall_arrayref;
    
    if (@$ans == 1) {
       # Make new object and return          
       my $self = bless $ans->[0], $pkg;              
       return $self;
    }
    elsif (@$ans > 1) {
        my $rows = @$ans;
        my $error = "Got $rows entries for '$seq_name':\n";
        foreach my $r (@$ans) {
            $error .= "[" . join (", ", map "'$_'", @$r) . "]\n";
        }
        confess $error;
    }
    else {
        confess "No entries found for '$seq_name'";
    }
}

sub analysis_directory {
    my ( $self, $new_analysis_directory ) = @_;
    my ( $analysis_directory ) = $self->[0];
            
    if ($new_analysis_directory) {
        $self->[0] = $new_analysis_directory;
    } elsif ($analysis_directory) {
        return $analysis_directory;
    } else {
        confess "Analysis directory not found";
    }

}
sub analysis_priority {
    my ( $self, $new_analysis_priority ) = @_ ;
    
    my ( $analysis_priority ) = $self->[1];
    return $analysis_priority if $analysis_priority;
}

sub seq_id {
    my ( $self, $new_seq_id ) = @_;
    
    my ( $seq_id ) = $self->[2];
    return $seq_id if $seq_id;
}

sub ana_seq_id {
    my ( $self, $new_ana_seq_id ) = @_;
    
    my ( $ana_seq_id )= $self->[3];
    return $ana_seq_id if $ana_seq_id;
}

sub status_id {
    my ( $self, $new_status_id ) = @_;
    
    my ( $status_id ) = $self->[4];
    return $status_id if $status_id;
}

sub status_date {
    my ( $self, $new_status_date ) = @_;
    
    my ( $status_date ) = $self->[5];
    return $status_date if $status_date;
}

sub embl_checksum {
    my ( $self, $new_embl_checksum ) = @_ ;
    
    my ( $embl_checksum ) = $self->[6];
    return $embl_checksum if $embl_checksum;
}



1;

__END__



=head1 NAME - Hum::AnaStatus::Sequence

=head1 MEHTHODS

=over 4

=item new_from_sequence_name

my $ana_seq = Hum::AnaStatus::Sequence->new_from_sequence_name('dJ354B12');

Given a humace sequence name, returns a new
object, or throws an exception if it isn't found
in the database

=item set_status

$ana_seq->set_status(3);

=item set_annotator_uname

$ana_seq->set_annotator_uname('ak1');

=item new_AceFile

my $ace_file = $ana_seq->new_AceFile($acefile_name);

=item lock_sequence

=item unlock_sequence

=back

=head1 READ-ONLY METHODS

The following methods just report the values of
their fields, they dont' allow you to set them

=over 4

=item ana_seq_id

=item seq_id

=item current_status

The number of the status currently held

=item current_status_date

The date the current status was assigned.

=item current_status_description

The description of this status

=item analysis_directory

Analysis directory location

=item analysis_priority

Assigned analysis priority

=item annotator_uname

The user name of the annotator assigned to
annotate this sequence.

=item get_all_AceFiles

Returns a list of Hum::AnaStatus::AceFile objects
associated with this sequence.

=back

=head1 AUTHOR

Javier Santoyo-Lopez B<email> jsl@sanger.ac.uk

