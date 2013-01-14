
### Hum::Mole

package Hum::Mole;

use strict;
use warnings;
use Carp;
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
    my $mole_login_db = 'mm_ini';
        
    my $mole_dsn = "DBI:mysql:database=${mole_login_db};host=${mole_host}";
    my $mole_db = DBI->connect($mole_dsn, $mole_user);
    
    my %database_handle_for_category = (
        emblrelease => \$CLASS_emblrelease_db,
        emblnew => \$CLASS_emblnew_db,
    );
        
    foreach my $database_category (keys %database_handle_for_category) {

        # If there are multiple names, use the highest alphabetically
        # This should equate to the most recent        
        my @database_names = sort @{$mole_db->selectcol_arrayref(qq/select database_name from ini where database_category='$database_category' and current='yes' and available='yes'/)};
        
        if(scalar @database_names > 0) {
            my $current_name = $database_names[-1];
            my $dsn = "DBI:mysql:database=${current_name};host=${mole_host}";
            ${$database_handle_for_category{$database_category}} = DBI->connect($dsn, $mole_user);
            
        }
    }
        
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

