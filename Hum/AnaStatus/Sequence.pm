
### Hum::AnaStatus::Sequence

package Hum::AnaStatus::Sequence;

use strict;
use Carp;
use Hum::Submission qw( prepare_statement timeace );
use Hum::AnaStatus::AceFile;

sub new_from_sequence_name {
    my ($pkg, $seq_name) = @_;

    my $sth = prepare_statement(q{
        SELECT a.analysis_directory
          , a.analysis_priority
          , a.seq_id
          , a.ana_seq_id
          , status.status_id
          , UNIX_TIMESTAMP(status.status_date)
          , s.embl_checksum
          , person.annotator_uname
        FROM sequence s
          , ana_sequence a
          , ana_status status
        LEFT JOIN ana_sequence_person person
          ON a.ana_seq_id = person.ana_seq_id                        
        WHERE s.seq_id = a.seq_id
          AND a.ana_seq_id = status.ana_seq_id
          AND status.is_current = 'Y'
          AND a.is_current = 'Y'
          AND s.sequence_name = ?
        });

    $sth->execute($seq_name);
    
    # in $ans the reference of the first array refers to the row, and the second 
    # array refers to the value of each attribute in the row.
    # values are in the same order than in the SELECT statement
    my $ans = $sth->fetchall_arrayref;
    
    if (@$ans == 1) {                             
       my (
            $analysis_directory,
            $analysis_priority,
            $seq_id,
            $ana_seq_id,
            $status_id,
            $status_date,
            $embl_checksum,
            $annotator_uname
           ) = @{$ans->[0]};
        
        my $self = bless {}, $pkg;
        
        $self->sequence_name($seq_name);
        $self->analysis_directory($analysis_directory);
        $self->analysis_priority($analysis_priority);
        $self->seq_id($seq_id);
        $self->ana_seq_id($ana_seq_id);
        $self->status_id($status_id || 0);
        $self->status_date($status_date || 0);
        $self->embl_checksum($embl_checksum);
        $self->annotator_uname($annotator_uname);
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

{
    my( $set_not_current, $new_status );

    sub set_status {
        my ( $self, $status ) = @_;
        
        my $time = time;
        
        confess "status id not defined" unless $status;
        # Just return TRUE if we already have this status
        return 1 if $status == $self->status_id;
        confess "Unknown status_id '$status'"
            unless $self->_is_valid_status_id($status);

        my $ana_seq_id = $self->ana_seq_id
            or confess "No ana_seq_id in object";

        $set_not_current ||= prepare_statement(q{
            UPDATE ana_status
            SET is_current = 'N'
            WHERE ana_seq_id = ?
            });

        $new_status ||= prepare_statement(q{
            INSERT ana_status( ana_seq_id
                  , is_current
                  , status_date
                  , status_id )
            VALUES( ?
                  , 'Y'
                  , FROM_UNIXTIME(?)
                  , ?)
            });
        
        $set_not_current->execute($ana_seq_id);
        $new_status->execute($ana_seq_id, $time, $status);
        my $rows = $new_status->rows;
        if ($rows == 1) {
            $self->{'_status_id'}   = $status;
            $self->{'_status_date'} = $time;
            return 1;
        } else {
            confess "ana_status INSERT failed";
        }
    }
}

{
    my $set_annotator_uname;
    
    sub set_annotator_uname {
        my ($self, $annotator_uname ) = @_;
        
        confess "annotator_uname not defined" unless $annotator_uname;
        $self->annotator_uname($annotator_uname);
        
        my $ana_seq_id = $self->ana_seq_id
            or confess "No ana_seq_id in object";
        
        $set_annotator_uname ||= prepare_statement(q{            

            INSERT ana_sequence_person (annotator_uname
                  , ana_seq_id)
            VALUES(?,?)
            
            });
            
        $set_annotator_uname->execute($annotator_uname, $ana_seq_id);
                
    }
}
 
 

sub status_id {
    my ( $self, $status_id ) = @_;
    
    if ($status_id) {
        confess "Unknown status_id '$status_id'"
            unless $self->_is_valid_status_id($status_id);
        confess "Can't modify status_id"
            if $self->{'_status_id'};
        $self->{'_status_id'} = $status_id;
    }
    return $self->{'_status_id'};
}


{
   my %valid_status_id;
    
    sub _is_valid_status_id {
        my ($self, $status_id) = @_;
        
        my @valid_status_id;
                
        unless (%valid_status_id){
            my $sth = prepare_statement (q{
            SELECT status_id
            FROM ana_status_dict });
            
            $sth->execute;
            
            while (my $valid_status_id = $sth->fetchrow) {
                push (@valid_status_id, $valid_status_id);
            }                        
            %valid_status_id = map {$_, 1} @valid_status_id;
        }
        return $valid_status_id{$status_id};
    }
}


sub analysis_directory {
    my ( $self, $analysis_directory ) = @_;
    
    if ($analysis_directory) {
        confess "Can't modify analysis_directory"
            if $self->{'_analysis_directory'};
        $self->{'_analysis_directory'} = $analysis_directory;
    }
    return $self->{'_analysis_directory'};
}


sub analysis_priority {
    my ( $self, $analysis_priority ) = @_;
    
    if (defined $analysis_priority) {
        confess "Can't modify analysis_priority"
            if $self->{'_analysis_priority'};
        $self->{'_analysis_priority'} = $analysis_priority;
    }
    return $self->{'_analysis_priority'};
}


sub seq_id {
    my ( $self, $seq_id ) = @_;
    
    if ($seq_id) {
        confess "Can't modify seq_id"
            if $self->{'_seq_id'};
        $self->{'_seq_id'} = $seq_id;
    }
    return $self->{'_seq_id'};
}


sub ana_seq_id {
    my ( $self, $ana_seq_id ) = @_;
    
    if ($ana_seq_id) {
        confess "Can't modify ana_seq_id"
            if $self->{'_ana_seq_id'};
        $self->{'_ana_seq_id'} = $ana_seq_id;
    }
    return $self->{'_ana_seq_id'};
}


sub status_date {
    my ( $self, $status_date ) = @_;
    
    if ($status_date) {
        confess "Can't modify status_date"
            if $self->{'_status_date'};
        $self->{'_status_date'} = $status_date;
    }
    return $self->{'_status_date'};
}


sub embl_checksum {
    my ( $self, $embl_checksum ) = @_;
    
    if ($embl_checksum) {
        confess "Can't modify embl_checksum"
            if $self->{'_embl_checksum'};
        $self->{'_embl_checksum'} = $embl_checksum;
    }
    return $self->{'_embl_checksum'};
}


sub annotator_uname {
    my ( $self, $annotator_uname ) = @_;
    
    if ($annotator_uname) {
        confess "Unknown annotator '$annotator_uname'"
            unless $self->_is_valid_annotator($annotator_uname);
        confess "Can't modify annotator_uname"
            if $self->{'_annotator_uname'};
        $self->{'_annotator_uname'} = $annotator_uname;
    }
    return $self->{'_annotator_uname'};
}

{
    my( %valid_annotators );

    sub _is_valid_annotator {
        my( $self, $annotator ) = @_;
                
        unless (%valid_annotators){
            my @valid_annotators;
            my $sth = prepare_statement (q{
            SELECT annotator_uname
            FROM ana_person });
            
            $sth->execute;
            
            while (my $valid_annotator = $sth->fetchrow) {
                push (@valid_annotators, $valid_annotator);
            }                        
            %valid_annotators = map {$_, 1} @valid_annotators;
        }
        return $valid_annotators{$annotator};
    }
}


sub sequence_name {
    my ( $self, $seq_name ) = @_;

    if ($seq_name) {
        confess "Can't modify seq_name"
            if $self->{'_seq_name'};
        $self->{'_seq_name'} = $seq_name;
    }
    return $self->{'_seq_name'};
}

sub add_AceFile {
    my( $self, $acefile ) = @_;
    
    my $acefile_name = $acefile->acefile_name
        or confess "acefile_name not defined";
    
    # Check that we don't already have the acefile in the database
    if ($self->get_AceFile_by_name($acefile_name)) {
        confess "AceFile '$acefile_name' is already stored in the database";
    }
    
    $self->AceFile_hash->{$acefile_name} = $acefile;
}

sub get_AceFile_by_filename {
    my ($self, $file_name) = @_;

    my $acefile_name = $self->parse_filename($file_name);

    return $self->get_AceFile_by_name($acefile_name);
}

sub get_AceFile_by_name {
    my ($self, $acefile_name) = @_;
    
    return $self->AceFile_hash->{$acefile_name};
}

sub get_all_AceFiles {
    my ($self) = @_;

    return values %{$self->AceFile_hash};
}

{
    my( $fetch_acefile_data );

    sub AceFile_hash {
        my ($self) = @_;

        unless ($self->{'_acefile'}) {
            $self->{'_acefile'} = {};
            
            my $ana_seq_id = $self->ana_seq_id
                or confess "No ana_seq_id in object";

            $fetch_acefile_data ||= prepare_statement(q{
                SELECT acefile_name
                  , acefile_status_id
                  , UNIX_TIMESTAMP(creation_time)
                FROM ana_acefile
                WHERE ana_seq_id = ?
                });
            $fetch_acefile_data->execute($ana_seq_id);

            while ( my($acefile_name,
                $acefile_status_id,
                $creation_time ) = $fetch_acefile_data->fetchrow) {

                my $acefile = Hum::AnaStatus::AceFile->new;
                $acefile->ana_seq_id($ana_seq_id);
                $acefile->acefile_name($acefile_name);
                $acefile->acefile_status_id($acefile_status_id);
                $acefile->creation_time($creation_time);

                $self->add_AceFile($acefile);
            }
        }
        return $self->{'_acefile'};
    }
}

sub new_AceFile_from_filename_and_time {
    my ($self, $file_name, $time) = @_;
    
    my $ana_seq_id = $self->ana_seq_id
        or confess "No ana_seq_id";
    confess "File name not defined" unless $file_name;
    $time ||= time;

    unless ($time =~ /^\d+$/) {
        my $unix_time = timeace($time)
            or confess "Bad time '$time'";
        $time = $unix_time;
    }
    
    my $acefile_name = $self->parse_filename($file_name);
    my $seq_name = $self->sequence_name;

    # Make a new acefile object, and populate it
    my $acefile = Hum::AnaStatus::AceFile->new;
    $acefile->acefile_name($acefile_name);
    $acefile->creation_time($time);
    $acefile->acefile_status_id(1);
    $acefile->ana_seq_id($ana_seq_id);
    
    $self->add_AceFile($acefile);###return as well?
    
    $acefile->store;
    
    return $acefile;
}

sub parse_filename {
    my ($self, $file_name) = @_;
    
    my $seq_name = $self->sequence_name
        or confess "sequence_name not defined";
    my $acefile_name = $file_name;
    return 'ace' if $file_name eq "$seq_name.ace";
    
    # Remove the .ace suffix from $acefile_name
    my $ace = substr($acefile_name, -4, 4);
    if ($ace eq '.ace') {
        # Remove the suffix
        substr($acefile_name, -4, 4) = '';
    } else {
        confess "acefile name '$file_name' doesn't end '.ace'";
    }
    
    # Remove the seqname. prefix from $acefile_name
    my $seq_name_prefix = "$seq_name.";
    my $prefix_len = length($seq_name_prefix);
    my $prefix = substr($acefile_name, 0, $prefix_len);
    if ($prefix eq $seq_name_prefix) {
        substr($acefile_name, 0, $prefix_len) = '';
    } else {
        confess "acefile name '$file_name' doesn't begin '$seq_name_prefix'";
    }
    
    return $acefile_name;
}


1;

__END__



=head1 NAME - Hum::AnaStatus::Sequence

=head1 METHODS

=over 4

=item new_from_sequence_name

my $ana_seq = 
    Hum::AnaStatus::Sequence->new_from_sequence_name ('dJ354B12');

Given a humace sequence name, returns a new
object, or throws an exception if it isn't found
in the Submissions database

=back

=head1 STORE METHODS    

The following methods store the values of their fields in the 
Submissions database

=item set_status

  $ana_seq->set_status(3);

If the current status is equal to the new status
given, this method returns TRUE.  Otherwise
set_status adds a new status to the database,
using the current time.

=item set_annotator_uname

  $ana_seq->set_annotator_uname('ak1');

This method stores the annotator username assigned to a sequence.  

=item new_AceFile_from_filename_and_time

  my $ace_file =
      $ana_seq->new_AceFile_from_filename_and_time(acefile_name, creation_time);
 
Given the name of an acefile and its creation time (in unix-time
or in ace-time format), this method returns an AceFile object and stores
its values in the Submissions database. 
If the time is not specified, the current time will be assigned to the
AceFile object.


=item lock_sequence

=item unlock_sequence

=back

=head1 READ-ONLY METHODS

The following methods just report the values of
their fields, they dont' allow you to set them

=over 4

=item ana_seq_id

This reports the ana_sequence id.

=item seq_id

This reports the sequence id.

=item status_id

This method returns the status number currently held.

=item status_date

The date when the current status was assigned.

=item analysis_directory

This method resports the full path of the analysis directory.

=item analysis_priority

The priority of the assigned analysis.

=item annotator_uname

The user name of the annotator assigned to
annotate this sequence.

=item get_all_AceFiles

Returns a list of all Hum::AnaStatus::AceFile objects
associated with this sequence.

=back

=head1 AUTHOR

Javier Santoyo-Lopez B<email> jsl@sanger.ac.uk

