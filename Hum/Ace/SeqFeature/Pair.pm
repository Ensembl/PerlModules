
### Hum::Ace::SeqFeature::Pair

package Hum::Ace::SeqFeature::Pair;

use strict;
use warnings;
use Carp;
use Hum::Ace::SeqFeature;
use vars '@ISA';

@ISA = ('Hum::Ace::SeqFeature');


sub hit_name {
    my( $self, $hit_name ) = @_;
    
    if ($hit_name) {
        $self->{'_hit_name'} = $hit_name;
    }
    return $self->{'_hit_name'};
}

sub hit_start {
    my( $self, $hit_start ) = @_;
    
    if ($hit_start) {
        $self->{'_hit_start'} = $hit_start;
    }
    return $self->{'_hit_start'};
}

sub hit_end {
    my( $self, $hit_end ) = @_;
    
    if ($hit_end) {
        $self->{'_hit_end'} = $hit_end;
    }
    return $self->{'_hit_end'};
}

{
    my %allowed_strand = map {$_, 1} qw{ -1 0 1 };

    sub hit_strand {
        my( $self, $strand ) = @_;

        if (defined $strand) {
            confess "Illegal strand '$strand'"
                unless $allowed_strand{$strand};
            $self->{'_hit_strand'} = $strand;
        }
        return $self->{'_hit_strand'};
    }
}

sub hit_length {
    my( $self ) = @_;
    
    my $start = $self->hit_start;
    my $end   = $self->hit_end;
    return $end - $start + 1;
}

sub hit_Sequence {
    my( $self, $hit_seq ) = @_;
    
    if ($hit_seq) {
        unless (ref($hit_seq) and $hit_seq->isa('Hum::Sequence')) {
            confess "'$hit_seq' is not a Hum::Sequence";
        }
        $self->{'_hit_Sequence'} = $hit_seq;
    }
    return $self->{'_hit_Sequence'};
}

sub percent_identity {
    my( $self, $percent_identity ) = @_;
    
    if (defined $percent_identity) {
        $self->{'_percent_identity'} = $percent_identity;
    }
    return $self->{'_percent_identity'} || 0;
}

sub homol_tag {
    my( $self, $homol_tag ) = @_;
    
    if ($homol_tag) {
        $self->{'_homol_tag'} = $homol_tag;
    }
    return $self->{'_homol_tag'};
}

sub hit_overlaps {
    my( $self, $other ) = @_;
    
    if ($self->hit_end >= $other->hit_start
        and $self->hit_start <= $other->hit_end)
    {
        return 1;
    } else {
        return 0;
    }
}

sub pretty_string {
    my( $self ) = @_;
    
    return sprintf("  %6.2f%% %16s %6d %6d %16s %6d %6d  %s\n",
        $self->percent_identity,
        $self->seq_name,
        $self->seq_start,
        $self->seq_end,
        $self->hit_name,
        $self->hit_start,
        $self->hit_end,
        ($self->hit_strand == 1 ? '+' : '-'),
        );
}

{
    my $header = qq{\n}
    # 80:  ################################################################################
      . qq{ identity  query      name  start    end  subject    name  start    end  strand\n}
      . qq{ --------  -----------------------------  -------------------------------------\n};
    #         100.0%         dJ630J13      1  92514         dJ630J13      1  92514     REV
    

    sub pretty_header {
        return $header;
    }
}


1;

__END__

=head1 NAME - Hum::Ace::SeqFeature::Pair

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

