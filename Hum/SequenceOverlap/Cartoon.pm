
### Hum::SequenceOverlap::Cartoon

package Hum::SequenceOverlap::Cartoon;

use strict;
use GD;
use base 'Hum::SequenceOverlap';


sub rpp {
    my( $self, $rpp ) = @_;
    
    if ($rpp) {
        $self->{'_rpp'} = $rpp;
    }
    return $self->{'_rpp'} || 1000;
}

sub pad {
    my( $self, $pad ) = @_;
    
    if ($pad) {
        $self->{'_pad'} = $pad;
    }
    return $self->{'_pad'} || 10;
}

sub gif {
    my( $self ) = @_;
    
    my $width  = $self->image_width;
    my $height = $self->image_height;
    my $img = GD::Image->new($width, $height);
    my $white = $img->colorAllocate(255,255,255);
    my $black = $img->colorAllocate(0,0,0);
    return $img->gif;
}

sub image_width {
    my( $self ) = @_;
    
    my $scale = $self->rpp;
    my $pad   = $self->pad;
    my $wid_1 = $self->a_Position->SequenceInfo->sequence_length;
    my $wid_2 = $self->a_Position->SequenceInfo->sequence_length;
}

sub image_height {
    my( $self ) = @_;
    
}

1;

__END__

=head1 NAME - Hum::SequenceOverlap::Cartoon

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

