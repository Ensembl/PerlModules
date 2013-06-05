package Hum::Chromoview::TPF::Row;

### Author: jt8@sanger.ac.uk

use strict;
use warnings;
use Hum::Chromoview::TPF;
use Hum::TPF::Row;

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

sub acc_sv {
    my ($self) = @_;
    
    my $acc_sv = '';
    if ($self->row->accession) {
        $acc_sv = $self->row->accession . "." . $self->row->SequenceInfo->sequence_version;
    }
    return $acc_sv;
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
	my $check_r      = eval{$self->row->SequenceInfo;};
	my $seq_len = eval {$check_r->sequence_length} ? $check_r->sequence_length : '-';
	return $seq_len;
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

sub data_for_chromoview {
    my ($self) = @_;
    
    if($self->row->is_gap) {
        return {
            contig => 'GAP',
        };
    }
    else {
        return {
                R=>1,
                contig=>$self->row->contig || '?',
                external_clone=>$self->row->intl_clone_name || '?',
                project=>undef,
                status=>undef,
                accession_and_finishing=>$self->row->accession . "/" . $self->finishing_status,
                length=> $self->sequence_length,
                library=> $self->library,
                
                accession=>$self->row->accession,
        };
    }
}

1;

__END__

=head1 AUTHOR

James Torrance email B<jt8@sanger.ac.uk>
