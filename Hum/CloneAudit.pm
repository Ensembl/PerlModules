package Hum::CloneAudit;
use strict;
use warnings;
use Moose;
use Carp;
use DBI;
use DateTime;
use Hum::Submission qw{seq_id_from_project_name sanger_id_from_project_name};
use Hum::ChromosomeAudit::DBI;
use Hum::CloneProject qw{fetch_projectname_from_clonename fetch_project_status};
use Hum::Pfetch qw{get_EMBL_entries};
use Hum::ProjectDump::EMBL;

=head2 Hum::CloneAudit module

	Audits various features of a clone.

=cut

has 'clonename' => (
	is  => 'ro',
	isa => 'Str',
	required => 1,
);

has 'accession' => (
	is  => 'ro',
	isa => 'Str',
	required => 1,
);

has 'dbi' => (
    is  => 'ro',
    isa => 'Hum::ChromosomeAudit::DBI',
    required => 1,
);

has 'projectname' => (
	is  => 'ro',
	isa => 'Maybe[Str]',
	lazy_build => 1,
);

has 'organisation' => (
    is  => 'ro',
    isa => 'Str',
    lazy_build => 1,
);

has 'verbose' => (
    is  => 'ro',
    isa => 'Bool',
    default => 0,
);

has 'embl_entry' => (
	is => 'ro',
	isa => 'Maybe[Hum::EMBL]',
	lazy_build => 1,
);

has 'embl_date' => (
	is => 'ro',
	isa => 'Maybe[DateTime]',
	lazy_build => 1,
);

has 'submissions_seq_id' => (
	is => 'ro',
	isa => 'Maybe[Int]',
	lazy_build => 1,
);

has 'submissions_date' => (
	is => 'ro',
	isa => 'Maybe[DateTime]',
	lazy_build => 1,
);

has 'project_status' => (
	is => 'ro',
	isa => 'Maybe[Str]',
	lazy_build => 1,
);

has 'project_date' => (
	is => 'ro',
	isa => 'Maybe[DateTime]',
	lazy_build => 1,
);

has 'sanger_sequence' => (
	is => 'ro',
	isa => 'Maybe[Str]',
	lazy_build => 1,
);

has 'embl_sequence' => (
	is => 'ro',
	isa => 'Maybe[Str]',
	lazy_build => 1,
);

has 'project_dump' => (
	is => 'ro',
	isa => 'Maybe[Hum::ProjectDump]',
	lazy_build => 1,
);

sub _build_project_status {
	my ($self) = @_;

	my ($project_status, $project_status_date) = fetch_project_status($self->projectname);
	
	return $project_status;
}

# NB This has redundancy with the project_status builder, but it doesn't appear to be worth the fuss of eliminating it
sub _build_project_date {
	my ($self) = @_;

	my ($project_status, $project_status_date_string) = fetch_project_status($self->projectname);
	
	my $date_time;
	if($project_status_date_string =~ /^(\d+)-(.{3})-(\d+)$/) {
		my $day = $1;
		my $month_string = $2;
		my $year_last_two_digits = $3;
		
		my $year;
		if($year_last_two_digits < 80) {
			$year = 2000 + $year_last_two_digits;
		}
		else {
			$year = 1900 + $year_last_two_digits;
		}
		
		my $month_number = $self->three_letter_month_to_number($month_string);
		if(defined($month_number)) {
			$date_time = DateTime->new(
				year       => $year,
				month      => $month_number,
				day        => $day,
			);
		}
	}
	
	return $date_time;
}

sub _build_project_dump {
	my ($self) = @_;
	
	my $sanger_id = sanger_id_from_project_name($self->projectname);
	
	my $pdmp;
	if(!defined($sanger_id)) {
		warn "Cannot create project dump because no Sanger ID available for project " . $self->projectname . "\n";
	}
	else {
		eval {
			$pdmp = Hum::ProjectDump::EMBL->new_from_sanger_id($sanger_id);
			$pdmp->set_ghost_path;
			$pdmp->read_fasta_file;
		};
		if($@) {
			$pdmp = undef;
		}
	}
	
	return $pdmp;
}

sub _build_sanger_sequence {
	my ($self) = @_;
	
	my $sequence;
	
	if(defined($self->project_dump)) {
		eval {
			($sequence) = $self->project_dump->embl_sequence_and_contig_map
		};
		if($@) {
			$sequence = undef;
		}
	}
		
	#my @contigs = $self->project_dump->contig_list;
	#if(scalar @contigs != 1) {
	#	warn "Cannot determine sequence for multiple contigs\n";
	#}
	#else {
#		$sequence = $self->project_dump->DNA($contigs[0]);
	#}
	
	return $sequence;
}

sub _build_embl_sequence {
	my ($self) = @_;
	
	if(defined($self->embl_entry)) {
		return $self->embl_entry->Sequence->seq;
	}
	else {
		warn "No EMBL entry for getting seq\n";
		return;
	}
}

sub is_sanger_sequence_identical_to_embl_sequence {
	my ($self) = @_;
	
	if(
		!defined($self->sanger_sequence)
		or !defined($self->embl_sequence)
		or length($self->sanger_sequence) == 0
		or length($self->embl_sequence) == 0
	) {
		warn "Cannot obtain sequences to compare for project " . $self->projectname . "\n";
		return 0;
	}
	else {
		return($self->sanger_sequence eq $self->embl_sequence);
	}
}

sub _build_submissions_seq_id {
	my ($self) = @_;
	
	my $seq_id = seq_id_from_project_name($self->projectname); 
	
	if(!defined($seq_id)) {
		carp "Cannot identify seq_id for " . $self->projectname . "\n";
	}
	return $seq_id
}

sub days_between_embl_date_and_submissions_date {
	my ($self) = @_;
	
	my $approximate_days;
	if($self->embl_date and $self->submissions_date) { 
		my $duration = $self->embl_date->subtract_datetime($self->submissions_date);
		my ($years, $months, $days) = $duration->in_units('years','months','days');
		$approximate_days = abs( 365 * $years + 30 * $months + $days );
	}
	else {
		carp "Cannot obtain dates for " . $self->projectname . "\n";
		$approximate_days = 'ERROR';
	}
	
	return $approximate_days;
}

sub _build_submissions_date {
	my ($self) = @_;

	my $date;
	
	if($self->submissions_seq_id) {
		$self->dbi->submission_date_for_project_sth->execute($self->submissions_seq_id);
		my $submissions_date_result_ref = $self->dbi->submission_date_for_project_sth->fetchrow_arrayref;
	
		if(defined($submissions_date_result_ref) and ref($submissions_date_result_ref) eq 'ARRAY' and scalar(@$submissions_date_result_ref) == 1) {
			my ($submissions_date_string) = @$submissions_date_result_ref;
			if($submissions_date_string =~ /^(\d{4})-(\d{2})-(\d{2}) /) {
				my $day = $3;
				my $month = $2;
				my $year = $1;
		
				$date = DateTime->new(
					year       => $year,
					month      => $month,
					day        => $day,
				);
			}
			 
		}
	}
	
	return $date;
}

sub _build_embl_date {
	my ($self) = @_;
	
	my $date;
	if(defined($self->embl_entry)) {
	    foreach my $reference ($self->embl_entry->Reference) {
	        foreach my $location ($reference->locations) {
	        	if($location =~ /Submitted \((.*?)\) to the INSDC/) {
	        		
	        		my $date_string = $1;
	        		
	        		if($date_string =~ /^(\d+)-(.{3})-(\d{4})/) {
	        			my $day = $1;
	        			my $month_string = $2;
	        			my $year = $3;
	        			
	        			my $month_number = $self->three_letter_month_to_number($month_string); 
	        			
	        			if(defined($month_number)) {

			        		$date = DateTime->new(
								year       => $year,
								month      => $month_number,
								day        => $day,
			        		);
	        				
	        			}
	        		}
	        	}
	        }
	    }
	    if(!defined($date)) {
	    	# $date = DateTime::Format::Epoch::Unix->parse_datetime( $self->embl_entry->DT->date );
	    }
    }
		
	return $date;
}

sub three_letter_month_to_number {
	my ($self, $month_string) = @_;
	
	my %month_number_for_string = (
		JAN => 1,
		FEB => 2,
		MAR => 3,
		APR => 4,
		MAY => 5,
		JUN => 6,
		JUL => 7,
		AUG => 8,
		SEP => 9,
		OCT => 10,
		NOV => 11,
		DEC => 12,
	);

	my $month_number;
	if(exists($month_number_for_string{$month_string})) {
		$month_number = $month_number_for_string{$month_string};
	}
		
	return $month_number;
}

sub _build_embl_entry {
	my ($self) = @_;
	
	my ($embl_entry) = get_EMBL_entries($self->accession);
	
	return $embl_entry;
}

sub _build_projectname {
	my ($self) = @_;
	return fetch_projectname_from_clonename($self->clonename);
}

sub _build_species {
	my ($self) = @_;
	return species_from_project_name($self->projectname);
}

sub is_sanger_accession {
    my ($self) = @_;
    
    my %valid_organisations = (
    	'Sanger Centre' => 1,
    	'UK HGMP-RC' => 1,
    );
    
    # Check the "sequenced by" entry in the Clone table
    unless(
        defined($self->organisation)
        and exists($valid_organisations{$self->organisation})
    ) {
        return 0;
    }

    if(!defined($self->embl_entry)) {
        return 0;
    }

    foreach my $reference ($self->embl_entry->Reference) {
        foreach my $location ($reference->locations) {
            if($location =~ /Sanger/i) {
                return 1;
            }
        }
    }
    
    return 0;
}

sub is_finished {
	my ($self) = @_;
	
	my %is_project_status_valid = (
    	'Analysed' => 1,
    	'Submitted to EMBL' => 1,
	);
	
	if(defined($self->projectname)) {
		my ($project_status, $project_status_date) = fetch_project_status($self->projectname);
		
		if(exists($is_project_status_valid{$project_status})) {
			return 1;
		}
	}
	
	return 0; 
}

sub _build_organisation {
		my ($self) = @_;

	$self->dbi->organisation_sth->execute($self->clonename);
	my $organisation_result_ref = $self->dbi->organisation_sth->fetchrow_arrayref;

	my $organisation;
	if(defined($organisation_result_ref) and ref($organisation_result_ref) eq 'ARRAY' and scalar(@$organisation_result_ref) == 1) {
		($organisation) = @$organisation_result_ref; 
	}

	return $organisation;
}

no Moose;
__PACKAGE__->meta->make_immutable;

__END__

=head1 AUTHOR

James Torrance <jt8@sanger.ac.uk>

