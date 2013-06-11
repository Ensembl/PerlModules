package Hum::Chromoview::TPF::Row;

### Author: jt8@sanger.ac.uk

use strict;
use warnings;
use Hum::Chromoview::TPF;
use Hum::TPF::Row;
use Hum::CloneProject;

sub new {
    my ($class, $row) = @_;
    my $self = {
        '_row' => $row,
    };
    return bless ($self, $class);
}

sub row {
    my ($self) = @_;
    return $self->{'_row'};
}

sub tpf {
    my ($self, $tpf) = @_;
    if($tpf) {
        $self->{'_tpf'} = $tpf;
    }
    return $self->{'_tpf'};
}

sub acc_sv {
    my ($self) = @_;
    
    if(!exists($self->{'_acc_sv'})) {
    
        my $acc_sv = '';
        if ($self->row->accession) {
            $self->{'_acc_sv'} = $self->row->accession . "." . $self->row->SequenceInfo->sequence_version;
        }
    }
    return $self->{'_acc_sv'};
}

sub finishing_status {
    my ($self) = @_;

    my $finishing_status_for_phase = {
        1 => 'unfinished',
        2 => 'contiguous',
        3 => 'finished'
    };

    eval{ $self->row->SequenceInfo->htgs_phase };
    my $fin_status = $@ ? '-' : $finishing_status_for_phase->{$self->row->SequenceInfo->htgs_phase};

    return $fin_status;
}

sub sequence_length {
    my ($self) = @_;
    
    if(!exists($self->{'_sequence_length'})) {
        
    	my $check_r = eval{$self->row->SequenceInfo;};
    	$self->{'_sequence_length'} = eval {$check_r->sequence_length} ? $check_r->sequence_length : '-';
    }
	return $self->{'_sequence_length'};
}

sub contained_status {
    my ($self, $contained_status) = @_;
    
    if($contained_status) {
        $self->{'_contained_status'} = $contained_status;
    }
    ## THIS IS PROBABLY TEMPORARY- PROVIDE DEFAULT STATUS
    elsif(!exists($self->{'_contained_status'})) {
        $self->{'_contained_status'} = 'NOT_CONTAINED';
    }
    
	return $self->{'_contained_status'};
}

## THIS MIGHT NEED SHIFTING TO OVERLAP OBJECT, OR OTHERWISE CHANGING
sub container_strand {
    my ($self, $container_strand) = @_;
    
    if($container_strand) {
        $self->{'_container_strand'} = $container_strand;
    }
    ## THIS IS PROBABLY TEMPORARY- PROVIDE DEFAULT STRAND
    elsif(!exists($self->{'_container_strand'})) {
        $self->{'_container_strand'} = 1;
    }
    
	return $self->{'_container_strand'};
}


sub build_library_and_clone {
    my ($self) = @_;
    
	my ($clonename, $lib) = $self->row->get_sanger_clone_and_libraryname_from_intl_name($self->row->intl_clone_name);
	$lib =~ s/_/ /g;
	$lib = '-' unless $lib;
	
    # some clones may have been splitted, use sequence table for projectname
	# instead of Hum::CloneProject::fetch_projectname_from_clonename($clonaname)
	# as this is querying clone_project table, which may not have relevant info
	my $projname;
	eval {
    	$projname = Hum::CloneProject::fetch_projectname_from_clonename($clonename) ||
        	$self->row->SequenceInfo->projectname;
	};
    $clonename = $self->row->sanger_clone_name unless $clonename;
    if ( defined $projname and defined $clonename and $projname ne $clonename ) {
    	my $swap = "Clone ($clonename) - Project ($projname) swap";
    	$clonename = $swap;
	}
    
	
	$self->{'_library'} = $lib;
	$self->{'_clonename'} = $clonename;
	$self->{'_projectname'} = $projname;
    
    return;
}

sub library {
    my ($self) = @_;
    
    if(!exists($self->{'_library'})) {
    	my ($clonename, $lib) = $self->row->get_sanger_clone_and_libraryname_from_intl_name($self->row->intl_clone_name);
    	$lib =~ s/_/ /g;
    	$lib = '-' unless $lib;
    	$self->{'_library'} = $lib;
    }
    	
	return $self->{'_library'};
}

sub clonename {
    my ($self) = @_;
    
    if(!exists($self->{'_clonename'})) {
        $self->build_library_and_clone;
    }
    return $self->{'_clonename'};
}

sub projectname {
    my ($self) = @_;
    
    if(!exists($self->{'_projectname'})) {
        $self->build_library_and_clone;
    }
    return $self->{'_projectname'};
}

sub project_status {
    my ($self) = @_;
    
    if(!exists($self->{'_project_status'})) {
        $self->build_status;
    }
    return $self->{'_project_status'};
}

sub project_status_date {
    my ($self) = @_;
    
    if(!exists($self->{'_project_status_date'})) {
        $self->build_status;
    }
    return $self->{'_project_status_date'};
}

sub build_status {
    my ($self) = @_;
    
    my ($status, $statusdate) = Hum::CloneProject::fetch_project_status($self->projectname);
    $status = $statusdate = '-' unless $self->projectname;
    
    $self->{'_project_status'} = $status;
    $self->{'_project_status_date'} = $statusdate;
    
    return;
}

sub gap_string {
    my ($self) = @_;
    
	my $type = $self->row->type_string;
	my $length = ($self->row->gap_length) ? ("length " . $self->row->gap_length ." bps")
	: 'length unknown';

	#$tpfGaps->{$rank}++;

	my $gapinfo = 'GAP'." ($type) " . $length;
    return $gapinfo;
}

sub external_clone_and_contig {
    my ($self) = @_;
    
    my $pgp_link = "http://pgpviewer.ensembl.org/PGP_" . lc($self->tpf->species) . "/Location/View?region=" . $self->row->accession;
    
    return qq{<a href="$pgp_link">} . $self->row->intl_clone_name . "</a><BR>" . $self->row->contig_name;
}

sub accession_and_finishing {
    my ($self) = @_; 
    
    #my $oracle_report_link = "http://intweb.sanger.ac.uk/cgi-bin/oracle_reports/report.pl?Internal_Name=" . $self->projectname;
    my $ena_link = "http://www.ebi.ac.uk/cgi-bin/emblfetch?style=html&id=" . $self->row->accession;
    
    return qq{<a href="$ena_link">} . $self->acc_sv . "</A><BR>" . $self->finishing_status;
}

sub data_for_chromoview {
    my ($self) = @_;
    
    if($self->row->is_gap) {
        return {
            external_clone_and_contig => $self->gap_string,
        };
    }
    else {
        return {
                #contig=>$self->row->contig_name || '?',
                #external_clone=>$self->row->intl_clone_name || '?',
                external_clone_and_contig=>$self->external_clone_and_contig,
                internal_clone=>$self->clonename,
                project_status_and_date=>$self->project_status . "<BR>" . $self->project_status_date,
                accession_and_finishing=> $self->accession_and_finishing,
                length=> $self->sequence_length,
                library=> $self->library,
                
                accession=>$self->row->accession,
                projectname=>$self->projectname,
        };
    }
}

1;

__END__

=head1 AUTHOR

James Torrance email B<jt8@sanger.ac.uk>
