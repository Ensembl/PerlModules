
### Hum::Ace::PolyA

package Hum::Ace::PolyA;

use strict;
use warnings;
use Carp;
use Hum::Ace::PolyA::Consensus;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub clone {
    my( $self ) = @_;
    
    my $new = ref($self)->new;
    $new->signal_position($self->signal_position);
    $new->site_position  ($self->site_position);
    $new->consensus      ($self->consensus);
    return $new;
}

sub find_best_in_SubSeq {
    my( $pkg, $sub, $site, $limit ) = @_;
    
    my @exons = $sub->get_all_Exons;
    my( $trim );
    if ($sub->strand == 1) {
        my $end = $exons[$#exons]->end;
        $site ||= $end;
        $trim = $end - $site;
    } else {
        my $end = $exons[0]->start;
        $site ||= $end;
        $trim = $site - $end;
    }
    
    my $seq = $sub->mRNA_Sequence;
    if ($trim) {
        my $end = $seq->sequence_length - $trim;
        $seq = $seq->sub_sequence(1, $end);
    }
    
    my @poly = $pkg->find_best_in_string($seq->sequence_string);
    foreach my $p (@poly) {
        my  ($sig_pos) = $sub->remap_coords_mRNA_to_genomic($p->signal_position);
        $p->signal_position($sig_pos);
        my ($site_pos) = $sub->remap_coords_mRNA_to_genomic($p->site_position);
        $p->site_position($site_pos);
    }
    
    # Were we asked for a maximum number of hits?
    if ($limit) {
        return @poly[0..$limit - 1];
    } else {
        return @poly;
    }
}

sub find_best_in_string {
    my( $pkg, $string ) = @_;
    
    my $len = length($string);
    my( @found );
    foreach my $cons (Hum::Ace::PolyA::Consensus->fetch_all) {
        my $signal = $cons->signal;
        my $pos = $len - $cons->scan_range_length;
        
        while (($pos = index($string, $signal, $pos)) > -1) {
            my $poly = $pkg->new;
            $poly->signal_position($pos + 1);
            $poly->site_position($len);
            $poly->consensus($cons);
            push(@found, $poly);
            $pos++;
        }
    }
    return sort {$b->score <=> $a->score} @found;
}

sub make_all_from_SubSeq_and_ace_tag {
    my( $pkg, $sub, $tag ) = @_;
    
    confess "Not implemented";
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

sub hexamer_end_position {
    my( $self ) = @_;
    
    my $site = $self->site_position
        or confess "No site_position";
    my $signal = $self->signal_position
        or confess "No signal_position";
    return $signal - $site + 5;
}

sub score {
    my( $self ) = @_;
    
    my $score = $self->{'_score'};
    unless (defined $score) {
        my $hex_pos = $self->hexamer_end_position;
        my $cons = $self->consensus
            or confess "No consensus";
        $self->{'_score'} = $score = 100 * $cons->score_for_position($hex_pos);
    }
    return $score;
}

sub hash_key {
    my( $self ) = @_;
    
    my $site_pos = $self->site_position;
    my $sig_pos  = $self->signal_position;
    my $signal   = $self->consensus->signal;
    return "$signal ($site_pos-$sig_pos)";
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

=item find_best_in_string( STRING )

This assumes that you are passing a lower case
nucleotide string that represents the mRNA.  It
scans the end of the string (end of the last
exon) and returns a list of candidate PolyA
obects in order of score, best to worst.

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
