### Hum::EMBL::ExonCollection
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

=head1 NAME Hum::EMBL::ExonCollection
 
=head2 Description

Created by the Bio::Otter::EMBL::Factory object, as part of the process of building
up FT lines to annotate a finished genomic clone sequence, from an Otter database.

Hum::EMBL::ExonCollection objects are created to annotate the mRNA and CDS of each
Transcript, for all the Genes on the clone sequence.

  my $mRNA_exon_collection = Hum::EMBL::ExonCollection->new;

  $mRNA_exon_collection->exons(@exons); #Array of Hum::EMBL::Exon objects.

=cut

package Hum::EMBL::ExonCollection;

use Carp;
use strict;

=head2 new

Constructor:

 my $collection = Hum::EMBL::ExonCollection->new;

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
        $loc->{'_hum_embl_exoncollection_exons'} = [@exons];
    } else {
        return @{$loc->{'_hum_embl_exoncollection_exons'}};
    }
}

=head2 missing_5_prime

Get/set method for the missing_5_prime flag

=cut

sub missing_5_prime {
    my( $loc, $value ) = @_;
    
    if (defined $value) {
        $loc->{'_hum_embl_exoncollection_missing_5_prime'} = $value;
    } else {
        return $loc->{'_hum_embl_exoncollection_missing_5_prime'};
    }
}

=head2 missing_3_prime

Get/set method for the missing_3_prime flag

=cut

sub missing_3_prime {
    my( $loc, $value ) = @_;
    
    if (defined $value) {
        $loc->{'_hum_embl_exoncollection_missing_3_prime'} = $value;
    } else {
        return $loc->{'_hum_embl_exoncollection_missing_3_prime'};
    }
}

sub start {
    my( $self, $value ) = @_;

    if ($value) {
        $self->{_hum_embl_exoncollection_start} = $value;
    }
    return $self->{_hum_embl_exoncollection_start};
}

sub end {
    my( $self, $value ) = @_;

    if ($value) {
        $self->{_hum_embl_exoncollection_end} = $value;
    }
    return $self->{_hum_embl_exoncollection_end};
}


sub start_not_found {
    my( $self ) = @_;
    
    if ($self->strand eq 'W') {
        $self->missing_5_prime(1);
    } elsif ($self->strand eq 'C') {
        $self->missing_3_prime(1);
    } else {
        confess "Direction not specified";
    }
}

sub end_not_found {
    my( $self ) = @_;
    
    if ($self->strand eq 'W') {
        $self->missing_3_prime(1);
    } elsif ($self->strand eq 'C') {
        $self->missing_5_prime(1);
    } else {
        confess "Direction not specified";
    }
}


sub length {
    my( $self ) = @_;
    
    confess "length got called";
    
    return $self->three_prime - $self->five_prime + 1;
}

=head2 five_prime

Return the start of the first Hum::EMBL::Location::Exon
object, or confess should none exist

=cut

sub five_prime {
    my( $self ) = @_;
    
    if (my $exon = $self->{'exons'}[0]) {
        return $exon->start;
    } else {
        confess "No start position";
    }
}

=head2 three_prime

Return the end of the first Hum::EMBL::Location::Exon
object, or confess should none exist

=cut

sub three_prime {
    my( $self ) = @_;
    
    if (my $exon = $self->{'exons'}[-1]) {
        return $exon->end;
    } else {
        confess "No end position";
    }
}

sub parse {
    my( $loc, $s ) = @_;
    
    confess "This needs to be fixed";
    
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

# Generates a unique string for a location
sub hash_key {
    my( $loc ) = @_;

    warn "This needs to be changed\n";
    my @exons = $loc->exons;
        
    my( @key );
    if (ref($loc->{'exons'}[0])) {
        @key = map @$_, @{$loc->{'exons'}};
    } else {
        @key = @{$loc->{'exons'}};
    }
    
    return join '_', ($loc->{'strand'}, @key,
        $loc->{'missing_5_prime'},
        $loc->{'missing_3_prime'});
}

BEGIN {
    my $joiner = "\nFT". ' ' x 19;

    sub compose {
        my( $self ) = @_;

        my $text;
        my( @exons ) = $self->exons;
        $text = 'join(' unless @exons == 1; #Don't need the join if its single exon

        foreach my $exon (@exons) {
            
            my $exon_text;
            if ($exon->accession_version) {
                $exon_text .= $exon->accession_version . ':';
            }
            $exon_text .= $exon->start .  '..' . $exon->end;
            
            if ($exon->strand == -1) {
                $exon_text = 'complement(' . $exon_text . ')';
            }
            $exon_text .= ',';
            $text .= $exon_text;
        }
        chop ($text);
        $text .= ')' unless @exons == 1;
        
   #     if (ref $exons[0]) {
   #         if ($self->missing_5_prime) {
   #             my $i = $exons[0][0];
   #             $exons[0][0] = "<$i";
   #         }
   #         if ($self->missing_3_prime) {
   #            my $i = $exons[$#exons][1];
   #            $exons[$#exons][1] = ">$i";
   #         }
   #         
   #         if (@exons == 1) {
   #             $text = "$exons[0][0]..$exons[0][1]";
   #         } else {
   #             $text = 'join('. join(',', map "$_->[0]..$_->[1]", @exons) .')';
   #         }
   #    } else {
   #         $text = $exons[0];
   #         if ($self->missing_5_prime) {
   #             $text = "<$text";
   #        } elsif ($self->missing_3_prime) {
   #            $text = ">$text";
   #        }
   #    }

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

