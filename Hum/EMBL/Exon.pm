### Hum::EMBL::Exon
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

=head1 NAME Hum::EMBL::Exon

=head2 Description

Object used during the dumping of EMBL entries for finished genomic
sequence, to hold exon information.

These objects are added to a Hum::EMBL::ExonLocation object as part of
the process (see Bio::Otter::EMBL::Factory)

=cut

package Hum::EMBL::Exon;

use strict;
use Carp;

=head2 new

my $exon = Hum::EMBL::Exon->new;

=cut

sub new {
    my( $pkg ) = @_;
                                                                                 
    return bless {}, $pkg;
}

=head2 strand

Get/set method for the strand of the exon. 
Convention: forward strand +1, reverse strand -1. 
Same as Ensembl and others. This is checked
explicitly.

=cut

sub strand {
    my ($self, $value) = @_;

    if ($value) {
        unless (($value == -1) or ($value == 1)) {
            confess "Bad value for strand: $value";
        }
        $self->{_hum_embl_location_exon_strand} = $value;
    }
    return $self->{_hum_embl_location_exon_strand};
}

=head2 start

Get/set method for the position of the exon. Should be >= 1.
As this is  populated from Ensembl/Otter exons, start will always
be less than end.

=cut

sub start {
    my ($self, $value) = @_;
    
    if ($value) {
        $self->{_hum_embl_location_exon_start} = $value;
    }
    return $self->{_hum_embl_location_exon_start};
}

=head2 end

Get/set method for the position of the exon. Should be >= 1.
As this is copied from Ensembl/Otter exons, end will always
be greater than start.

=cut

sub end {
    my ($self, $value) = @_;
    
    if ($value) {
        $self->{_hum_embl_location_exon_end} = $value;
    }
    return $self->{_hum_embl_location_exon_end};
}

=head2 accession_version

Get/set method for the accession.version string for the clone
in which the exon is found/predicted.

  e.g. AL669831.13

=cut

sub accession_version {
    my ($self, $value) = @_;
    
    if ($value) {
        $self->{_hum_embl_location_exon_accession_version} = $value;
    }
    return $self->{_hum_embl_location_exon_accession_version};
}

1;

__END__
 
=head1 AUTHOR
 
Mike Croning B<email> mdr@sanger.ac.uk
