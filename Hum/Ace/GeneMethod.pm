
### Hum::Ace::GeneMethod

package Hum::Ace::GeneMethod;

use strict;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
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
        $self->{'_is_mutable'} = $flag ? 1 : 0;
    }
    return $self->{'_is_mutable'};
}


1;

__END__

=head1 NAME - Hum::Ace::GeneMethod

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

