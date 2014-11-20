
### Hum::AGP::Row::Clone

package Hum::AGP::Row::Clone;

use strict;
use warnings;
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
    
    my $len = $self->seq_end - $self->seq_start + 1;
    if ($len < 1) {
        die sprintf("For sequence %s chr_length = $len which is less than 1! (start = %d  end = %d)\n",
            $self->accession_sv, $self->seq_start, $self->seq_end),
            "This sequence may be redundant, or its overlaps are wrong\n";
    }
    return $len;
}

sub strand {
    my( $self, $strand ) = @_;
    
    if ($strand) {
        confess "Bad strand '$strand' (should be either '1' or '-1')"
            unless $strand =~ /^-?1$/;
        $self->{'_strand'} = $strand;
    }
    
    if(!defined($self->{'_strand'})) {
    	return;
    }
    else {
    	return $self->{'_strand'};
    }
}

sub accession_sv {
    my( $self, $accession_sv ) = @_;
    
    if ($accession_sv) {
        $self->{'_accession_sv'} = $accession_sv;
    }
    return $self->{'_accession_sv'};
}

{
    my %type_phase = (
        'W' => 1,
        'D' => 1,
        'U' => 1,   # Ambiguous.  Used to mean "Unfinished", but now
                    # used by NCBI/GRC to mean a gap of unknown size
        'A' => 2,
        'F' => 3,
        );

    sub htgs_phase {
        my( $self, $htgs_phase ) = @_;
    
        if ($htgs_phase) {
            $self->{'_htgs_phase'} = $htgs_phase;
        }
        return $self->{'_htgs_phase'} || $type_phase{$self->phase_letter};
    }
}

sub phase_letter {
    my ($self, $letter) = @_;

    if ($letter) {
        $self->{'_phase_letter'} = $letter;
    }
    return $self->{'_phase_letter'} || 'O'; # "O" means "other type of sequence"
}

sub elements {
    my( $self ) = @_;
    
    unless ($self->strand) {
        confess sprintf "Strand not set for %s\n",
            $self->accession_sv;
    }
    
    my @ele = (
        $self->phase_letter,
        $self->accession_sv,
        $self->seq_start,
        $self->seq_end,
        $self->strand == 1 ? '+' : '-',
        );
#    if (my $rem = $self->remark) {
#        push(@ele, "# $rem");
#    }
    return @ele;
}

1;

__END__

=head1 NAME - Hum::AGP::Row::Clone

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

