
### Hum::TPF::Row::Gap

package Hum::TPF::Row::Gap;

use strict;


sub type {
    my( $self, $type ) = @_;
    
    if ($type) {
        confess "Bad type '$type'" unless $type =~ /^[12345]$/;
        $self->{'_type'} = $type;
    }
    return $self->{'_type'};
}

sub gap_length {
    my( $self, $gap_length ) = @_;
    
    if ($gap_length) {
        $self->{'_gap_length'} = $gap_length;
    }
    return $self->{'_gap_length'} || '?';
}

sub to_string {
    my( $self ) = @_;
    
    return join("\t",
        'GAP',
        $self->type,
        $self->gap_length)
        . "\n";
}



1;

__END__

=head1 NAME - Hum::TPF::Row::Gap

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

