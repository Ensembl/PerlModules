### Hum::EMBL::Location::Exon
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

=head1 NAME Hum::EMBL::Location::Exon
 
=head2 Constructor:

 ??

=cut

package Hum::EMBL::Location::Exon;

use strict;
use Carp;

use vars '@ISA';
 
@ISA = ('Hum::EMBL::Location');

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

sub start {
    my ($self, $value) = @_;
    
    if ($value) {
        $self->{_hum_embl_location_exon_start} = $value;
    }
    return $self->{_hum_embl_location_exon_start};
}

sub end {
    my ($self, $value) = @_;
    
    if ($value) {
        $self->{_hum_embl_location_exon_end} = $value;
    }
    return $self->{_hum_embl_location_exon_end};
}

sub accession_version {
    my ($self, $value) = @_;
    
    if ($value) {
        $self->{_hum_embl_location_exon_accession_version} = $value;
    }
    return $self->{_hum_embl_location_exon_accession_version};
}

__END__
 
=head1 AUTHOR
 
Mike Croning B<email> mdr@sanger.ac.uk
