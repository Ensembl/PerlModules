package Hum::ChromosomeAudit::DBI;
use strict;
use warnings;
use Moose;
use Carp;
use DBI;
use DateTime;
use Hum::CloneProject qw{fetch_projectname_from_clonename fetch_project_status};
use Hum::Tracking qw{verbatim_chromosome_from_project prepare_track_statement};
use Hum::Submission qw{chromosome_from_project_name species_from_project_name prepare_statement};

=head2 Hum::ChromosomeAudit::DBI module

	Handles database interactions for ChromosomeAudit

=cut

has 'audit_dbi' => (
    is  => 'ro',
    isa => 'DBI::db',
    lazy_build => 1,
);

has 'recording_sth' => (
    is  => 'ro',
    isa => 'DBI::st',
    lazy_build => 1,
);

has 'organisation_sth' => (
    is  => 'ro',
    isa => 'DBI::st',
    lazy_build => 1,
);

has 'update_clone_chromosome_sth' => (
    is  => 'ro',
    isa => 'DBI::st',
    lazy_build => 1,
);

has 'update_sequence_chromosome_sth' => (
    is  => 'ro',
    isa => 'DBI::st',
    lazy_build => 1,
);

has 'update_sequence_file_path_sth' => (
    is  => 'ro',
    isa => 'DBI::st',
    lazy_build => 1,
);

has 'submission_date_for_project_sth' => (
    is  => 'ro',
    isa => 'DBI::st',
    lazy_build => 1,
);

has 'acception_date_for_project_sth' => (
    is  => 'ro',
    isa => 'DBI::st',
    lazy_build => 1,
);

sub _build_audit_dbi {
	my ($self) = @_;
	
	my $db_name = 'jt8_chromosome_audit';
	my $db_host = 'gritdb';
	my $db_user = 'gritadmin';
	my $db_pass = 'gritty';
	
	my $dsn = "DBI:mysql:database=$db_name;host=$db_host";
	my $dbi = DBI->connect($dsn, $db_user, $db_pass) || die "Cannot connect to $db_name\n";
	
	return $dbi;
}

sub _build_recording_sth {
	my ($self) = @_;

	my $recording_sql = "INSERT INTO chromosome_correction (from_chromosome, to_chromosome, species, clonename, database_name, date) VALUES (?,?,?,?,?,NOW());";
	my $recording_sth = $self->audit_dbi->prepare($recording_sql);
	
	return $recording_sth;	
}

sub _build_organisation_sth {
	my ($self) = @_;

	my $organisation_sql = q{
		SELECT 
			O.orgtitle
		FROM
			clone C,
			organisation O
		WHERE
			C.sequenced_by = O.id_org
			AND C.clonename = ?
	};
	return prepare_track_statement($organisation_sql);
}

sub _build_update_clone_chromosome_sth {
	my ($self) = @_;

	my $update_clone_chromosome_sql = "
		UPDATE CLONE
		SET CHROMOSOME=(
			SELECT ID_DICT
			FROM CHROMOSOMEDICT
			WHERE SPECIESNAME=?
			AND CHROMOSOME=?
		)
		WHERE CLONENAME=?";

	return prepare_track_statement($update_clone_chromosome_sql);	
}

sub _build_update_sequence_chromosome_sth {
	my ($self) = @_;

	my $update_sequence_chromosome_sql = "
    	UPDATE sequence S,
    		project_dump PD,
    		project_acc PA,
    		species_chromosome SC
    	SET S.chromosome_id=SC.chromosome_id
    	WHERE
    		S.seq_id=PD.seq_id
    		AND PD.is_current='Y'
    		AND PD.sanger_id=PA.sanger_id
    		AND SC.species_name=?
    		AND SC.chr_name =?
    		AND PA.project_name = ?";

	return prepare_statement($update_sequence_chromosome_sql);

}

sub _build_update_sequence_file_path_sth {
	my ($self) = @_;

	my $update_sequence_file_path_sql = "
		UPDATE sequence S,
		project_dump PD,
    	project_acc PA
		SET S.file_path=?
		WHERE
			S.seq_id=PD.seq_id
			AND PD.is_current='Y'
			AND PD.sanger_id=PA.sanger_id
			AND PA.project_name = ?";
	
	return prepare_statement($update_sequence_file_path_sql);	
}

sub _build_submission_date_for_project_sth {
	my ($self) = @_;
	
	my $submission_date_for_project_sql = "
		SELECT max(submission_time)
		FROM submission
		WHERE seq_id=?
	";

	return prepare_statement($submission_date_for_project_sql);	
}

sub _build_acception_date_for_project_sth {
	my ($self) = @_;
	
	my $acception_date_for_project_sql = "
		SELECT accept_date
		FROM acception
		WHERE seq_id=?
	";

	return prepare_statement($acception_date_for_project_sql);	
}

no Moose;
__PACKAGE__->meta->make_immutable;

__END__

=head1 AUTHOR

James Torrance <jt8@sanger.ac.uk>

