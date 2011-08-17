
### Hum::Mole

package Hum::Mole;

use strict;
use warnings;
use Carp;
use DateTime;
use DBI;

my $CLASS_emblrelease_db;
my $CLASS_emblnew_db;

sub new {
	my ($caller, $accession) = @_;

	my $class = ref($caller) || $caller;
	my $self = bless {}, $class;
	$self->accession($accession);

	# Create class DB connections if they do not pre-exist
	if(!defined($CLASS_emblrelease_db) or !defined($CLASS_emblnew_db)) {
		$self->_get_embl_databases;
	}

   	my $entry_from_accession_sql = "SELECT entry_id FROM accession WHERE accession='" . $self->accession . "'";

	my @entries = @{$CLASS_emblnew_db->selectcol_arrayref($entry_from_accession_sql)};
	if(scalar @entries > 0) {
		$self->db($CLASS_emblnew_db);
	}
	else {
		@entries = @{$CLASS_emblrelease_db->selectcol_arrayref($entry_from_accession_sql)};
		$self->db($CLASS_emblrelease_db);
	}

	if(scalar @entries == 1) {
		$self->entry($entries[0]);
		return $self;
	}
	else {
		return;
	}
}

sub _get_embl_databases {
	my $mole_user = 'genero';
	my $mole_host = 'cbi5d';
	my $mole_login_db = 'mysql';
		
	my $mole_dsn = "DBI:mysql:database=${mole_login_db};host=${mole_host}";
	my $mole_db = DBI->connect($mole_dsn, $mole_user);
		
	my @databases = @{$mole_db->selectcol_arrayref("show databases")};

	# Find latest EMBL
	my $latest_embl;
	my $highest_embl_number = 0;
	foreach my $database (@databases) {
		if($database =~ /^embl_(\d+)$/) {
			my $embl_number = $1;
			if($embl_number > $highest_embl_number) {
				$highest_embl_number = $embl_number;
				$latest_embl = $database;
			}
		}
	}
		
	# Find latest EMBLNEW
	my $latest_emblnew;
	my $latest_emblnew_date;
	foreach my $database (@databases) {
		if($database =~ /^emnew_(\d{4})(\d{2})(\d{2})$/) {
			my $emblnew_date = DateTime->new(
				year => $1,
				month => $2,
				day => $3,
			);
				
			if(
				!defined($latest_emblnew_date)
				or $emblnew_date > $latest_emblnew_date
			) {
				$latest_emblnew_date = $emblnew_date;
				$latest_emblnew = $database;
			}
		}
	}
				
	# Connect to these databases
	my $embl_dsn = "DBI:mysql:database=${latest_embl};host=${mole_host}";
	$CLASS_emblrelease_db = DBI->connect($embl_dsn, $mole_user);

	my $emblnew_dsn = "DBI:mysql:database=${latest_emblnew};host=${mole_host}";
	$CLASS_emblnew_db = DBI->connect($emblnew_dsn, $mole_user);
		
	return;						
}

sub accession {
    my( $self, $accession ) = @_;
    
    if ($accession) {
        $self->{'_accession'} = $accession;
    }
    return $self->{'_accession'};
}

sub db {
    my( $self, $db ) = @_;
    
    if ($db) {
        $self->{'_db'} = $db;
    }
    return $self->{'_db'};
}

sub entry {
    my( $self, $entry ) = @_;
    
    if ($entry) {
        $self->{'_entry'} = $entry;
    }
    return $self->{'_entry'};
}

sub sv {
	my ($self) = @_;
	my $get_accession_version_sql = "SELECT accession_version FROM entry WHERE entry_id=" . $self->entry;
	my @accession_versions = @{$self->db->selectcol_arrayref($get_accession_version_sql)};	

	my ($acc, $sv);
	if(scalar @accession_versions == 1) {
		($acc, $sv) = $accession_versions[0] =~ /^(.+)\.(\d+)$/;
	}
	return $sv;
}

sub htgs_phase {
	my ($self) = @_;
	
	my( $htgs_phase );
	
	my $keyword_sql = "SELECT keyword FROM keyword WHERE entry_id=" . $self->entry;
	my @keywords = @{$self->db->selectcol_arrayref($keyword_sql)};
	foreach my $keyword ( @keywords ) {
		if ($keyword =~ /HTGS_PHASE(\d)/) {
            $htgs_phase = $1;
            last;
        }
	}

    unless ($htgs_phase) {
    	my $data_class_sql = "SELECT data_class FROM entry WHERE entry_id=" . $self->entry;
		my @data_classes = @{$self->db->selectcol_arrayref($data_class_sql)};
    	
        if (scalar @data_classes == 1 and $data_classes[0] eq 'HTG') {
            $htgs_phase = 1;
        } else {
            $htgs_phase = 3;
        }
    }
	
	return $htgs_phase;
}

1;

__END__

=head1 NAME - Hum::Mole

=head1 AUTHOR

James Torrance B<email> jt8@sanger.ac.uk
