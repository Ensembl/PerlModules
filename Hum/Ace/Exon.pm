
### Hum::Ace::Exon

package Hum::Ace::Exon;

use strict;
use warnings;
use Carp;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub clone {
    my( $old ) = @_;
    
    my $new = ref($old)->new;
    foreach my $meth (qw{
        start
        end
        phase
        otter_id
        })
    {
        $new->$meth($old->$meth());
    }
    return $new;
}

sub otter_id {
    my( $self, $otter_id ) = @_;
    
    if ($otter_id) {
        $self->{'_otter_id'} = $otter_id;
    }
    return $self->{'_otter_id'};
}

sub drop_otter_id {
    my ($self) = @_;
    
    $self->{'_otter_id'} = undef;
}

sub start {
    my( $self, $start ) = @_;
    
    if (defined $start) {
        confess "Illegal start '$start'; must be positive integer greater than zero"
            unless $start =~ /^[1-9]\d*$/;
        $self->{'_start'} = $start;
    }
    return $self->{'_start'} || confess "start not set";
}

sub end {
    my( $self, $end ) = @_;
    
    if (defined $end) {
        confess "Illegal end '$end'; must be positive integer greater than zero"
            unless $end =~ /^[1-9]\d*$/;
        $self->{'_end'} = $end;
    }
    return $self->{'_end'} || confess "end not set";
}

# Used to use EnsEMBL convention:
#sub phase {
#    my( $self, $phase ) = @_;
#    
#    if (defined $phase) {
#        confess "Illegal phase '$phase'; must be one of (0,1,2)"
#            unless $phase =~ /^[012]$/;
#        $self->{'_phase'} = $phase;
#    }
#    return $self->{'_phase'};
#}

sub unset_phase {
    my( $self ) = @_;
    
    $self->{'_phase'} = undef;
}

sub phase {
    my( $self, $phase ) = @_;
    
    if (defined $phase) {
        confess "Illegal phase '$phase'; must be one of (1,2,3)"
            unless $phase =~ /^[123]$/;
        $self->{'_phase'} = $phase;
    }
    return $self->{'_phase'};
}

sub ensembl_phase {
    my( $self, $arg ) = @_;
    
    if (defined $arg) {
        confess "ensembl_phase is read-only";
    }
    if (my $ace_phase = $self->phase) {
        return( (3 - ($ace_phase - 1)) % 3 );
    } else {
        return;
    }
}

sub overlaps {
    my( $self, $other ) = @_;
    
    confess "no other" unless $other;
    
    if ($self->end < $other->start
        or $self->start > $other->end)
    {
        return 0;
    } else {
        return 1;
    }
}

sub contains {
    my( $self, $other ) = @_;
    
    if ($self->start <= $other->start
        and $self->end >= $other->end)
    {
        return 1;
    } else {
        return 0;
    }
}

sub matches {
    my( $self, $other ) = @_;
    
    if ($self->start == $other->start
        and $other->end == $other->end)
    {
        return 1;
    } else {
        return 0;
    }
}

sub length {
    my( $self ) = @_;
    
    return $self->end - $self->start + 1;
}



1;

__END__

=head1 NAME - Hum::Ace::Exon

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

