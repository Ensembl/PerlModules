
### Hum::AnaStatus::AceFile

package Hum::AnaStatus::AceFile;

use strict;
use Carp;
use Hum::Submission qw( prepare_statement );

sub new {
    my ($pkg) = @_;
    
    my $self = bless {}, $pkg;
    
    return $self;
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
            unless $self->_is_valid_ace_status_id($acefile_status_id);
                                    
        $self->{'_acefile_status_id'} = $acefile_status_id;
    }
    return $self->{'_acefile_status_id'};
}

sub task_name {
    my ( $self ) = @_;

    if (my $task_name = $self->{'_task_name'}) {
        return $task_name;
    } else {
        $task_name = $self->acefile_name
            or confess "acefile_name not set";
        $task_name =~ s/[^a-zA-Z]//g;
        $self->{'_task_name'} = $task_name;
    }
}

{
    my( $store_acefile );

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

        $store_acefile ||= prepare_statement(q{
            INSERT ana_acefile (acefile_name
              , acefile_status_id
              , ana_seq_id
              , creation_time)
            VALUES(?
            , ?
            , ?
            , FROM_UNIXTIME(?))
            });
        $store_acefile->execute(
            $acefile_name,
            $acefile_status_id,
            $ana_seq_id,
            $creation_time);
        
        $self->store_acefile_date_range;
    }
}

{
    my( $get_acefile_date,
        $add_new_acefile_date,
        $update_latest_date,
        $update_earliest_date,
        $add_dates );
    
    sub store_acefile_date_range {
        my( $self ) = @_;

        my $time = $self->creation_time
            or confess "creation_time is empty";
        my $acefile_name = $self->acefile_name
            or confess "acefile_name is empty";
        
        $get_acefile_date ||= prepare_statement(q{
            SELECT UNIX_TIMESTAMP(earliest_date)
              , UNIX_TIMESTAMP(latest_date)
            FROM ana_task_version
            WHERE acefile_name = ?
            });
        $get_acefile_date->execute($acefile_name);
        my($earliest, $latest) = $get_acefile_date->fetchrow;

        # Update the row if we have a later date
        # than the latest stored in the database
        if ($earliest) {
            if ($time > $latest) {
                $update_latest_date ||= prepare_statement(q{
                    UPDATE ana_task_version
                    SET latest_date = FROM_UNIXTIME(?)
                    WHERE acefile_name = ?
                    });
                $update_latest_date->execute($time, $acefile_name);
            }
            if ($time < $earliest) {
                $update_earliest_date ||= prepare_statement(q{
                    UPDATE ana_task_version
                    SET earliest_date = FROM_UNIXTIME(?)
                    WHERE acefile_name = ?
                    });
                $update_earliest_date->execute($time, $acefile_name);
            }
        } else {
            # Add a new row
            confess "$acefile_name latest date: $latest. Earliest date not defined"
                if $latest;##?
            my $task_name = $self->task_name
                or confess "task_name is empty";
            $add_dates ||= prepare_statement(q{
                INSERT ana_task_version (acefile_name
                  , task_name
                  , earliest_date
                  , latest_date)
                VALUES (?
                    , ?
                    , FROM_UNIXTIME(?)
                    , FROM_UNIXTIME(?))                
                });
            $add_dates->execute(
                $acefile_name,
                $task_name,
                $time,
                $time);
        }
    }
}


{
    my %valid_ace_status_id;
    
    sub _is_valid_ace_status_id {
        my ($self, $ace_status_id) = @_;
        
        my @valid_ace_status_id;
                
        unless (%valid_ace_status_id){
            my $sth = prepare_statement (q{
            SELECT acefile_status_id
            FROM ana_acefile_status_dict });
            
            $sth->execute;
            
            while (my $valid_ace_status_id = $sth->fetchrow) {
                push (@valid_ace_status_id, $valid_ace_status_id);
            }                        
            %valid_ace_status_id = map {$_, 1} @valid_ace_status_id;
        }
        return $valid_ace_status_id{$ace_status_id};
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

