### Hum::EMBL::ExonLocation
#
# Copyright 2004 Genome Research Limited (GRL)
#
# Maintained by Mike Croning <mdr@sanger.ac.uk>
#
# You may distribute this file/module under the terms of the perl artistic
# licence
#
# POD documentation main docs before the code. Internal methods are usually
# preceded with a _
#

=head1 NAME Hum::EMBL::ExonLocation
 
=head2 Description

Created by the Bio::Otter::EMBL::Factory object, as part of the process of building
up FT lines to annotate a finished genomic clone sequence, from an Otter database.

Hum::EMBL::ExonLocation objects are created to annotate the mRNA and CDS of each
Transcript, for all the Genes on the clone sequence.

  my $mRNA_exon_location = Hum::EMBL::ExonLocation->new;

  then add exons:

  $mRNA_exon_location->exons(@exons); #Array of Hum::EMBL::Exon objects.

=cut

package Hum::EMBL::ExonLocation;

use Carp;
use strict;

=head2 new

Constructor:

 my $collection = Hum::EMBL::ExonLocation->new;

=cut

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}

=head2 exons

Get/set method for the list of 
Hum::EMBL::Exon objects.

=cut

sub exons {
    my( $loc, @exons ) = @_;
    
    if (@exons) {
        $loc->{'_hum_embl_exonlocation_exons'} = [@exons];
    } else {
        return @{$loc->{'_hum_embl_exonlocation_exons'}};
    }
}

=head2 start

=cut

sub start {
    my( $self, $value ) = @_;

    if ($value) {
        $self->{_hum_embl_exonlocation_start} = $value;
    }
    return $self->{_hum_embl_exonlocation_start};
}

=head2 end

=cut

sub end {
    my( $self, $value ) = @_;

    if ($value) {
        $self->{_hum_embl_exonlocation_end} = $value;
    }
    return $self->{_hum_embl_exonlocation_end};
}

=head2 start_not_found

=cut

sub start_not_found {
    my( $self, $value ) = @_;
    
    if ($value) {
        $self->{_hum_embl_exonlocation_start_not_found} = $value;
    }
    return $self->{_hum_embl_exonlocation_start_not_found};
}

=head2 end_not_found

=cut

sub end_not_found {
    my( $self, $value ) = @_;
    
    if ($value) {
        $self->{_hum_embl_exonlocation_end_not_found} = $value;
    }
    return $self->{_hum_embl_exonlocation_end_not_found};
}

sub parse {
    my( $loc, $s ) = @_;
    
    confess "This needs to be completely written";
    
    # If the location contains multiple complement
    # tags, then the order of the exons will need
    # to be reversed
    my $C_count = 0;
    while ($$s =~ /complement/g) {
        $C_count++;
    }
    if ($C_count) {
        $loc->strand('C');
    } else {
        $loc->strand('W');
    }
    
    $loc->missing_5_prime(1) if $$s =~ /</;
    $loc->missing_3_prime(1) if $$s =~ />/;
    
    my( @exons );
    while ($$s =~ /(\d+)\.\.>?(\d+)/g) {
        push( @exons, [$1, $2] );
    }
    if (@exons) {
        if ($C_count > 1) {
            @exons = reverse @exons;
        }
        $loc->exons(@exons);
    } elsif (my ($i) = $$s =~ /(\d+)/) {
        # Single base pair
        $loc->exons($i);
    } else {
        confess "Can't parse location string '$$s'";
    }
}

=head2 hash_key

Generate a string based on: start, end and strand properties
of the Hum:EMBL::Exon objects contained by the ExonLocation
and start_not_found, and end_not_found

e.g. For a mRNA/CDS with t2 exons:

 153811_154573_1_155134_155215_1_0_0

start1, end1, strand1, start2, end2, strand2, start_not_found, end_not_found

=cut

sub hash_key {
    my( $self ) = @_;

    my @exons = $self->exons;
    
    my $key;
    foreach my $exon (@exons) {
        $key .= $exon->start . '_' . $exon->end . '_' . $exon->strand . '_'; 
    }
    
    $self->start_not_found ? $key .= '1' : $key .= '0';
    $self->end_not_found   ? $key .= '_1' : $key .= '_0';
    return $key;
}

BEGIN {
    my $joiner = "\nFT". ' ' x 19;

    sub compose {
        my( $self ) = @_;

        my $text;
        my @exons = $self->exons;
        $text = 'join(' unless @exons == 1; #Don't need the 'join(' if single exon

        for (my $i = 0; $i <= $#exons; $i++) {
        
            my $exon = $exons[$i];
            
            my $exon_text;
            if ($exon->accession_version) {
                $exon_text .= $exon->accession_version . ':';
            }

            #Do we need a start not found '<'
            if (($i == 0) and $self->start_not_found) {
                $exon_text .= '<' . $exon->start .  '..';
            } else {
                $exon_text .= $exon->start .  '..';
            }

            #Do we need an end not found '>'
            if (($i == $#exons) and $self->end_not_found) {
                $exon_text .= '>' . $exon->end;
            } else {
                $exon_text .= $exon->end;
            }
            
            #Check strand
            if ($exon->strand == -1) {
                $exon_text = 'complement(' . $exon_text . ')';
            }
            $exon_text .= ',';
            $text .= $exon_text;
        }
        chop ($text);
        $text .= ')' unless @exons == 1;

        my( @lines );
        while ($text =~ /(.{1,58}(,|$))/g) {
            push(@lines, $1);
        }

        return join($joiner, @lines) ."\n";
    }
}

sub add_location_qualifier {
    my( $loc, $qualifier ) = @_;
    
    $loc->{'_location_qualifers'} ||= [];
    push(@{$loc->{'_location_qualifers'}}, $qualifier);
}

sub location_qualifiers {
    my( $loc ) = @_;
    
    if (my $q = $loc->{'_location_qualifers'}) {
        return @$q;
    } else {
        return;
    }
}

1;

__END__


