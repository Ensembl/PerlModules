
### Hum::AGP::Row::Gap

package Hum::AGP::Row::Gap;

use strict;
use Carp;
use base 'Hum::AGP::Row';


sub chr_length {
    my( $self, $gap_length ) = @_;
    
    if ($gap_length) {
        $self->check_positive_integer($gap_length);
        $self->{'_gap_length'} = $gap_length;
    }
    return $self->{'_gap_length'} || confess "chr_length not set";
}

sub elements {
    my( $self ) = @_;
    
    return('N', $self->chr_length);
}

1;

__END__

=head1 NAME - Hum::AGP::Row::Gap

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

