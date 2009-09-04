
### Hum::Blast::HSP

package Hum::Blast::HSP;

use strict;
use warnings;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub score {
    my( $self, $score ) = @_;
    
    if ($score) {
        $self->{'_score'} = $score;
    }
    return $self->{'_score'};
}

sub identity {
    my( $self, $identity ) = @_;
    
    if ($identity) {
        $self->{'_identity'} = $identity;
    }
    return $self->{'_identity'};
}

sub hsp_length {
    my( $self, $hsp_length ) = @_;
    
    if ($hsp_length) {
        $self->{'_hsp_length'} = $hsp_length;
    }
    return $self->{'_hsp_length'};
}

sub expect {
    my( $self, $expect ) = @_;
    
    if ($expect) {
        $self->{'_expect'} = $expect;
    }
    return $self->{'_expect'};
}

sub query_start {
    my( $self, $query_start ) = @_;
    
    if ($query_start) {
        $self->{'_query_start'} = $query_start;
    }
    return $self->{'_query_start'};
}

sub query_end {
    my( $self, $query_end ) = @_;
    
    if ($query_end) {
        $self->{'_query_end'} = $query_end;
    }
    return $self->{'_query_end'};
}

sub subject_start {
    my( $self, $subject_start ) = @_;
    
    if ($subject_start) {
        $self->{'_subject_start'} = $subject_start;
    }
    return $self->{'_subject_start'};
}

sub subject_end {
    my( $self, $subject_end ) = @_;
    
    if ($subject_end) {
        $self->{'_subject_end'} = $subject_end;
    }
    return $self->{'_subject_end'};
}

sub query_length {
    my( $self ) = @_;
    
    my $start = $self->query_start;
    my $end   = $self->query_end;
    if ($start < $end) {
        return $end - $start + 1;
    } else {
        return $start - $end + 1;
    }
}

sub subject_length {
    my( $self ) = @_;
    
    my $start = $self->subject_start;
    my $end   = $self->subject_end;
    if ($start < $end) {
        return $end - $start + 1;
    } else {
        return $start - $end + 1;
    }
}

1;

__END__

=head1 NAME - Hum::Blast::HSP

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

