
### Hum::TPF::Row::Gap

package Hum::TPF::Row::Gap;

use strict;
use base 'Hum::TPF::Row';
use Carp;


sub is_gap { return 1; }

sub type {
    my( $self, $type ) = @_;
    
    if ($type) {
        confess "Bad type '$type'" unless $type =~ /^[12345]$/;
        $self->{'_type'} = $type;
    }
    return $self->{'_type'};
}

sub type_string {
    my( $self ) = @_;
    
    my $type = $self->type or confess "type not set";
    if ($type == 5) {
        return 'CENTROMERE';
    } else {
        return "type-$type";
    }
}

sub gap_length {
    my( $self, $gap_length ) = @_;
    
    if ($gap_length) {
        $self->{'_gap_length'} = $gap_length;
    }
    return $self->{'_gap_length'} || '?';
}

sub string {
    my( $self ) = @_;
    
    return join("\t",
        'GAP',
        $self->type_string,
        $self->gap_length || '?')
        . "\n";
}



1;

__END__

=head1 NAME - Hum::TPF::Row::Gap

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

