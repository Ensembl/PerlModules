
### Hum::TPF::Row::Clone

package Hum::TPF::Row::Clone;

use strict;
use base 'Hum::TPF::Row';

sub accession {
    my( $self, $accession ) = @_;
    
    if ($accession) {
        if ($accession eq '?') {
            $self->{'_accession'} = undef;
        } else {
            $self->{'_accession'} = $accession;
        }
    }
    return $self->{'_accession'};
}

sub intl_clone_name {
    my( $self, $intl ) = @_;
    
    if ($intl) {
        if ($intl eq '?') {
            $self->{'_intl_clone_name'} = undef;
        } else {
            $self->{'_intl_clone_name'} = $intl;
        }
    }
    return $self->{'_intl_clone_name'};
}

sub contig_name {
    my( $self, $contig_name ) = @_;
    
    if ($contig_name) {
        $self->{'_contig_name'} = $contig_name;
    }
    return $self->{'_contig_name'};
}

sub string {
    my( $self ) = @_;
    
    return join("\t",
        $self->accession       || '?',
        $self->intl_clone_name || '?',
        $self->contig_name     || '?')
        . "\n";
}


1;

__END__

=head1 NAME - Hum::TPF::Row::Clone

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

