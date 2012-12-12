package Hum::ChromosomeAudit;
use strict;
use warnings;
use Moose;
use Carp;
use DBI;
use Hum::ChromosomeAudit::DBI;
use Hum::CloneProject qw{fetch_projectname_from_clonename fetch_project_status};
use Hum::Tracking qw{verbatim_chromosome_from_project prepare_track_statement};
use Hum::Submission qw{chromosome_from_project_name species_from_project_name prepare_statement};
use Hum::Pfetch qw{get_EMBL_entries};
use Hum::ProjectDump;
use Hum::CloneAudit;

=head2 Hum::ChromosomeAudit module

	Audits the chromosome assignments for a given project.

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

has 'tpf_chromosome' => (
	is  => 'ro',
	isa => 'Str',
	required => 1,
);

has 'oracle_chromosome' => (
	is  => 'rw',
	isa => 'Maybe[Str]',
);

has 'submissions_chromosome' => (
	is  => 'rw',
	isa => 'Maybe[Str]',
);

has 'path_in_submissions_chromosome' => (
	is  => 'rw',
	isa => 'Maybe[Str]',
);

has 'fasta_file' => (
	is  => 'rw',
	isa => 'Maybe[Str]',
);

has 'file_path' => (
	is  => 'rw',
	isa => 'Maybe[Str]',
);

has 'is_path_in_submissions_correct' => (
    is  => 'rw',
    isa => 'Bool',
    default => 0,
);

has 'has_audit_failed' => (
    is  => 'rw',
    isa => 'Bool',
    default => 0,
);

has 'projectname' => (
	is  => 'ro',
	isa => 'Str',
	lazy_build => 1,
);

has 'species' => (
	is  => 'ro',
	isa => 'Str',
	lazy_build => 1,
);

has 'dbi' => (
    is  => 'ro',
    isa => 'Hum::ChromosomeAudit::DBI',
    required => 1,
);

has 'clone_audit' => (
	is => 'ro',
	isa => 'Hum::CloneAudit',
	lazy_build => 1,
);

has 'verbose' => (
    is  => 'ro',
    isa => 'Bool',
    default => 0,
);

has 'should_record' => (
    is  => 'ro',
    isa => 'Bool',
    default => 1,
);

has 'should_rectify' => (
    is  => 'ro',
    isa => 'Bool',
    default => 1,
);

sub _build_clone_audit {
	my ($self) = @_;
	
	my $clone_audit = Hum::CloneAudit->new(
		accession => $self->accession,
		clonename => $self->clonename,
		projectname => $self->projectname,
		verbose => $self->verbose,
		dbi => $self->dbi,
	);
	
	return $clone_audit;
}

sub _build_projectname {
	my ($self) = @_;
	return fetch_projectname_from_clonename($self->clonename);
}

sub _build_species {
	my ($self) = @_;
	return species_from_project_name($self->projectname);
}

sub print_error {
	my ($self, $error) = @_;
	print $self->accession . ': ' . $error . "\n"; 
}

sub report_fatal_error {
	my ($self, $error) = @_;
	$self->has_audit_failed(1);
	print "FAILED TO AUDIT " . $self->clonename . ': ' . $error . "\n"; 
}

sub tpf_chromosome_in_submissions_format {
	my ($self) = @_;
	
	my $tpf_chromosome = $self->tpf_chromosome;
	if($tpf_chromosome eq 'U') {$tpf_chromosome = 'UNKNOWN';}
	
	return $tpf_chromosome;	
}

sub audit {
	my ($self) = @_;

	print "Acc " . $self->accession . "\n" if($self->verbose);

	# Only audit Sanger clones
	if(!$self->clone_audit->is_sanger_accession) {
		$self->print_error("Not Sanger clone") if($self->verbose);
	}
	elsif(!$self->clone_audit->is_finished) {
		$self->print_error("Not finished") if($self->verbose);
	}
	else {
    	# Audit oracle DB
    	$self->audit_oracle;
    	
    	# Audit submissions-DB (both chrom identifier and file-location)
    	$self->audit_submissions;
    
    	if(!$self->has_audit_failed) {	
    		$self->rectify_differences;
    	}
	}

	return;
}

sub record_update {
	my ($self, $database) = @_;

	if($self->should_record) {
	
		my %database_to_function = (
			'oracle' => 'oracle_chromosome',
			'submissions' => 'submissions_chromosome',
			'path_in_submissions' => 'path_in_submissions_chromosome',
		); 
	
		if(!exists($database_to_function{$database})) {
			$self->has_audit_failed(1);
			return;
		}
	
		$self->dbi->recording_sth->execute(
			$self->{$database_to_function{$database}},
			$self->tpf_chromosome,
			$self->species,
			$self->clonename,
			$database,
		);
	}

	return;	
}

sub rectify_differences {
	my ($self) = @_;
	
	my %transitions_to_ignore = (
		'X' => {'Y' => 1},
	);
	
	if(
		$self->oracle_chromosome ne $self->tpf_chromosome
		and !exists($transitions_to_ignore{$self->oracle_chromosome}{$self->tpf_chromosome})
	) {
		$self->print_error("Oracle chr " . $self->oracle_chromosome . " does not match TPF chromosome " . $self->tpf_chromosome);

		if($self->should_rectify) {

			my $rows_updated = $self->dbi->update_clone_chromosome_sth->execute(
				$self->species,
				$self->tpf_chromosome,
				$self->clonename,
			);
			if($rows_updated != 1) {
				warn "$rows_updated rows updated when changing Oracle chromosome from " . $self->oracle_chromosome . " to " . $self->tpf_chromosome . " for clone " . $self->clonename . "\n";
			}

		}
		$self->record_update('oracle');
	}
	if(
		$self->submissions_chromosome ne $self->tpf_chromosome_in_submissions_format
		and !exists($transitions_to_ignore{$self->submissions_chromosome}{$self->tpf_chromosome_in_submissions_format})
	) {
		$self->print_error("Submission chr " . $self->submissions_chromosome . " does not match TPF chromosome " . $self->tpf_chromosome_in_submissions_format);

		if($self->should_rectify) {

			my $rows_updated = $self->dbi->update_sequence_chromosome_sth->execute(
				$self->species,
				$self->tpf_chromosome_in_submissions_format,
				$self->projectname,
			);
			if($rows_updated != 1) {
				warn "$rows_updated rows updated when changing submissions chromosome from " . $self->oracle_chromosome . " to " . $self->tpf_chromosome_in_submissions_format . " for clone " . $self->clonename . "\n";
			}
		}
		$self->record_update('submissions'); 
	}
   	if(
   		$self->path_in_submissions_chromosome ne $self->tpf_chromosome_in_submissions_format
   		and !exists($transitions_to_ignore{$self->path_in_submissions_chromosome}{$self->tpf_chromosome_in_submissions_format})
   	) {
   		$self->print_error("embl_seq-in-database chr " . $self->path_in_submissions_chromosome . " does not match TPF chromosome " . $self->tpf_chromosome_in_submissions_format);

		if($self->should_rectify) {
			my $new_file_path = $self->file_path;
			my $tpfchromosome = $self->tpf_chromosome_in_submissions_format;
			$new_file_path =~ s/Chr_[^\/]+/Chr_$tpfchromosome/;

			my $rows_updated = $self->dbi->update_sequence_file_path_sth->execute(
				$new_file_path,
				$self->projectname,
			);
			if($rows_updated != 1) {
				warn "$rows_updated rows updated when changing submissions file path from " . $self->path_in_submissions_chromosome . " to " . $self->tpf_chromosome_in_submissions_format . " for clone " . $self->clonename . "\n";
			}

			my $old_file_name = $self->file_path . '/' . $self->fasta_file;
			my $new_file_name = $new_file_path . '/' . $self->fasta_file;			
			my $move_command = "mv $old_file_name $new_file_name";
			my $move_embl_command = "mv $old_file_name.embl $new_file_name.embl";
			system($move_command);
			system($move_embl_command);
		}
		$self->record_update('path_in_submissions');
   	}

	return;
}


sub audit_oracle {
	my ($self) = @_;

	$self->oracle_chromosome(verbatim_chromosome_from_project($self->projectname));
	
	return;
}

sub audit_submissions {
	my ($self) = @_;
	
	# Make use of (and/or extend) the Hum::Submissions module
	$self->submissions_chromosome(chromosome_from_project_name($self->projectname));

	my $project_dump;
	eval {
		$project_dump = Hum::ProjectDump->new_from_accession($self->accession);
	};
	
	if(defined($project_dump)) {
    	#my ($path_in_submissions_chromosome) = $project_dump->file_path =~ /\/Chr_([^\/]+)(\/unfinished_sequence)?\/?$/;
    	if($project_dump->file_path =~ /\/Chr_([^\/]+)\/?$/) {
    		$self->path_in_submissions_chromosome($1);
    	}
    	else {
    		$self->report_fatal_error("Cannot parse file path " . $project_dump->file_path);
    		return;
    	}
    		
    	if(! -e $project_dump->fasta_file_path) {
    		$self->report_fatal_error("Cannot locate FASTA file on the NFS");
    	}
    	$self->fasta_file($project_dump->sequence_name);
    	$self->file_path($project_dump->file_path);
	}
	else {
		$self->report_fatal_error("Cannot obtain project dump");
	}
	
	return;
}

no Moose;
__PACKAGE__->meta->make_immutable;

__END__

=head1 AUTHOR

James Torrance <jt8@sanger.ac.uk>

