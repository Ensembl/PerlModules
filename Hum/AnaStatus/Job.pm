
### Hum::AnaStatus::Job

package Hum::AnaStatus::Job;

use strict;
use Carp;
use Hum::Submission 'prepare_statement';

sub new {
    my( $pkg ) = @_;
    
    my $self = bless {}, $pkg;
    return $self;
}

sub new_from_ana_job_id {
    my( $pkg, $ana_job_id ) = @_;
    
    my $sth = prepare_statement(q{
        SELECT ana_seq_id
          , task_name
          , submit_time
          , lsf_job_id
          , lsf_error
        FROM ana_job
        WHERE ana_job_id = ?
        });
    $sth->execute($ana_job_id);
    
    my $ans = $sth->fetchall_arrayref;
    if (@$ans == 1) {
        my(
            $ana_seq_id,
            $task_name,
            $submit_time,
            $lsf_job_id,
            $lsf_error,
            ) = @{$ans->[0]};
        
        my $self = $pkg->new;
        $self->ana_job_id($ana_job_id);
        $self->task_name($task_name);
        $self->submit_time($submit_time);
        $self->lsf_job_id($lsf_job_id);
        $self->lsf_error($lsf_error);
    }
    elsif (@$ans > 1) {
        my $error = "Got multiple answers for ana_job_id '$ana_job_id' :\n";
        foreach my $row (@$ans) {
            pop(@$row);     # Don't want big error string
            $error .= "  [" . join (", ", map "'$_'", @$row) . "]\n";
        }
        confess $error;
    }
    else {
        confess "Didn't find any records fro ana_job_id '$ana_job_id'";
    }
}

sub ana_job_id {
    my( $self, $ana_job_id ) = @_;
    
    if ($ana_job_id) {
        confess "Can't alter ana_job_id"
            if $self->{'_ana_job_id'};
        $self->{'_ana_job_id'} = $ana_job_id;
    }
    return $self->{'_ana_job_id'};
}

sub ana_seq_id {
    my( $self, $ana_seq_id ) = @_;
    
    if ($ana_seq_id) {
        confess "Can't alter ana_seq_id"
            if $self->{'_ana_seq_id'};
        $self->{'_ana_seq_id'} = $ana_seq_id;
    }
    return $self->{'_ana_seq_id'};
}

sub task_name {
    my( $self, $task_name ) = @_;
    
    if ($task_name) {
        confess "Can't alter task_name"
            if $self->{'_task_name'};
        $self->{'_task_name'} = $task_name;
    }
    return $self->{'_task_name'};
}

sub submit_time {
    my( $self, $submit_time ) = @_;
    
    if ($submit_time) {
        confess "Can't alter submit_time"
            if $self->{'_submit_time'};
        $self->{'_submit_time'} = $submit_time;
    }
    return $self->{'_submit_time'};
}

sub lsf_job_id {
    my( $self, $lsf_job_id ) = @_;
    
    if ($lsf_job_id) {
        confess "Can't alter lsf_job_id"
            if $self->{'_lsf_job_id'};
        $self->{'_lsf_job_id'} = $lsf_job_id;
    }
    return $self->{'_lsf_job_id'};
}

sub lsf_error {
    my( $self, $lsf_error ) = @_;
    
    if ($lsf_error) {
        confess "Can't alter lsf_error"
            if $self->{'_lsf_error'};
        $self->{'_lsf_error'} = $lsf_error;
    }
    return $self->{'_lsf_error'};
}

sub submit {
    warn "submit not implemented";
}

1;

__END__

=head1 NAME - Hum::AnaStatus::Job

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

