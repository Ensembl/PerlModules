
### Hum::Ace::GeneMethod

package Hum::Ace::GeneMethod;

use strict;
use Carp;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub new_from_ace_tag {
    my( $pkg, $tag ) = @_;
    
    my $self = $pkg->new;
    $self->name($tag->name);
    my $color = $tag->at('Display.Colour[1]')
        or confess "No color";
    $self->color($color->name);
    if (my $cds_color = $tag->at('Display.CDS_Colour[1]')) {
        $self->cds_color($cds_color->name);
    }
    return $self;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub color {
    my( $self, $color ) = @_;
    
    if ($color) {
        $self->{'_color'} = $color;
    }
    return $self->{'_color'};
}

sub cds_color {
    my( $self, $cds_color ) = @_;
    
    if ($cds_color) {
        $self->{'_cds_color'} = $cds_color;
    }
    return $self->{'_cds_color'};
}

sub is_mutable {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        my $value = $self->{'_is_mutable'};
        if (defined $value) {
            confess "attempt to change read-only property";
        } else {
            $self->{'_is_mutable'} = $flag ? 1 : 0;
        }
    }
    return $self->{'_is_mutable'};
}

sub is_coding {
    my( $self ) = @_;
    
    ### Bad to base on just method name
    my $name = $self->name;
    if ($name =~ /(pseudo|mrna)/i) {
        return 0;
    } else {
        return 1;
    }
}

1;

__END__

=head1 NAME - Hum::Ace::GeneMethod

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

