=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Hum::Chromoview::TPF;

### Author: jt8@sanger.ac.uk

use strict;
use warnings;
use Hum::TPF;
use Hum::AGP;
use Hum::Chromoview::TPF::Row;

use Time::Piece; ### DEBUG

sub new {
    my ($class, $species, $chromosome, $subregion) = @_;
    my $self = {
        '_species' => $species,
        '_chromosome' => $chromosome,
        '_subregion' => $subregion,
    };
    return bless ($self, $class);
}

sub species {
    my ($self) = @_;
    return $self->{'_species'};
}

sub chromosome {
    my ($self) = @_;
    return $self->{'_chromosome'};
}

sub subregion {
    my ($self) = @_;
    return $self->{'_subregion'};
}

sub tpf {
    my ($self) = @_;
    
    if(exists($self->{'_tpf'})) {
        return $self->{'_tpf'};
    }
    else {
        $self->prepare_tpf;
        return $self->{'_tpf'}
    }
}

sub agp {
    my ($self) = @_;
    
    if(exists($self->{'_agp'})) {
        return $self->{'_agp'};
    }
    else {
        $self->prepare_agp;
        return $self->{'_agp'}
    }
}

sub agp_row_for_accession {
	my ($self, $query_accession) = @_;
	
	if(!exists($self->{'_agp_row_for_accession'})) {
    	foreach my $row ($self->agp->fetch_all_Rows) {
    		if(!$row->is_gap) {
    			my $accession_for_row = $row->accession_sv;
    			$accession_for_row =~ s/\..*//;
    			$self->{'_agp_row_for_accession'}{$accession_for_row} = $row;
    		}
    	}
	}

    if(exists($self->{'_agp_row_for_accession'}{$query_accession})) {
	   return $self->{'_agp_row_for_accession'}{$query_accession};
    }
    else {
        return undef;
    }
}

sub prepare_tpf {

    my($self) = @_;

    # fetch TPF
    my $tpf = $self->subregion ? Hum::TPF->current_from_species_chromsome_subregion($self->species, $self->chromosome, $self->subregion) :
    Hum::TPF->current_from_species_chromsome($self->species, $self->chromosome);

    $self->{'_tpf'} = $tpf;
    
    return;
}

sub prepare_agp {

    my($self) = @_;

    # fetch AGP
    my $agp = Hum::AGP->new;
    $agp->allow_dovetails(1);
    $agp->catch_errors(1);
    $agp->allow_unfinished(1);
    $agp->min_htgs_phase(2);
    $agp->chr_name($self->chromosome);
    $agp->verbose(0);
    $agp->process_TPF($self->tpf);

    $self->{'_agp'} = $agp;

    return;

}


sub fetch_all_TPF_Rows {
    my ($self) = @_;
    
    if(!exists($self->{'_tpf_rows'})) {
        my @rows = $self->tpf->fetch_all_Rows;
        $self->{'_tpf_rows'} = [];
        foreach my $row (@rows) {
            my $chromoview_row = Hum::Chromoview::TPF::Row->new($row);
            $chromoview_row->tpf($self);
            push(@{$self->{'_tpf_rows'}}, $chromoview_row);
        }
    }
    return @{$self->{'_tpf_rows'}};
}

sub fetch_non_contained_Rows {
    my ($self) = @_;

    if(!exists($self->{'_non_contained_tpf_rows'})) {
        my @rows = $self->tpf->fetch_non_contained_Rows;
        $self->{'_non_contained_tpf_rows'} = [];
        my $rank = 0;
        foreach my $row (@rows) {
            $rank++;
            my $chromoview_row = Hum::Chromoview::TPF::Row->new($row);
            $chromoview_row->tpf($self);
            $chromoview_row->rank($rank);
            if(!$row->is_gap) {
                $rank += scalar($row->get_contained_clones);
            }
            push(@{$self->{'_non_contained_tpf_rows'}}, $chromoview_row);
        }
    }
    return @{$self->{'_non_contained_tpf_rows'}};
}

sub DESTROY {
	my ($self) = @_;

	if(defined($self->{'_tpf'})) {
		$self->{'_tpf'}->disconnect();
		delete($self->{'_tpf'});
	}

	return;
}

1;

__END__

=head1 AUTHOR

James Torrance email B<jt8@sanger.ac.uk>
