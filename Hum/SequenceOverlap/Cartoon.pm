
### Hum::SequenceOverlap::Cartoon

package Hum::SequenceOverlap::Cartoon;

use strict;
use Carp;
use GD;
use Hum::SequenceOverlap;
use vars '@ISA';
@ISA = qw{ Hum::SequenceOverlap };


sub rpp {
    my( $self, $rpp ) = @_;
    
    if ($rpp) {
        $self->{'_rpp'} = $rpp;
    }
    return $self->{'_rpp'} || 200;
}

sub pad {
    my( $self, $pad ) = @_;
    
    if ($pad) {
        $self->{'_pad'} = $pad;
    }
    return $self->{'_pad'} || 10;
}

sub clone_thickness {
    my( $self, $clone_thickness ) = @_;
    
    if ($clone_thickness) {
        $self->{'_clone_thickness'} = $clone_thickness;
    }
    return $self->{'_clone_thickness'} || 2;
}


sub gif {
    my( $self ) = @_;
    
    my $width  = $self->image_width;
    my $height = $self->image_height;
    my $img = $self->get_Image($width, $height);
    my $color = $self->color_index('black');
    
    my $rpp   = $self->rpp;
    my $pad   = $self->pad;
    my $inf_a = $self->a_Position->SequenceInfo;
    my $inf_b = $self->b_Position->SequenceInfo;
    my $over  = $self->overlap_length;
    
    my $len_a = $inf_a->sequence_length;
    my $len_b = $inf_b->sequence_length;
    
    # Set up origin
    my $x = $pad;
    my $y = $pad + $self->font->height;
    
    my @rect_a = ($x, $y, $x + ($len_a / $rpp), $y + $self->clone_thickness);
    $img->filledRectangle(@rect_a, $color);
    $self->draw_top_label($self->a_Position, @rect_a);
    
    # Move origin to draw second sequence
    $x += ($len_a - $over) / $rpp;
    $y += $pad;
    
    my @rect_b = ($x, $y, $x + ($len_a / $rpp), $y + $self->clone_thickness);
    $img->filledRectangle(@rect_b, $color);
    $self->draw_bottom_label($self->b_Position, @rect_b);
    
    return $img->gif;
}

sub get_Image {
    my( $self, $width, $height ) = @_;
    
    if ($width) {
        $self->{'_gd_image'} = GD::Image->new($width, $height);
        $self->setup_colors;
    }
    return $self->{'_gd_image'};
}

sub setup_colors {
    my( $self ) = @_;
    
    my $img = $self->get_Image;
    $self->{'_colors'}{'NavajoWhite'} = $img->colorAllocate(255,222,173);
    $self->{'_colors'}{'white'} = $img->colorAllocate(255,255,255);
    $self->{'_colors'}{'black'} = $img->colorAllocate(0,0,0);
    $self->{'_colors'}{'LightSeaGreen'} = $img->colorAllocate(32,178,170);
    
}

sub color_index {
    my( $self, $name ) = @_;
    
    confess "No name given" unless $name;
    my $i = $self->{'_colors'}{$name};
    if (defined $i) {
        return $i;
    } else {
        confess "No index for color '$name'";
    }
}

sub draw_top_label {
    my( $self, $pos, @rect ) = @_;
    
    my $color = $self->color_index('black');
    my $pad = $self->pad;
    my $img = $self->get_Image;
    my $inf = $pos->SequenceInfo;
    my $label = join('.', $inf->accession, $inf->sequence_version);
    my $font = $self->font;
    if ($pos->is_3prime) {
        my $poly = GD::Polygon->new;
        my($x, $y) = @rect[2,1];
        $poly->addPt($x, $y);
        $poly->addPt($x - $pad, $y);
        $poly->addPt($x - $pad, $y - $pad);
        $img->filledPolygon($poly, $color);
        
        ($x, $y) = @rect[0,1];
        $y -= $font->height;
        $img->string($font, $x, $y, $label, $color);
    } else {
        my $poly = GD::Polygon->new;
        my($x, $y) = @rect[0,1];
        $poly->addPt($x, $y);
        $poly->addPt($x + $pad, $y);
        $poly->addPt($x + $pad, $y - $pad);
        $img->filledPolygon($poly, $color);
        
        $x += $pad * 2;
        $y -= $font->height;
        $img->string($font, $x + (2 * $pad), $y, $label, $color);
    }
}

sub draw_bottom_label {
    my( $self, $pos, @rect ) = @_;
    
    my $color = $self->color_index('black');
    my $pad = $self->pad;
    my $img = $self->get_Image;
    my $inf = $pos->SequenceInfo;
    my $label = join('.', $inf->accession, $inf->sequence_version);
    my $font = $self->font;
    if ($pos->is_3prime) {
        my $poly = GD::Polygon->new;
        my($x, $y) = @rect[0,3];
        $poly->addPt($x, $y);
        $poly->addPt($x + $pad, $y);
        $poly->addPt($x + $pad, $y + $pad);
        $img->filledPolygon($poly, $color);
        
        $img->string($font, $x + (2 * $pad), $y + 1, $label, $color);
    } else {
        my $poly = GD::Polygon->new;
        my($x, $y) = @rect[2,3];
        $poly->addPt($x, $y);
        $poly->addPt($x - $pad, $y);
        $poly->addPt($x - $pad, $y + $pad);
        $img->filledPolygon($poly, $color);
        
        ($x, $y) = @rect[0,3];
        $img->string($font, $x, $y + 1, $label, $color);
    }
}

sub font {
    return gdLargeFont();
}

sub image_width {
    my( $self ) = @_;
    
    my $scale = $self->rpp;
    my $pad   = $self->pad;
    my $wid_1 = $self->a_Position->SequenceInfo->sequence_length;
    my $wid_2 = $self->a_Position->SequenceInfo->sequence_length;
    my $over  = $self->overlap_length;

    my $width = $wid_1 + $wid_2 - $over;
    return ($pad * 2) + ($width / $scale);
}


sub image_height {
    my( $self ) = @_;
    
    return $self->clone_thickness + (3 * $self->pad) + (2 * $self->font->height);
}

1;

__END__

=head1 NAME - Hum::SequenceOverlap::Cartoon

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

