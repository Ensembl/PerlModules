
### Hum::Ace::XaceRemote

package Hum::Ace::XaceRemote;

use strict;
use Carp;

sub new {
    my( $pkg, $xwid ) = @_;
    
    my $self = bless {}, $pkg;
    if ($xwid) {
        $self->xace_window_id($xwid);
    }
    return $self;
}

sub xace_window_id {
    my( $self, $xwid ) = @_;
    
    if ($xwid) {
        $self->{'_xace_window_id'} = $xwid;
    }
    return $self->{'_xace_window_id'}
        || confess "xace_window_id not set";
}

sub send_command {
    my( $self, @command ) = @_;
    
    my $com_str = join(' ; ', @command);
    warn "Sending: '$com_str'\n";
    my @xrem_com = (
        'xremote',
        -id         => $self->xace_window_id,
        -remote     => $com_str,
        );
    #warn "command = @xrem_com\n";
    if (system(@xrem_com) == 0) {
        return 1;
    } else {
        confess "Failed xremote: (@xrem_com) : $?";
    }
}

sub show_SubSeq {
    my( $self, $subseq, $pad ) = @_;
    
    unless (defined $pad) {
        $pad = int($subseq->subseq_length / 10);
        $pad = 500 if $pad < 500;
    }
    my $seq     = $subseq->clone_Sequence or confess "No clone_Sequence";
    my $start   = $subseq->start - $pad;
    my $end     = $subseq->end   + $pad;
    my $strand  = $subseq->strand;
    
    my $seq_name = $seq->name
        or confess "sequence_name not set";
    
    # Trim start and end to within sequence
    if ($start < 1) {
        $start = 1;
    }
    if ($end > $seq->sequence_length) {
        $end = $seq->sequence_length;
    }
    
    my @com = ('gif', "seqget $seq_name", "seqdisplay -visible_coords $start $end");
    if ($strand == -1) {
        push(@com, "seqactions -rev_comp");
    }
    
    $self->send_command(@com);
}

sub show_sequence {
    my( $self, $seq_name ) = @_;
    
    $self->send_command('gif', "seqget $seq_name", 'seqdisplay');
}

sub save {
    my( $self ) = @_;
    
    $self->send_command('save -regain');
}

sub load_ace {
    my $self        = shift;
    my $ace = join("\n\n", @_);
    
    #warn "\nLoading:\n\n$ace\n\n";
    
    my $tmp_ace = "/tmp/xremote.$$.ace";
    local *ACE_REMOTE;
    open ACE_REMOTE, "> $tmp_ace"
        or confess "Can't write to '$tmp_ace' : $!";
    print ACE_REMOTE $ace;
    close ACE_REMOTE;
    
    eval{
        $self->send_command("parse $tmp_ace");
    };
    unlink($tmp_ace);
    confess("Error parsing:\n$ace", $@) if $@;
}

1;

__END__

=head1 NAME - Hum::Ace::XaceRemote

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

