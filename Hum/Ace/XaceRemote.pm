
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
    return;
}

sub xace_window_id {
    my( $self, $xwid ) = @_;
    
    if ($xwid) {
        $self->{'_xace_window_id'} = $xwid;
    }
    unless ($xwid = $self->{'_xace_window_id'}) {
        my $xwid = $self->get_xace_window_id;
        $self->{'_xace_window_id'} = $xwid;
    }
    return $xwid;
}




1;

__END__

=head1 NAME - Hum::Ace::XaceRemote

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

