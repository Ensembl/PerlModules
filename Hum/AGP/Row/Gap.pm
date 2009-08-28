
### Hum::AGP::Row::Gap

package Hum::AGP::Row::Gap;

use strict;
use warnings;
use Carp;
use base 'Hum::AGP::Row';


sub chr_length {
    my( $self, $gap_length ) = @_;
    
    if ($gap_length) {
        $self->check_positive_integer($gap_length);
        $self->{'_gap_length'} = $gap_length;
    }
    return $self->{'_gap_length'} || confess "chr_length not set";
}

sub elements {
    my( $self ) = @_;
    
    my @ele = ('N', $self->chr_length);
    if (my $rem = $self->remark) {
        push(@ele, $rem);
    }
    return @ele;
}


{
    my %know_gap_type = map {$_, 1} qw{
        clone
        contig
        centromere
        short_arm
        heterochromatin
        telomere
        };

    sub set_remark_from_Gap {
        my( $self, $gap ) = @_;

        my $linkage = $gap->type <= 2 ? 'yes' : 'no';
        if (my $rem = $gap->remark) {
            if (my $known = $know_gap_type{lc $rem}) {
                $self->remark("$rem\t$linkage");
            } else {
                $self->remark("contig\t$linkage\t# $rem");
            }
        } else {
            $self->remark("contig\t$linkage");
        }
    }
}


1;

__END__

=head1 NAME - Hum::AGP::Row::Gap

=head1 GAP TYPES

From the NCBI web page (http://www.ncbi.nlm.nih.gov/Genbank/WGS.agpformat.html):

This column specifies the gap type. 
Fundamentally, there are two types of gaps,
captured and uncaptured.  In some cases,
uncaptured gaps are assigned biological value
(i.e. centromere).

=head1 Accepted values

=head2 Captured gaps

=over 4

=item * fragment

gap between two sequence contigs (also called a
"sequence gap").  This is the gap type between
contigs in an unfinished clone.

=back

=head2 Uncaptured gaps

=over 4

=item * clone

Gap between two clones that do not overlap.

=item * contig

Gap between clone contigs (also called a "layout
gap").  I don't understand how this can be
distinguished from a clone gap.  Maybe look at
fpc conting names?

=item * centromere

Gap inserted for the centromere.

=item * short_arm

Gap inserted at the start of an acrocentric
chromosome.

=item * heterochromatin

Gap inserted for an especially large region of
heterochromatin (may also include the
centromere).

=item * telomere

Gap inserted for the telomere.

=back

=head2 Linkage qualifier

This column indicates if there is evidence of
linkage between the adjacent lines.  Permitted
values are B<yes> or B<no>.

=head1 Definitions of tpf gap types

These are what we record in the GAPTYPEDICT table
in the tracking database:

=over 4

=item * type-1

sequence evidence for closure

=item * type-2

spanned by clones in map

=item * type-3

no spanning clones in map

=item * type-4

no spanning clones in any available library

=back

So the linkage qualifier should be set to B<yes>
for type 1 and 2 gaps, and to B<no> for types 3
and 4 (which might actually have linkage, but we
can't tell).

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

