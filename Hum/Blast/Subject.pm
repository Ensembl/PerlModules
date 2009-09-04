
### Hum::Blast::Subject

package Hum::Blast::Subject;

use strict;
use warnings;
use Hum::Blast::HSP;

sub new {
    my( $pkg ) = @_;
    
    return bless {
        _HSP_list => [],
        }, $pkg;
}

sub subject_length {
    my( $self, $length ) = @_;
    
    if ($length) {
        $self->{'_subject_length'} = $length;
    }
    return $self->{'_subject_length'};
}

sub subject_name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_subject_name'} = $name;
    }
    return $self->{'_subject_name'};
}

sub new_HSP {
    my( $self ) = @_;
    
    my $hsp = Hum::Blast::HSP->new;
    push( @{$self->{'_HSP_list'}}, $hsp );
    return $hsp;
}

sub sort_HSPs_by_query_start_end {
    my( $self ) = @_;
    
    @{$self->{'_HSP_list'}} = sort {
        $a->query_start <=> $b->query_start
            ||
          $a->query_end <=> $b->query_end
        } @{$self->{'_HSP_list'}};
}

sub get_all_HSPs {
    my( $self ) = @_;
    
    return @{$self->{'_HSP_list'}};
}

sub count_HSPs {
    my( $self ) = @_;
    
    return scalar @{$self->{'_HSP_list'}};
}

sub total_score {
    my( $self ) = @_;
    
    my $total = 0;
    foreach my $hsp ($self->get_all_HSPs) {
        $total += $hsp->score;
    }
    return $total;
}

sub total_identity {
    my( $self ) = @_;
    
    my $identity = 0;
    my $length   = 0;
    foreach my $hsp ($self->get_all_HSPs) {
        $identity += $hsp->identity;
        $length   += $hsp->hsp_length;
    }
    return $identity / $length;
}

sub min_expect {
    my( $self ) = @_;
    
    my( $expect );
    foreach my $hsp ($self->get_all_HSPs) {
        my $e = $hsp->expect;
        $expect = $e unless defined $expect;
        $expect = $e if $e < $expect;
    }
    return $expect;
}

1;

__END__

=head1 NAME - Hum::Blast::Subject

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

