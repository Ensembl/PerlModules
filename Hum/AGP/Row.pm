
### Hum::AGP::Row

package Hum::AGP::Row;

use strict;
use Carp;

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}

sub is_gap {
    my( $self ) = @_;

    return ref($self) =~ /gap/i ? 1 : 0;
}

sub check_positive_integer {
    my( $self, $int ) = @_;
    
    confess "Not my kind of integer '$int'"
        unless $int =~ /^[1-9]\d*$/;
}

1;

__END__

=head1 NAME - Hum::AGP::Row

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

