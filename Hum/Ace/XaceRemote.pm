
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
    my @xrem_com = (
        'xremote',
        -id         => $self->xace_window_id,
        -remote     => $com_str,
        );
    if (system(@xrem_com) == 0) {
        return 1;
    } else {
        confess "Failed xremote: (@xrem_com) : $?";
    }
}

sub show_sequence {
    my( $self, $seq_name ) = @_;
    
    $self->send_command('gif', "seqget $seq_name", 'seqdisplay');
}

1;

__END__

=head1 NAME - Hum::Ace::XaceRemote

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

