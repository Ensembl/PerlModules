
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

1;

__END__

=head1 NAME - Hum::AGP::Row::Clone

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

