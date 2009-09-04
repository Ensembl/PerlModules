
### Hum::AnaStatus::AceFile

package Hum::AnaStatus::AceFile;

use strict;
use warnings;
use Carp;
use Hum::Submission qw( prepare_statement );

sub new {
    my ($pkg) = @_;
    
    my $self = bless {}, $pkg;
    
    return $self;
}

sub get_all_for_ana_seq_id {
    my( $pkg, $ana_seq_id ) = @_;
    
    confess "No ana_seq_id given" unless $ana_seq_id;
    
    my $fetch_acefile_data = prepare_statement(qq{
        SELECT a.acefile_name
          , a.acefile_status_id
          , UNIX_TIMESTAMP(a.creation_time)
          , UNIX_TIMESTAMP(v.earliest_date)
          , UNIX_TIMESTAMP(v.latest_date)
        FROM ana_acefile a
          , ana_task_version v
        WHERE a.acefile_name = v.acefile_name
          AND ana_seq_id = $ana_seq_id
        });
    $fetch_acefile_data->execute;

    my( @list );
    while (my $row = $fetch_acefile_data->fetchrow_arrayref) {
        my $acefile = $pkg->new;
        $acefile->ana_seq_id        ($ana_seq_id);
        $acefile->acefile_name      ($row->[0]);
        $acefile->acefile_status_id ($row->[1]);
        $acefile->creation_time     ($row->[2]);
        $acefile->earliest_date     ($row->[3]);
        $acefile->latest_date       ($row->[4]);
        push(@list, $acefile);
    }
    return @list;
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

sub acefile_name {
    my ( $self, $acefile_name ) = @_;

    if ($acefile_name) {
        confess "Can't modify acefile_name"
            if $self->{'_acefile_name'};
        $self->{'_acefile_name'} = $acefile_name;
    }
    return $self->{'_acefile_name'};
}

sub acefile_status_id {
    my ( $self, $acefile_status_id ) = @_;

    if ($acefile_status_id) {
        confess "Can't modify acefile_status_id"
            if $self->{'_acefile_status_id'};
        confess "Unknown acefile_status_id '$acefile_status_id'"
            unless $self->is_valid_acefile_status_id($acefile_status_id);
                                    
        $self->{'_acefile_status_id'} = $acefile_status_id;
    }
    return $self->{'_acefile_status_id'};
}

sub creation_time {
    my ( $self, $creation_time ) = @_;

    if ($creation_time) {
        confess "Can't modify creation_time"
            if $self->{'_creation_time'};
        $self->{'_creation_time'} = $creation_time;
    }
    return $self->{'_creation_time'};
}

sub earliest_date {
    my ( $self, $earliest_date ) = @_;

    if ($earliest_date) {
        confess "Can't modify earliest_date"
            if $self->{'_earliest_date'};
        $self->{'_earliest_date'} = $earliest_date;
    }
    return $self->{'_earliest_date'};
}

sub latest_date {
    my ( $self, $latest_date ) = @_;

    if ($latest_date) {
        confess "Can't modify latest_date"
            if $self->{'_latest_date'};
        $self->{'_latest_date'} = $latest_date;
    }
    return $self->{'_latest_date'};
}

sub acefile_status_id_name {
    my ( $self, $acefile_status_id ) = @_;

    my %status_dict =  (
        '1' => 'Begin',
        '2' => 'Complete',
        '3' => 'Loaded',
        '4' => 'Load Error',
        '5' => 'Compressed',
        '6' => 'Deleted',
        '7' => 'Create Error',
        '%' => 'Any'
        );
								

    if ($acefile_status_id) {
        confess "Can't modify acefile_status_id"
            if $self->{'_acefile_status_id'};
        confess "Unknown acefile_status_id '$acefile_status_id'"
            unless $self->is_valid_acefile_status_id($acefile_status_id);
                                    
        $self->{'_acefile_status_id'} = $status_dict{$acefile_status_id};
    }
    return $status_dict{$self->{'_acefile_status_id'}};
}

sub set_acefile_status {
    my( $self, $acefile_status) = @_;

    confess "Acefile status not given" unless $acefile_status;
    return 1 if $acefile_status == $self->acefile_status_id;
    confess "Unknown acefile status '$acefile_status'"
        unless $self->is_valid_acefile_status_id($acefile_status);

    my $acefile_name = $self->acefile_name
        or confess "No acefile_name in object";
    my $ana_seq_id = $self->ana_seq_id
        or confess "No ana_seq_id in object";

    my $new_acefile_status = prepare_statement(qq{
        UPDATE ana_acefile
        SET acefile_status_id = $acefile_status
        WHERE acefile_name = '$acefile_name'
          AND ana_seq_id = $ana_seq_id
        });
    $new_acefile_status->execute;

    my $rows = $new_acefile_status->rows;
    if ($rows == 1) {
        $self->{'_acefile_status_id'} = $acefile_status;
        return 1;
    } else {
        confess "acefile_status UPDATE failed";
    }
}

{
    my %valid_acefile_status_id;
    
    sub is_valid_acefile_status_id {
        my ( $self, $acefile_status_id) = @_;
        
        unless (%valid_acefile_status_id){
            my $sth = prepare_statement (q{
                SELECT acefile_status_id
                FROM ana_acefile_status_dict
                });
                
            $sth->execute;
            
            while (my ($valid_acefile_status_id) = $sth->fetchrow) {
                $valid_acefile_status_id{$valid_acefile_status_id} = 1;
            }
        }
        return $valid_acefile_status_id{$acefile_status_id};
    }    
}


sub task_name {
    my ( $self ) = @_;

    my( $task_name );
    unless ($task_name = $self->{'_task_name'}) {
        $task_name = $self->acefile_name
            or confess "acefile_name not set";
        $task_name =~ s/[^a-zA-Z]//g;
        $self->{'_task_name'} = $task_name;
    }
    return $task_name;
}

sub file_path {
    my( $self, $seq_name ) = @_;
    
    confess "Missing sequence_name argument"
        unless $seq_name;
    my $name = $self->acefile_name;
    my $gz   = $self->acefile_status_id == 5 ? '.gz' : '';
    my $extn = $name eq 'ace' ? '' : '.ace';
    return "$seq_name.$name$extn$gz";
}

{
    my( $time, $day_sec );

    sub age_in_days {
        my( $self ) = @_;

        $time    ||= time;
        $day_sec ||= 24 * 60 * 60;
        
        my $latest = $self->latest_date;
        return( ($time - $latest) / $day_sec );
    }
}

sub store {
    my( $self ) = @_;

    my $acefile_name = $self->acefile_name
        or confess "acefile_name is empty";
    my $acefile_status_id = $self->acefile_status_id
        or confess "acefile_status_id is empty";
    my $ana_seq_id = $self->ana_seq_id
        or confess "ana_seq_id is empty";
    my $creation_time = $self->creation_time;
    unless ($creation_time) {
        $creation_time = time;
        $self->creation_time($creation_time);
    }

    my $store_acefile = prepare_statement(qq{
        INSERT ana_acefile (acefile_name
          , acefile_status_id
          , ana_seq_id
          , creation_time)
        VALUES('$acefile_name'
        , $acefile_status_id
        , $ana_seq_id
        , FROM_UNIXTIME($creation_time))
        });
    $store_acefile->execute;

    $self->store_acefile_date_range;
}

sub store_acefile_date_range {
    my( $self ) = @_;

    my $time = $self->creation_time
        or confess "creation_time is empty";
    my $acefile_name = $self->acefile_name
        or confess "acefile_name is empty";

    my $get_acefile_date = prepare_statement(qq{
        SELECT UNIX_TIMESTAMP(earliest_date)
          , UNIX_TIMESTAMP(latest_date)
        FROM ana_task_version
        WHERE acefile_name = '$acefile_name'
        });
    $get_acefile_date->execute;
    my($earliest, $latest) = $get_acefile_date->fetchrow;

    # Update the row if we have a later date
    # than the latest stored in the database
    if ($earliest) {
        if ($time > $latest) {
            my $update_latest_date = prepare_statement(qq{
                UPDATE ana_task_version
                SET latest_date = FROM_UNIXTIME($time)
                WHERE acefile_name = '$acefile_name'
                });
            $update_latest_date->execute;
        }
        if ($time < $earliest) {
            my $update_earliest_date = prepare_statement(qq{
                UPDATE ana_task_version
                SET earliest_date = FROM_UNIXTIME($time)
                WHERE acefile_name = '$acefile_name'
                });
            $update_earliest_date->execute;
        }
    } else {
        # Add a new row
        confess "$acefile_name latest date: $latest. Earliest date not defined"
            if $latest;##?
        my $task_name = $self->task_name
            or confess "task_name is empty";
        my $add_dates = prepare_statement(qq{
            INSERT ana_task_version (acefile_name
              , task_name
              , earliest_date
              , latest_date)
            VALUES ('$acefile_name'
                , '$task_name'
                , FROM_UNIXTIME($time)
                , FROM_UNIXTIME($time))
            });
        $add_dates->execute;
    }
}





1;

__END__

=head1 NAME - Hum::AnaStatus::AceFile

=head1 METHODS  

=ovr4 

=item new

my $acefile = Hum::AnaStatus::AceFile->new

Creates a new AceFile object

=item ana_seq_id

This reports the ana_sequence id.

=item acefile_name

The name of the acefile.

=item acefile_status_id

The status of the acefile.

=item task_name

The task of the acefile

=item creation_time

The time when the acefile was created.

=item store

This method stores acefile object values and updates the task dates 
in the Submissions database.

=back

=head1 AUTHOR

Javier Santoyo-Lopez B<email> jsl@sanger.ac.uk

