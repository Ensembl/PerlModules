
### Hum::AnaStatus::Job

package Hum::AnaStatus::Job;

use strict;
use warnings;
use Carp;
use Hum::Submission qw{
    create_lock
    destroy_lock
    prepare_statement
    };
use Hum::AnaStatus::Sequence;

sub new {
    my( $pkg ) = @_;
    
    my $self = bless {}, $pkg;
    return $self;
}

sub new_from_ana_job_id {
    my( $pkg, $ana_job_id ) = @_;
    
    my $sth = prepare_statement(qq{
        SELECT ana_seq_id
          , task_name
          , submit_time
          , lsf_job_id
          , lsf_error
        FROM ana_job
        WHERE ana_job_id = $ana_job_id
        });
    $sth->execute;
    
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
        $self->ana_seq_id($ana_seq_id);
        $self->task_name($task_name);
        $self->submit_time($submit_time);
        $self->lsf_job_id($lsf_job_id);
        $self->lsf_error($lsf_error);
        
        return $self;
    }
    elsif (@$ans > 1) {
        my $error = "Got multiple answers for ana_job_id '$ana_job_id' :\n";
        foreach my $row (@$ans) {
            pop(@$row);     # Don't want big error string
            $error .= "  [" . join(", ", map "'$_'", @$row) . "]\n";
        }
        confess $error;
    }
    else {
        confess "Didn't find any records for ana_job_id '$ana_job_id'";
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

sub get_AnaSequence {
    my( $self ) = @_;
    
    my( $ana_seq );
    unless ($ana_seq = $self->{'_ana_sequence'}) {
        my $ana_seq_id = $self->ana_seq_id
            or confess "No ana_seq_id";
        $ana_seq = Hum::AnaStatus::Sequence
            ->new_from_ana_seq_id($ana_seq_id);
        $self->{'_ana_sequence'} = $ana_seq;
    }
    return $ana_seq;
}

{
    my( %_task_command );
    
    sub run_command {
        my( $self ) = @_;
        
        unless (%_task_command) {
            my $sth = prepare_statement(q{
                SELECT task_name
                  , run_command
                FROM ana_task
                });
            $sth->execute;
            while (my ($name, $com) = $sth->fetchrow) {
                $_task_command{$name} = $com;
            }
        }
        my $name = $self->task_name
            or confess "No task_name";
        return $_task_command{$name}
            || confess "No run_command for task '$name'";
    }
}

sub submit {
    my( $self ) = @_;
    
    $self->store;

    my $ana_job_id      = $self->ana_job_id;
    my $wrapper_command = $self->wrapper_command;
    
    my $bsub_pipe = "bsub $wrapper_command -ana_job_id $ana_job_id 2>&1 |";
    local *BSUB_PIPE;
    open BSUB_PIPE, $bsub_pipe
        or die "Can't open pipe '$bsub_pipe' : $!";
    
    my $bsub_out = '';
    my( $lsf_job_id );
    while (<BSUB_PIPE>) {
        $bsub_out .= $_;
        $lsf_job_id = $1 if /^Job\s+\<(\d+)\>/;;
    }
    unless ($lsf_job_id and close(BSUB_PIPE)) {
        confess "Error running '$bsub_pipe' : exit $?\n$bsub_out";
    }
    $self->lsf_job_id($lsf_job_id);
    $self->store_lsf_job_id;
}

sub wrapper_command {
    my( $self, $command ) = @_;
    
    if ($command) {
        $self->{'_wrapper_command'} = $command;
    }
    return $self->{'_wrapper_command'} || $self->default_wrapper_command;
}

{
    my( $default_wrapper );

    sub default_wrapper_command {
        
        unless ($default_wrapper) {
            my $command_dir = $0;
            $command_dir =~ s{/?([^/]+)$}{};
            $default_wrapper = "$command_dir/run_ana_job";
            confess "Default wrapper not executable : '$default_wrapper'"
                unless -x $default_wrapper;
        }
        
        return $default_wrapper;
    }
}

sub store {
    my( $self ) = @_;
    
    my $ana_seq_id = $self->ana_seq_id
        or confess "ana_seq_id not set";
    my $task_name = $self->task_name
        or confess "task_name not set";
    my $insert = prepare_statement(qq{
        INSERT ana_job( ana_job_id
              , ana_seq_id
              , task_name
              , submit_time )
        VALUES (NULL, $ana_seq_id, '$task_name', NOW())
        });
    $insert->execute;
    my $ana_job_id = $insert->{'mysql_insertid'}
        or confess "No insertid from statement handle";
    $self->ana_job_id($ana_job_id);
}

sub store_lsf_job_id {
    my( $self ) = @_;
    
    my $ana_job_id = $self->ana_job_id
        or confess "No ana_job_id.  'store' not called?";
    my $lsf_job_id = $self->lsf_job_id
        or confess "No lsf_job_id.  bsub not done?";
    
    my $update = prepare_statement(qq{
        UPDATE ana_job
        SET lsf_job_id = $lsf_job_id
          , lsf_error = NULL
        WHERE ana_job_id = $ana_job_id
        });
    $update->execute;
    my $rows_affected = $update->rows;
    confess "Error: '$rows_affected' rows updated"
        unless $rows_affected == 1;
}

sub save_command_output {
    my( $self, $output ) = @_;
    
    my $ana_job_id = $self->ana_job_id
        or confess "No ana_job_id.  'store' not called?";
    
    my $update = prepare_statement(q{
        UPDATE ana_job
        SET lsf_error = ?
        WHERE ana_job_id = ?
        });
    $update->execute($output, $ana_job_id);
    my $rows_affected = $update->rows;
    confess "Error: '$rows_affected' rows updated"
        unless $rows_affected == 1;
}

sub remove {
    my( $self ) = @_;
    
    my $ana_job_id = $self->ana_job_id
        or confess "No ana_job_id";
    my $update = prepare_statement(q{
        DELETE from ana_job
        WHERE ana_job_id = ?
        });
    $update->execute($ana_job_id);
    $self = undef;
}

sub lock_name {
    my( $self ) = @_;
    
    my $task_name = $self->task_name
        or die "missing task_name";
    my $ana_seq_id = $self->ana_seq_id
        or die "missing ana_seq_id";
    return "$task_name-$ana_seq_id";
}

sub lock {
    my( $self ) = @_;
    
    create_lock($self->lock_name);
}

sub unlock {
    my( $self ) = @_;

    destroy_lock($self->lock_name);
}

sub is_locked {
    my( $self ) = @_;

    my $sth = prepare_statement(q{
        SELECT count(*)
        FROM general_lock
        WHERE lock_name = ?
        });
    $sth->execute($self->lock_name);
    my ($c) = $sth->fetchrow;
    return $c;
}

1;

__END__

=head1 NAME - Hum::AnaStatus::Job

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

