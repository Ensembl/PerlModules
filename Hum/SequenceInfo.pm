
### Hum::SequenceInfo

package Hum::SequenceInfo;

use strict;
use warnings;
use Carp;
use Hum::Submission 'prepare_statement';
use Hum::Tracking qw{
    track_db
    prepare_cached_track_statement
    };
use Hum::Pfetch 'get_EMBL_entries';
use Hum::NcbiFetch 'wwwfetch_EMBL_object_using_NCBI_fallback';
use Hum::FastaFileIO;
use Hum::Mole;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub fetch_by_db_id {
    my( $pkg, $db_id ) = @_;
    
    return $pkg->_fetch_generic(q{ id_sequence = ? }, $db_id);
}

sub fetch_by_accession_sv {
    my( $pkg, $acc, $sv ) = @_;
    
    return $pkg->_fetch_generic(q{ accession = ? AND sv = ? }, $acc, $sv);
}

sub fetch_latest_by_accession {
    my( $pkg, $acc ) = @_;
    
    return $pkg->_fetch_generic(q{ accession = ? ORDER BY sv DESC }, $acc);
}

sub fetch_latest_with_Sequence {
    my( $pkg, $acc ) = @_;
    
    confess "Missing accession argument" unless $acc;
    
    return $pkg->sanger_sequence_get($acc)
        || $pkg->embl_sequence_get($acc);
}

# This is only called if all details must be retrieved from web
# Because it loads the whole sequence from the web, this should be avoided
# if other info sources are available
sub embl_web_sequence_get {
	my ($pkg, $acc) = @_;

	my $embl = get_EMBL_entry_from_pfetch_or_web($acc);
    return unless $embl;

    # Attempt to get this from the Tracking database
    # This guards against situations where the clone is in Tracking but missing from Mole.
    my $self;
    unless($self = $pkg->fetch_by_accession_sv($acc, $embl->ID->version)) {
    	$self = $pkg->new;
        $self->accession($acc);
        $self->sequence_version($embl->ID->version);
    }

    my $htgs_phase = 3;
    foreach my $keyword ($embl->KW->list) {
    	if($keyword =~ /^HTGS_PHASE(\d)$/) {
    		$htgs_phase = $1;
    	}
    }
	$self->htgs_phase($htgs_phase);

	# We set the lazy-load method in case the sequence
	# gets dropped and needs to be reloaded
	$self->_lazy_load_method('_lazy_load_embl_sequence');
    $self->Sequence($embl->hum_sequence);
	
	return $self;
}

sub embl_sequence_get {
    my( $pkg, $acc ) = @_;
    
    my $mole_entry = Hum::Mole->new($acc);
    # If we can't get this accession from Mole, try EMBL
    if(!defined($mole_entry)) {
    	return $pkg->embl_web_sequence_get($acc);
    }

    my $sv = $mole_entry->sv;
    return unless $sv;
    
    my( $self );
    unless ($self = $pkg->fetch_by_accession_sv($acc, $sv)) {
        $self = $pkg->new;
        $self->accession($acc);
        $self->sequence_version($sv);
    }
      $self->htgs_phase($mole_entry->htgs_phase);
      return unless $self->htgs_phase;
      
    $self->_lazy_load_method('_lazy_load_embl_sequence');
    
    return $self;
}

{
    my( $sth );

    sub sanger_sequence_get {
        my( $pkg, $acc ) = @_;

        my $sth ||= prepare_statement(q{
            SELECT s.sequence_name
              , s.sequence_version
              , s.embl_checksum
              , s.file_path
              , d.htgs_phase
              , a.project_name
            FROM project_acc a
              , project_dump d
              , sequence s
            WHERE a.sanger_id = d.sanger_id
              AND d.seq_id = s.seq_id
              AND d.is_current = 'Y'
              AND a.accession = ?
            });
        $sth->execute($acc);

        my( @seq_inf );
        while (my ($name, $sv, $cksum, $path, $htgs_phase, $proj) = $sth->fetchrow) {
            unless ($sv) {
                warn "sv not set for '$acc' ($name)\n";
                return;
            }

            my( $self );
            unless ($self = $pkg->fetch_by_accession_sv($acc, $sv)) {
                $self = $pkg->new;
                $self->accession($acc);
                $self->sequence_version($sv);
                $self->projectname($proj);
                
            }
            $self->htgs_phase($htgs_phase);
            $self->_lazy_load_method('_lazy_load_sanger_sequence');
            $self->sanger_sequence_file("$path/$name");

            push(@seq_inf, $self);
        }

        if (@seq_inf == 1) {
            return $seq_inf[0];
        }
        elsif (@seq_inf) {
            confess "got ", scalar(@seq_inf), " sequences for accession '$acc'\n";
        }
        else {
            return;
        }
    }
}

sub get_EMBL_entry_from_pfetch_or_web {
	my ($accession_sv) = @_;
	
	my ($entry) = get_EMBL_entries($accession_sv);
    unless ($entry) {
        $entry = wwwfetch_EMBL_object_using_NCBI_fallback($accession_sv);
    }
	
	return $entry;
}

sub get_EMBL_entry {
    my ($self) = @_;
    
    my( $entry );
    if (my $path = $self->embl_file_path || $self->fetch_embl_file_path) {
        my $embl = Hum::EMBL->new;
        $entry = $embl->parse($path);
    }
    unless ($entry) {
        my $acc = $self->accession        or confess        "accession not set";
        my $sv  = $self->sequence_version or confess "sequence_version not set";
        $entry = get_EMBL_entry_from_pfetch_or_web("$acc.$sv");
    }
    return $entry;
}

sub _fetch_generic {
    my( $pkg, $where_clause, @data ) = @_;
    
    my $sth = track_db()->prepare_cached(qq{
        SELECT id_sequence
          , accession
          , sv
          , id_htgsphase
          , length
          , embl_checksum
          , projectname
        FROM sequence
        WHERE $where_clause
        });
    $sth->execute(@data);
    my ($db_id, $acc, $sv, $htgs_phase, $length, $cksum, $proj) = $sth->fetchrow;
    $sth->finish;
    
    return unless $db_id;
    
    my $self = $pkg->new;
    $self->db_id($db_id);
    $self->accession($acc);
    $self->sequence_version($sv);
    $self->htgs_phase($htgs_phase);
    $self->sequence_length($length);
    $self->embl_checksum($cksum);
    $self->projectname($proj);
    
    return $self;
}

sub db_id {
    my( $self, $db_id ) = @_;
    
    if ($db_id) {
        $self->{'_db_id'} = $db_id;
    }
    return $self->{'_db_id'};
}

sub accession {
    my( $self, $accession ) = @_;
    
    if ($accession) {
        $self->{'_accession'} = $accession;
    }
    return $self->{'_accession'};
}

sub sequence_version {
    my( $self, $sequence_version ) = @_;
    
    if ($sequence_version) {
        $self->{'_sequence_version'} = $sequence_version;
    }
    if(defined($self->{'_sequence_version'})) {
        return $self->{'_sequence_version'};
    }
    else {
        return;
    }
}

sub accession_sv {
    my ($self) = @_;
    
    return join('.', $self->accession, $self->sequence_version);
}

sub sanger_sequence_file {
    my( $self, $sanger_sequence_file ) = @_;
    
    if ($sanger_sequence_file) {
        $self->{'_sanger_sequence_file'} = $sanger_sequence_file;
    }
    return $self->{'_sanger_sequence_file'};
}

sub htgs_phase {
    my( $self, $htgs_phase ) = @_;
    
    if ($htgs_phase) {
        $self->{'_htgs_phase'} = $htgs_phase;
    }
    return $self->{'_htgs_phase'};
}

sub sequence_length {
    my( $self, $sequence_length ) = @_;
    
    if ($sequence_length) {
        $self->{'_sequence_length'} = $sequence_length;
    }
    elsif (
        !defined($self->{'_sequence_length'})
    ) {
        $self->_lazy_load_sequence;
    }
    
    return $self->{'_sequence_length'};
}

sub embl_checksum {
    my( $self, $embl_checksum ) = @_;
    
    if ($embl_checksum) {
        $self->{'_embl_checksum'} = $embl_checksum;
    }
    elsif (
        !defined($self->{'_embl_checksum'})
    ) {
        $self->_lazy_load_sequence;
    }
    
    return $self->{'_embl_checksum'};
}

sub projectname {
    my( $self, $projectname ) = @_;
    
    if ($projectname) {
        $self->{'_projectname'} = $projectname;
    }
    return $self->{'_projectname'};
}

sub embl_file_path {
    my( $self, $embl_file_path ) = @_;
    
    if ($embl_file_path) {
        $self->{'_embl_file_path'} = $embl_file_path;
    }
    return $self->{'_embl_file_path'};
}

sub fetch_embl_file_path {
    my ($self) = @_;
    
    return if $self->{'_no_embl_file_path_stored'};
    
    my $acc = $self->accession          or confess "accession not set";
    my $sv  = $self->sequence_version   or confess "sequence_version not set";
    
    my $sth ||= prepare_statement(q{
        SELECT s.sequence_name
          , s.file_path
        FROM project_acc a
          , project_dump d
          , sequence s
        WHERE a.sanger_id = d.sanger_id
          AND d.seq_id = s.seq_id
          AND d.is_current = 'Y'
          AND a.accession = ?
          AND s.sequence_version = ?
        });
    $sth->execute($acc, $sv);
    
    my ($name, $path) = $sth->fetchrow;
    
    if ($name and $path) {
        return $self->embl_file_path("$path/$name.embl");
    } else {
        $self->{'_no_embl_file_path_stored'} = 1;
        return;
    }
}

sub _lazy_load_sanger_sequence {

    my ($self) = @_;

    my( $seq );
    if ($self->htgs_phase == 3) {
        # Finished sequences may not have an EMBL file
        my $fasta = Hum::FastaFileIO->new_DNA_IO( $self->sanger_sequence_file );
        $seq = $fasta->read_one_sequence;
    } else {
        # Unfinished sequences may be in multiple pieces
        # so we need the sequence from the EMBL file where
        # it is in one piece.
        $self->embl_file_path( $self->sanger_sequence_file . ".embl" );
        my $entry = $self->get_EMBL_entry;
        $seq = $entry->hum_sequence;
    }
    $seq->name($self->accession . '.' . $self->sequence_version);
    
    $self->Sequence($seq);
    
    return;
}

sub _lazy_load_embl_sequence {

    my ($self) = @_;

	# We only want to call this if the SV is specified
    if(!defined($self->sequence_version)) {
        confess "sequence_version not set";
    }

    my $embl = get_EMBL_entry_from_pfetch_or_web($self->accession_sv);
    return unless $embl;

    $self->Sequence($embl->hum_sequence);
    
    return;
}

sub _lazy_load_method {
    my ($self, $method) = @_;
    
    if ($method) {
        $self->{'_lazy_load_method'} = $method;
    }
    return $self->{'_lazy_load_method'};
    
}

sub _lazy_load_sequence {
    my ($self) = @_;
    
    if( $self->can($self->_lazy_load_method) ) {
        my $method = $self->_lazy_load_method;
        $self->$method;
    }
    else {
        confess("Lazy load method " . $self->_lazy_load_method . " wrongly specified\n");
    } 
    
    return;
}

sub Sequence {
    my( $self, $seq ) = @_;
    
    if ($seq) {
        $self->{'_Sequence'} = $seq;
        $self->sequence_length($seq->sequence_length);
        $self->embl_checksum($seq->embl_checksum);
    }
    # If sequence has been requested and does not exist
    # then lazy-load sanger sequence
    elsif (
        !defined($self->{'Sequence'})
    ) {
        # Only attempt lazy-load if the lazy load method is defined.
        if(defined($self->{'_lazy_load_method'})) {
            $self->_lazy_load_sequence;
        }
        else {
            return;
        }
    }
    
    return $self->{'_Sequence'};
}

sub drop_Sequence {
    my( $self ) = @_;
    
    $self->{'_Sequence'} = undef;
}

sub store {
    my( $self ) = @_;
    
    confess "object already has a db_id" if $self->db_id;
    
    # Get next value from sequence
    $self->get_next_id;
        
    # Could check if already stored, or use a REPLACE?
    my $sth = track_db->prepare_cached(q{
        INSERT INTO sequence(
            id_sequence
          , accession
          , sv
          , id_htgsphase
          , length
          , embl_checksum
          , projectname )
        VALUES(?,?,?,?,?,?,?)
        });
    
    $sth->execute(
        $self->db_id,
        $self->accession,
        $self->sequence_version,
        $self->htgs_phase,
        $self->sequence_length,
        $self->embl_checksum,
        $self->projectname,
        );
}

sub update_htgs_phase {
    my( $self ) = @_;
    
    my $db_id = $self->db_id      or confess "object does not have a db_id";
    my $phase = $self->htgs_phase or confess "htgs_phase not set";
    my $sth = track_db->prepare_cached(q{
        UPDATE sequence SET id_htgsphase = ? WHERE id_sequence = ?
        });
    $sth->execute($phase, $db_id);
}

sub get_next_id {
    my( $self ) = @_;
    
    my $sth = prepare_cached_track_statement(q{
        SELECT sequ_seq.nextval FROM dual
        });
    $sth->execute;
    my ($id) = $sth->fetchrow;
    $sth->finish;
    $self->db_id($id);
}

1;

__END__

=head1 NAME - Hum::SequenceInfo

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

