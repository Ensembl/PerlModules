
### Hum::Ace::PolyA

package Hum::Ace::PolyA;

use strict;
use Carp;
use Hum::Ace::PolyA::Consensus;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub find_best {
    my( $pkg, $sub, $site, $limit ) = @_;
    
    confess "Not implemented";
}

sub make_all_from_SubSeq_and_ace_tag {
    my( $pkg, $sub, $tag ) = @_;
}

sub strand {
    my( $self, $strand ) = @_;
    
    if (defined $strand) {
        if ($strand == 1 or $strand == -1) {
            $self->{'_strand'} = $strand;
        } else {
            confess "Bad strand '$strand'";
        }
    }
    return $self->{'_strand'};
}

sub signal_position {
    my( $self, $pos ) = @_;
    
    if (defined $pos) {
        if ($pos > 0) {
            $self->{'_signal_position'} = $pos;
        } else {
            confess "Bad signal_position '$pos'";
        }
    }
    return $self->{'_signal_position'};
}

sub site_position {
    my( $self, $pos ) = @_;
    
    if (defined $pos) {
        if ($pos > 0) {
            $self->{'_site_position'} = $pos;
        } else {
            confess "Bad site_position '$pos'";
        }
    }
    return $self->{'_site_position'};
}

sub consensus {
    my( $self, $cons ) = @_;
    
    if ($cons) {
        $self->{'_consensus'} = $cons;
    }
    return $self->{'_consensus'};
}

sub ace_string_for_SubSeq {
    my( $self, $sub ) = @_;
    
    confess "Not implemented";
}

1;

__END__

=head1 NAME - Hum::Ace::PolyA

=head1 CLASS METHODS

=over 4

=item new

Returns a new empty object.

=item find_best( SUBSEQ, SITE_POSITION, LIMIT )

Given a B<Hum::Ace::Subseq> object, returns the
best B<Hum::Ace::PolyA> canditates in order of
score.  Score is calculated using the statistics
presented in B<Beaudoing et al, Genome Research,
10:1001-1010, (2000)>.  The sequence is searched
within 3 standard deviations either side of the
mean site position for each hexamer consensus.

=item make_all_from_SubSeq_and_ace_tag( SUBSEQ, ACE_SUBSEQ )

Given a B<Hum::Ace::Subseq> object and its
B<Ace::Object> AcePerl object, it returns a list
of PolyA objects made from the features under the
Feature tag (if any).

=back

=head1 INSTANCE METHODS

=over 4

=item strand

Set to either 1 or -1, for forward or reverse
strand of the genomic sequence respectively.

=item signal_position

The position of the first base of the hexamer
signal in the genomic sequence.

=item site_position

The position of the last genomic base represented
in the transcript before the poly(A) tail.

=item ace_string_for_SubSeq( SUBSEQ )

Given a B<Hum::Ace::Subseq> object, returns an
ace file format string giving the location of
polyA_signal and polyA_site Features in
post-splice transcript coordinate space (which is
what fMap needs to display the features in the
correct location).

=back

=head1 NOTES

I think there should be a base class which deals
with genomic -> spliced transcript coordinate
mapping.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

[qw{  aataaa    3286    16  4.7  }],
[qw{  attaaa     843    17  5.3  }],
[qw{  agtaaa     156    16  5.9  }],
[qw{  tataaa     180    18  7.8  }],
[qw{  cataaa      76    17  5.9  }],
[qw{  gataaa      72    18  6.9  }],
[qw{  aatata      96    18  6.9  }],
[qw{  aataca      70    18  8.7  }],
[qw{  aataga      43    18  6.3  }],
[qw{  aaaaag      49    18  8.9  }],
[qw{  actaaa      36    17  8.1  }],
