
### Hum::AGP::Row::Clone

package Hum::AGP::Row::Clone;

use strict;
use Carp;
use base 'Hum::AGP::Row';


sub seq_start {
    my( $self, $seq_start ) = @_;
    
    if ($seq_start) {
        $self->check_positive_integer($seq_start);
        $self->{'_seq_start'} = $seq_start;
    }
    return $self->{'_seq_start'};
}

sub seq_end {
    my( $self, $seq_end ) = @_;
    
    if ($seq_end) {
        $self->check_positive_integer($seq_end);
        $self->{'_seq_end'} = $seq_end;
    }
    return $self->{'_seq_end'};
}

sub chr_length {
    my( $self ) = @_;
    
    return $self->seq_end - $self->seq_start + 1;
}

sub strand {
    my( $self, $strand ) = @_;
    
    if ($strand) {
        confess "Bad strand '$strand' (should be either '1' or '-1')"
            unless $strand =~ /^-?1$/;
        $self->{'_strand'} = $strand;
    }
    return $self->{'_strand'};
}

sub accession_sv {
    my( $self, $accession_sv ) = @_;
    
    if ($accession_sv) {
        $self->{'_accession_sv'} = $accession_sv;
    }
    return $self->{'_accession_sv'};
}

sub is_finished {
    my( $self, $is_finished ) = @_;
    
    if (defined $is_finished) {
        $self->{'_is_finished'} = $is_finished ? 1 : 0;
    }
    return $self->{'_is_finished'};
}


sub elements {
    my( $self ) = @_;
    
    unless ($self->strand) {
        confess "Strand not set\n";
    }
    
    return (
        $self->is_finished ? 'F' : 'U',     ### Is "U" correct?
        $self->accession_sv,
        $self->seq_start,
        $self->seq_end,
        $self->strand == 1 ? '+' : '-',
        );
}

1;

__END__

=head1 NAME - Hum::AGP::Row::Clone

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

