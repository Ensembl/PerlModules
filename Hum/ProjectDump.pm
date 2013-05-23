
package Hum::ProjectDump;

use strict;
use warnings;
use Carp;
use Hum::Submission qw(
    acc_data
    prepare_statement
    sub_db
    );
use Hum::Tracking qw(
    track_db
    prepare_track_statement
    is_full_shotgun_complete
    is_assigned_to_finisher
    is_shotgun_complete
    current_project_status_number
    has_limited_order_remark
    );
use Hum::EBI_FTP;
use Hum::Conf qw( FTP_ROOT FTP_GHOST);
use Hum::Species;
use Hum::GapTags::Submissions;
use Symbol 'gensym';
use File::Path;

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}

sub get_all_dumps_for_project {
    my( $pkg, $project ) = @_;
    
    my @dumps = $pkg->get_all_existing_dumps_for_project($project);
    
    if (@dumps) {
        return @dumps;
    } else {
        my $pdmp = $pkg->create_new_dump_object($project);
        return($pdmp);
    }
}

sub get_all_existing_dumps_for_project {
    my( $pkg, $project ) = @_;

    my $get_sids = prepare_statement(qq{
        SELECT a.sanger_id
        FROM project_acc a
          , project_dump d
        WHERE a.sanger_id = d.sanger_id
          AND d.is_current = 'Y'
          AND a.project_name = '$project'
        });
    $get_sids->execute;

    my(@dumps);
    while (my($sid) = $get_sids->fetchrow) {
        my $pdmp = $pkg->new_from_sanger_id($sid);
        push(@dumps, $pdmp);
    }

    return @dumps;
}

sub create_new_dump_object {
    my( $pkg, $project, $force_flag ) = @_;

    my $active_count = prepare_statement(qq{
        SELECT count(*)
        FROM project_check
        WHERE is_active = 'Y'
          AND project_name = '$project'
        });
    $active_count->execute;
    my ($is_active) = $active_count->fetchrow;
    if ($force_flag or $is_active) {
        my $pdmp = $pkg->new;
        $pdmp->project_name($project);
        $pdmp->sanger_id("_\U$project");
        return $pdmp;
    } else {
        confess "Project '$project' is not active";
    }
}

sub new_from_sequence_name {
    my( $pkg, $name ) = @_;
    
    my $sth = prepare_statement(qq{
        SELECT d.sanger_id
        FROM project_dump d
          , sequence s
        WHERE d.seq_id = s.seq_id
          AND d.is_current = 'Y'
          AND s.sequence_name = '$name'
        });
    $sth->execute;
    
    my( @sid );
    while (my ($s) = $sth->fetchrow) {
        push(@sid, $s);
    }
    
    if (@sid == 1) {
        return $pkg->new_from_sanger_id($sid[0]);
    } else {
        confess "Looking for the sanger_id corresponding to sequence '$name' I got (",
            join(', ', map "'$_'", @sid), ')';
    }
}

sub new_from_accession {
    my( $pkg, $acc ) = @_;

    my $sth = prepare_statement(qq{
       SELECT d.sanger_id
       FROM project_acc a
         , project_dump d
       WHERE a.accession = '$acc'
       AND a.sanger_id = d.sanger_id
       AND d.is_current = 'Y'
       });

    $sth->execute;

    my( @sid );
    while (my ($s) = $sth->fetchrow) {
        push(@sid, $s);
    }

    if (@sid == 1) {
        return $pkg->new_from_sanger_id($sid[0]);
    } else {
        confess "Looking for the sanger_id corresponding to sequence '$acc' I got (",
            join(', ', map "'$_'", @sid), ')';
    }

}

sub new_from_sanger_id {
    my( $pkg, $sanger_id ) = @_;
    
    my $pdmp = $pkg->new;
    $pdmp->sanger_id($sanger_id);
    $pdmp->read_submission_data;
    $pdmp->read_accession_data;
    
    return $pdmp;
}

# Generate simple data access functions using closures
BEGIN {
        
    # List of fields we want scalar access fuctions to
    my @scalar_fields = qw(
        accession
        dump_time
        embl_name
        project_name
        project_suffix
        sanger_id
        seq_id
        sequence_version
        sequenced_by
        funded_by
    );
    
    # Make scalar field access functions
    foreach my $func (@scalar_fields) {
        no strict 'refs';
        
        # Don't overwrite existing functions
        die "'$func()' already defined" if defined (&$func);
        
        my $field = "_$func";
        *$func = sub {
            my( $pdmp, $arg ) = @_;
            
            if ($arg) {
                $pdmp->{$field} = $arg;
            }
            return $pdmp->{$field};
        }
    }
}

sub assembly_tag_parser {
	my ($pdmp) = @_;
	
	if(!exists($pdmp->{'_assembly_tag_parser'})) {
	
	    $pdmp->{'_assembly_tag_parser'} = Hum::GapTags::Submissions->new({
	        project => $pdmp->project_name,
	        dbi => sub_db, 
	        known_sanger => 1,
	    });
		
	}
	
	return $pdmp->{'_assembly_tag_parser'};
}

sub assembly_tags {
    my ($pdmp, @assembly_tags) = @_;

	if(@assembly_tags) {
		@{$pdmp->{'_assembly_tags'}} = @assembly_tags;
	}

	if(!exists($pdmp->{'_assembly_tags'})) {
	
	    @{$pdmp->{'_assembly_tags'}} = $pdmp->assembly_tag_parser->get_assembly_tags;
	    if($pdmp->assembly_tag_parser->result ne 'Ok') {
	        @{$pdmp->{'_assembly_tags'}} = ();
	    }
	}

	return @{$pdmp->{'_assembly_tags'}};
}

sub submission_time {
    my $pdmp = shift;

    return $pdmp->_submission_data('submission_time', @_);
}

sub submission_type {
    my $pdmp = shift;

    return $pdmp->_submission_data('submission_type', @_);
}

sub embl_file_md5_sum {
    my $pdmp = shift;

    return $pdmp->_submission_data('embl_file_md5_sum', @_);
}

sub region_start {
    my $pdmp = shift;

    return $pdmp->_submission_data('region_start', @_);
}

sub region_end {
    my $pdmp = shift;

    return $pdmp->_submission_data('region_end', @_);
}

sub is_htgs_draft {
    my( $pdmp ) = @_;

    my $project = $pdmp->project_name;
    return is_shotgun_complete($project);
}

sub is_htgs_limited_order {
    my( $pdmp ) = @_;

    my $project = $pdmp->project_name;
    return has_limited_order_remark($project);
}

sub is_htgs_fulltop {
    my( $pdmp ) = @_;

    my $project = $pdmp->project_name;
    return is_full_shotgun_complete($project);
}

sub is_htgs_activefin {
    my( $pdmp ) = @_;

    my $project = $pdmp->project_name;
    return is_assigned_to_finisher($project);
}

sub is_cancelled {
    my( $pdmp ) = @_;

    return ($pdmp->current_status_number == 24) ? 1 : 0;
}

sub is_private {
    my( $pdmp ) = @_;

    return Hum::Tracking::is_private($pdmp->project_name);
}

sub project_type {
    my ($self) = @_;

    my $type;
    unless ($type = $self->{'_project_type'}) {
        $type = $self->{'_project_type'} = Hum::Tracking::project_type($self->project_name);
    }
    return $type;
}

sub current_status_number {
    my( $pdmp ) = @_;

    unless (defined $pdmp->{'_current_status_number'}) {
        my $project = $pdmp->project_name;
        $pdmp->{'_current_status_number'}
            = current_project_status_number($project) || 0;
    }
    return $pdmp->{'_current_status_number'};
}

sub _submission_data {
    my( $pdmp, $field, $value ) = @_;

    my $data = $pdmp->{'_submission_data'};
    if ($value) {
        unless ($data) {
            $pdmp->{'_submission_data'} = $data = {};
        }
        $data->{$field} = $value;
    }
    elsif (! $data) {
        $data = {};
        my $seq_id = $pdmp->seq_id
            or confess "No seq_id";
        my $sth = prepare_statement(qq{
            SELECT UNIX_TIMESTAMP(submission_time)
              , submission_type
              , embl_file_md5_sum
              , region_start
              , region_end
            FROM submission
            WHERE seq_id = $seq_id
            ORDER BY submission_time DESC
            LIMIT 1
            });
        $sth->execute;
        if (my($time, $type, $md5_sum, $start, $end) = $sth->fetchrow) {
            $data->{'submission_time'}   = $time;
            $data->{'submission_type'}   = $type;
            $data->{'embl_file_md5_sum'} = $md5_sum;
            $data->{'region_start'}      = $start;
            $data->{'region_end'}        = $end;
        }
        $pdmp->{'_submission_data'} = $data;
    }
    return $data->{$field};
}

sub accept_date {
    my( $pdmp ) = @_;

    unless ($pdmp->{'_accept_date'}) {
        my $seq_id = $pdmp->seq_id
            or confess "No seq_id";
        my $sth = prepare_statement(qq{
            SELECT UNIX_TIMESTAMP(accept_date)
            FROM acception
            WHERE seq_id = $seq_id
            ORDER BY accept_date DESC
            LIMIT 1
            });
        $sth->execute;
        my ($date) = $sth->fetchrow;
        $pdmp->{'_accept_date'} = $date;
    }
    return $pdmp->{'_accept_date'};
}

sub online_path {
    my( $pdmp ) = @_;
    
    unless (exists $pdmp->{'_online_path'}) {
        $pdmp->{'_online_path'} = Hum::Tracking::online_path_from_project($pdmp->project_name);
    }
    return $pdmp->{'_online_path'};
}

sub online_cluster {
    my( $self ) = @_;
    
    unless (exists $self->{'_online_cluster'}) {
        my $sth = prepare_statement(q{
            SELECT cluster_name
            FROM project_path_cluster
            WHERE project_name = ?
            });
        $sth->execute($self->project_name);
        
        my ($cluster) = $sth->fetchrow;

        $self->{'_online_cluster'} = $cluster;
    }
    return $self->{'_online_cluster'};
}

sub species {
    my( $pdmp ) = @_;
    
    unless (exists $pdmp->{'_species'}) {
        $pdmp->{'_species'} = Hum::Tracking::species_from_project($pdmp->project_name);
    }
    return $pdmp->{'_species'};
}

sub chromosome {
    my( $pdmp ) = @_;
    
    unless (exists $pdmp->{'_chromosome'}) {
        $pdmp->{'_chromosome'} = 
            Hum::Tracking::chromosome_from_project($pdmp->project_name);
    }
    return $pdmp->{'_chromosome'};
}

sub chromosome_id {
    my( $pdmp ) = @_;
    
    my $chr     = $pdmp->chromosome;
    my $species = $pdmp->species;
    $chr        = 'UNKNOWN' if(ref($chr) eq 'HASH');
    my $chr_id = Hum::Submission::chromosome_id_from_species_and_chr_name($species, $chr);
    if (defined $chr_id) {
        return $chr_id;
    } else {
        return Hum::Submission::add_new_species_chr($species, $chr);
    }
}

sub sequence_name {
    my( $pdmp, $value ) = @_;
    
    if ($value) {
        $pdmp->{'_sequence_name'} = $value
    }
    elsif (! exists $pdmp->{'_sequence_name'}) {
        $pdmp->{'_sequence_name'} = Hum::Tracking::clone_from_project($pdmp->project_name);
    }
    return $pdmp->{'_sequence_name'};
}

sub htgs_phase {
    my( $pdmp, $value ) = @_;
        
    if (defined $value) {
        $value =~ /^(1|2|3)$/
            or confess "Value of htgs_phase '$value' can only be '1', '2' or '3'";
        $pdmp->{'_htgs_phase'} = $value;
    }
    elsif (! $pdmp->{'_htgs_phase'}) {
        my $phase;
        if (Hum::Tracking::is_finished($pdmp->project_name)) {
            $phase = 3;
        }
        elsif ($pdmp->current_status_number == 49
            or $pdmp->current_status_number == 50
            or $pdmp->contig_count == 1)
        {
            # Status "49" is "Indexed Manually Improved", which should be phase 2
            # Status "50" is "Manually Improved", which should also be phase 2
            $phase = 2;
        }
        else {
            $phase = 1;
        }
        $pdmp->{'_htgs_phase'} = $phase;
    }
    return $pdmp->{'_htgs_phase'};
}

sub external_clone_name {
    my( $pdmp ) = @_;
    
    unless ($pdmp->{'_external_clone_name'}) {
        my $project = $pdmp->project_name
            or confess "No project_name";
        my $clone = Hum::Tracking::clone_from_project($project)
            or confess "No clone for project '$project'";
        my $ext_clone = Hum::Tracking::intl_clone_name($clone);
        $pdmp->{'_external_clone_name'} = $ext_clone;
    }
    return $pdmp->{'_external_clone_name'};
}

sub primer_pair {
    my ($pdmp) = @_;
    if ($pdmp->clone_type eq 'PCR product') {
        unless ($pdmp->{'_primer_pair'}) {
            my ($primer1,$primer2) = Hum::Tracking::primer_pair($pdmp->project_name);
            if(defined($primer1) and defined($primer2)) {
                $pdmp->{'_primer_pair'} = "fwd_seq: $primer1, rev_seq: $primer2";
            }
        }
        return $pdmp->{'_primer_pair'};
    }
}


sub clone_type {
    my ($pdmp) = @_;
    
    $pdmp->_fetch_clone_type_reason unless $pdmp->{'_clone_type'};
    return $pdmp->{'_clone_type'};
}

sub seq_reason {
    my ($pdmp) = @_;
    
    $pdmp->_fetch_clone_type_reason unless $pdmp->{'_seq_reason'};
    return $pdmp->{'_seq_reason'};
}


sub _fetch_clone_type_reason {
    my ($pdmp) = @_;
    
    my ($type, $reason) = Hum::Tracking::clone_type_seq_reason($pdmp->project_name);
    $pdmp->{'_clone_type'} = $type;
    $pdmp->{'_seq_reason'} = $reason;
}

sub author {
    my( $pdmp ) = @_;
    
    my $project = $pdmp->project_name;
    unless ($pdmp->{'_author'}) {
        my( $author );
        eval{ $author = Hum::Tracking::project_finisher($project) };
        $author ||= Hum::Tracking::project_team_leader($project);
        $pdmp->{'_author'} = $author;
    }
    return $pdmp->{'_author'};
}

sub fish_map {
    my( $pdmp ) = @_;
    
    unless ($pdmp->{'_fish_map'}) {
        $pdmp->{'_fish_map'} = Hum::Tracking::fishData( $pdmp->project_name );
    }
    return $pdmp->{'_fish_map'};
}

sub set_ftp_path {
    my( $pdmp ) = @_;
    return $pdmp->set_path($FTP_ROOT);
}
sub set_ghost_path {
    my( $pdmp ) = @_;
    return $pdmp->set_path($FTP_GHOST);
}

# Where to dump different projects
{

    my $unfinished = 'unfinished_sequence';

    sub set_path {
        my( $pdmp, $base_dir ) = @_;
        
        $base_dir ||= '.';
        my $species = $pdmp->species;
        my $phase   = $pdmp->htgs_phase;
        my $sp = Hum::Species->fetch_Species_by_name($species)
            or confess "Don't know about '$species'";

        my $path = "$base_dir/" . $sp->ftp_dir;
        
        # Get the chromosome name if this species splits on chromosome
        if (my $prefix = $sp->ftp_chr_prefix) {
            my $chr = $pdmp->chromosome || 'UNKNOWN';
            if (ref($chr) eq 'HASH'){
                $path .= "/pooled";
            } else {
                $path .= "/$prefix$chr";
            }
        }
        
        if ($phase != 3) {
            $path .= "/$unfinished";
        }
        return $pdmp->file_path($path);
    }

    sub make_file_path_dir {
        my( $pdmp ) = @_;

        my $path = $pdmp->file_path;
        unless (-d $path) {
            mkpath($path) or confess "mkpath('$path') failed : $!";
        }
    }

    sub list_ftp_dirs {
        return _list_dirs($FTP_ROOT);
    }

    sub list_ghost_dirs {
        return _list_dirs($FTP_GHOST);
    }

    sub _list_dirs {
        my( $base_dir ) = @_;

        confess("base_dir not supplied") unless $base_dir;

        my( @dirs );
        foreach my $species (Hum::Species->fetch_all_Species) {
            my $dir_name   = $species->ftp_dir;
            my $chr_prefix = $species->ftp_chr_prefix;

            my $dir = "$base_dir/$dir_name";
            if ($chr_prefix) {
                local *BASE;
                if (opendir BASE, $dir) {
                    my @chr = grep /^$chr_prefix/, readdir BASE;
                    closedir BASE;
                    foreach my $c (@chr) {
                        push(@dirs, _add_dir("$dir/$c"));
                    }
                }
            } else {
                push(@dirs, _add_dir($dir));
            }
        }
        return(@dirs);
    }

    sub _add_dir {
        my( $dir ) = @_;
        
        my( @dirs );
        foreach my $d ($dir, "$dir/$unfinished") {
            push(@dirs, $d) if -d $d;
        }
        return(@dirs);
    }
}

sub file_path {
    my( $pdmp, $path ) = @_;

    if ($path) {
        $pdmp->{'_file_path'} = $path;
    }
    return $pdmp->{'_file_path'} || confess "file_path not set";
}

sub read_submission_data {
    my( $pdmp ) = @_;

    my $sid = $pdmp->sanger_id or confess "No sanger_id";
    my $get_dump = prepare_statement(q{
        SELECT a.project_name
          , a.project_suffix
          , UNIX_TIMESTAMP(d.dump_time) dump_time
          , d.htgs_phase
          , s.seq_id
          , s.sequence_name
          , s.sequence_version
          , s.embl_checksum
          , s.unpadded_length
          , s.contig_count
          , s.file_path
          , c.sequenced_by
          , c.funded_by
        FROM (project_acc a
          , project_dump d
          , sequence s)
        LEFT JOIN project_check c 
            ON c.project_name = a.project_name
        WHERE a.sanger_id = d.sanger_id
          AND d.seq_id = s.seq_id
          AND a.sanger_id = ?
          AND d.is_current = 'Y'
        });
    $get_dump->execute($sid);
    if (my $ans = $get_dump->fetchrow_hashref) {
        map $pdmp->$_($ans->{$_}), keys %$ans;
    } else {
        confess("No data for sanger_id '$sid'");
    }
}

sub get_seqby_and_fundby {
    my( $pdmp ) = @_;
    
    my $proj = $pdmp->project_name
        or confess "project_name not set";
    my $sth = prepare_track_statement(q{
        SELECT c.funded_by
          , c.sequenced_by
        FROM clone_project cp
          , clone c
        WHERE cp.clonename = c.clonename
          AND cp.projectname = ?
        });
    $sth->execute($proj);
    my ($fund_by, $seq_by) = $sth->fetchrow;
    $sth->finish;
    
    $pdmp->funded_by($fund_by);
    $pdmp->sequenced_by($seq_by);
}

sub fasta_file_path {
    my( $pdmp ) = @_;
    
    my $dir = $pdmp->file_path;
    my $seq_name = $pdmp->sequence_name;
    my $file = "$dir/$seq_name";
    
    return $file;
}

sub embl_file_path {
    my( $pdmp ) = @_;
    
    return $pdmp->fasta_file_path .'.embl';
}

sub quality_file_path {
    my( $pdmp ) = @_;
    
    return $pdmp->fasta_file_path .'.qual';
}

sub delete_all_sequence_files {
    my( $pdmp ) = @_;
    
    $pdmp->_set_not_current;
    
    my $total = 0;
    $total += $pdmp->delete_fasta_file;
    $total += $pdmp->delete_quality_file;
    $total += $pdmp->delete_embl_file;
    $pdmp = undef;
    return $total;
}

sub delete_fasta_file {
    my( $pdmp ) = @_;
    
    return unlink($pdmp->fasta_file_path);
}

sub delete_embl_file {
    my( $pdmp ) = @_;
    
    return unlink($pdmp->embl_file_path);
}

sub delete_quality_file {
    my( $pdmp ) = @_;
    
    return unlink($pdmp->quality_file_path);
}

sub read_fasta_file {
    my( $pdmp ) = @_;
    
    my $file = $pdmp->fasta_file_path;
    
    local *FASTA;
    open FASTA, $file or confess "Can't read '$file' : $!";
    my( $dna );
    while (<FASTA>) {
        if (/^>/) {
            my ($contig) = /Contig_ID:\s+(\w+)/;
            unless ($contig) {
                $pdmp->htgs_phase == 3
                    or confess "Can't see 'Contig_ID:' in fasta header; not a Sanger fasta file?";
                $contig = 'FINISHED_CONTIG';
            }
            $dna = $pdmp->new_dna_ref($contig);
        } else {
            chomp;
            $$dna .= lc $_;
        }
    }
    
    if (my $count = $pdmp->contig_count) {
        return $count;
    } else {
        confess "No contigs read";
    }
}

sub write_fasta_file {
    my( $pdmp ) = @_;
    
    my $seq_name = $pdmp->sequence_name;
    my $accno    = $pdmp->accession || '';
    my $file = $pdmp->fasta_file_path;
    my $phase = $pdmp->htgs_phase;
    
    warn "Phase = $phase\n";
    
    local *FASTA;
    open FASTA, "> $file" or confess "Can't write to '$file' : $!";
    
    foreach my $contig ($pdmp->contig_list) {
        my $dna = $pdmp->DNA($contig);
        my( $header );
        if ($phase == 3) {
            $header = $seq_name;
        } else {
            my $len = length($$dna);
            my $c_name = "$seq_name.$contig";
            $header = join('  ', $c_name
                , "Unfinished sequence: $seq_name"
                , "Contig_ID: $contig"
                , "acc=$accno"
                , "Length: $len bp"
                );
        }
    print FASTA ">$header\n" or confess "Can't print to '$file' : $!";
    while ($$dna =~ m/(.{1,60})/g) {
        print FASTA $1, "\n" or confess "Can't print to '$file' : $!";
    }
    }
    close FASTA or confess "Error creating fasta file ($?) $!";
}

sub read_embl_file {
    my( $pdmp ) = @_;
    
    my $file = $pdmp->embl_file_path;
    
    if (-e $file) {
        my $fh = gensym();
        my $parser = Hum::EMBL->new;
        open $fh, $file or die "Can't read '$file' : $!";
        my $embl = $parser->parse($fh) or die "No embl file returned";
        close $fh;
        return $embl;
    } else {
        return;
    }    
}

sub write_embl_file {
    my( $pdmp ) = @_;

    my $file = $pdmp->embl_file_path;
    my $embl = $pdmp->embl_file;
    
    my $fh = gensym();
    open $fh, "> $file" or confess "Can't write to '$file' : $!";
    print $fh $embl->compose or confess "Can't write to '$file' : $!";
    close $fh or confess "Error creating EMBL file ($?) $!";
}

{
    my $padding_Ns = 'n' x 800;

    sub make_old_embl {
        my ( $pdmp ) = @_;

        $pdmp->read_fasta_file unless $pdmp->contig_count;
        my $seq = '';
        foreach my $contig ($pdmp->contig_list) {
            $seq .= $padding_Ns if $seq;
            my $dna = $pdmp->DNA($contig);
            $seq .= $$dna;
        }
        my $embl = Hum::EMBL->new;
        $embl->newSequence->seq($seq);
        return $embl;
    }
}

{
    sub embl_file {
        my( $pdmp, $embl ) = @_;

        if ($embl) {
            $pdmp->{'_embl_file'} = $embl;
        }
        elsif (! $pdmp->{'_embl_file'}) {
            if ($pdmp->can('make_embl')) {
                $embl = $pdmp->make_embl($pdmp);
            } else {
                # Read the existing file, or make a new
                # one from the fasta file
                $embl = $pdmp->read_embl_file || $pdmp->make_old_embl;
            }
            $pdmp->{'_embl_file'} = $embl;
        }
        return $pdmp->{'_embl_file'}
    }

    sub embl_checksum {
        my( $pdmp, $sum ) = @_;

        # Return the checksum from the embl entry if we have it
        if ($pdmp->{'_embl_file'}) {
            confess("Can't set checksum when embl_file is filled!") if $sum;
            return $pdmp->{'_embl_file'}->Sequence->embl_checksum;
        }
        # Or set or return the stored value
        else {
            if ($sum) {
                $pdmp->{'_embl_checksum'} = $sum;
            }
            return $pdmp->{'_embl_checksum'};
        }
    }
}

sub read_accession_data {
    my( $pdmp ) = @_;

    my( $accession, $embl_name, @secondaries ) = acc_data($pdmp->sanger_id);
    $pdmp->accession($accession);
    $pdmp->embl_name($embl_name);
    
    my $project_name = $pdmp->project_name
        or confess "project_name not set";
    
    if (my($ext_sec, $institute) = Hum::Tracking::external_draft_info($pdmp->project_name)) {
        #warn "Got [$ext_sec, $institute]";
        $pdmp->draft_institute($institute);
        my $seen = 0;
        foreach my $sec (@secondaries) {
            $seen = 1 if $sec eq $ext_sec;
        }
        push(@secondaries, $ext_sec) unless $seen;
    }
    $pdmp->secondary(@secondaries) if @secondaries;
}


sub draft_institute {
    my( $pdmp, $institute ) = @_;
    
    if ($institute) {
        $pdmp->{'_draft_institute'} = $institute;
    }
    return $pdmp->{'_draft_institute'};
}

BEGIN {
    foreach my $func (qw( DNA BaseQuality )) {
        my $field = "_$func";
        
        {
            no strict 'refs';
            *$func = sub {
                my( $pdmp, $contig, $data ) = @_;
                
                confess("Can't call $func() without contig name")
                    unless $contig;
                if ($data) {
                    confess "Not a reference: '$data'" unless ref($data);
                    $pdmp->{$field}{$contig} = $data;
                }
                return $pdmp->{$field}{$contig};
            }
        }
    }

    sub contig_list {
        my( $pdmp ) = @_;

        if (my $order = $pdmp->{'_contig_order'}) {
            return @$order;
        }
        elsif ($pdmp->{'_DNA'}) {
            return sort keys %{$pdmp->{'_DNA'}};
        }
        else {
            confess "No contigs";
        }
    }

    sub contig_count {
        my( $pdmp, $count ) = @_;

        if ($pdmp->{'_DNA'}) {
            return scalar keys %{$pdmp->{'_DNA'}};
        } else {
            if (defined $count) {
                $pdmp->{'_contig_count'} = $count;
            }
            return $pdmp->{'_contig_count'};
        }
    }

    sub contig_order {
        my ($pdmp, $contig_order) = @_;

        if ($contig_order) {
            my $count = $pdmp->contig_count;
            if ($count != @$contig_order) {
                confess sprintf "Have %d contigs, but %d elements in array ref argument",
                    $count, scalar @$contig_order;
            }
            foreach my $contig (@$contig_order) {
                unless ($pdmp->{'_DNA'}{$contig}) {
                    confess "contig '$contig' in contig order list does not exist";
                }
            }
            $pdmp->{'_contig_order'} = $contig_order;
        }

        return $pdmp->{'_contig_order'};
    }

    sub delete_contig {
        my( $pdmp, $contig ) = @_;

        confess "Can't call delete_contig() without contig name"
            unless defined $contig;
        delete( $pdmp->{'_DNA'}{$contig} )
            or confess "No such DNA '$contig'";
        delete( $pdmp->{'_BaseQuality'}{$contig} )
            or confess "No such BaseQuality '$contig'";
        
        # Remove entry from contig_order array
        if (my $order = $pdmp->{'_contig_order'}) {
            for (my $i = 0; $i < @$order;) {
                if ($order->[$i] eq $contig) {
                    splice(@$order, $i, 1);
                } else {
                    $i++;
                }
            }
        }
    }

    sub new_dna_ref {
        my( $pdmp, $contig ) = @_;

        confess "Can't call new_dna_ref() without contig name"
            unless defined $contig;
        my $dna = '';
        $pdmp->{'_DNA'}{$contig} = \$dna;
        return $pdmp->{'_DNA'}{$contig};
    }

    sub contig_length {
        my( $pdmp, $contig ) = @_;
        
        confess "Can't call contig_length() without contig name"
            unless defined $contig;
        my $dna = $pdmp->{'_DNA'}{$contig}
            or confess "No such contig '$contig'";
        return length($$dna);
    }

    sub unpadded_length {
        my( $pdmp, $length ) = @_;
        
        if ($pdmp->{'_DNA'}) {
            my $l = 0;      
            foreach my $contig ($pdmp->contig_list) {
                $l += $pdmp->contig_length($contig);
            }
            if ($l) {
                return $l;
            } else {
                confess("Can't get length -- no contigs");
            }
        } else {
            if (defined $length) {
                $pdmp->{'_unpadded_length'} = $length;
            }
            return $pdmp->{'_unpadded_length'};
        }
    }
}

sub ebi_submit {
    my( $pdmp ) = @_;

	# We only save assembly tags if we're submitting/dumping
	$pdmp->assembly_tag_parser->save;

    my $seq_id = $pdmp->seq_id
        or confess "No seq_id";

    my $sub_type = $pdmp->submission_type;
    unless ($sub_type) {
        if ($pdmp->htgs_phase eq '3') {
            $sub_type = 'FIN';
        } else {
            $sub_type = 'UNFIN';
        }
    }

    my $md5_sum      = $pdmp->embl_file_md5_sum;
    my $region_start = $pdmp->region_start;
    my $region_end   = $pdmp->region_end;
    my $time = time;

    my $seq_name = $pdmp->sequence_name or confess "sequence_name not set";
    my $em_file = $pdmp->embl_file_path;
    confess "No such file '$em_file'" unless -e $em_file;

    my $ebi_ftp = 'Hum::EBI_FTP'->new();
    $ebi_ftp->put_project( $seq_name, $em_file );

    my $record_submission = prepare_statement(qq{
        INSERT submission( seq_id
                         , submission_time
                         , submission_type
                         , embl_file_md5_sum
                         , region_start
                         , region_end
                         )
        VALUES (?, FROM_UNIXTIME(?), ?, ?, ? ,?)
        });
    $record_submission->execute($seq_id, $time, $sub_type, $md5_sum, $region_start, $region_end);

    $pdmp->submission_time($time);
}

BEGIN {
    my $field = '_secondary';

    sub secondary {
        my $pdmp = shift;

        if (@_) {
            $pdmp->{$field} = [@_];
        }
        return $pdmp->{$field} ? @{$pdmp->{$field}} : ();
    }

    sub add_secondary {
        my( $pdmp, $sec ) = @_;

        push( @{$pdmp->{$field}}, $sec ) if $sec;
    }
}

sub store_dump {
    my( $pdmp ) = @_;
    
    # We only save assembly tags if we're submitting/dumping
	$pdmp->assembly_tag_parser->save;
        
    $pdmp->_store_project_acc;
    my $seq_id = $pdmp->_store_sequence
        or confess "Got no seq_id from _store_sequence()";
    $pdmp->seq_id($seq_id);
    $pdmp->_store_project_dump;
}


=pod

 +------------------+---------------------------+------+-----+------------+----------------+
 | Field            | Type                      | Null | Key | Default    | Extra          |
 +------------------+---------------------------+------+-----+------------+----------------+
 | seq_id           | int(11)                   |      | PRI | 0          | auto_increment |
 | sequence_name    | varchar(20)               |      | MUL |            |                |
 | sequence_version | int(11)                   | YES  |     | NULL       |                |
 | embl_checksum    | int(10) unsigned zerofill |      | MUL | 0000000000 |                |
 | unpadded_length  | int(10) unsigned          |      | MUL | 0          |                |
 | contig_count     | int(11)                   |      |     | 0          |                |
 | file_path        | varchar(200)              |      |     |            |                |
 | chromosome_id    | int(10) unsigned          |      | MUL | 1          |                |
 +------------------+---------------------------+------+-----+------------+----------------+

=cut

{
    my @fields = qw(
        sequence_name
        embl_checksum
        unpadded_length
        contig_count
        file_path
        chromosome_id
    );
    
    sub _store_sequence {
        my( $pdmp ) = @_;

        my $insert = prepare_statement(q{
            INSERT INTO sequence(seq_id,}
            . join(',', @fields)
            . q{) VALUES (NULL,?,?,?,?,?,?)}
            );
        $insert->execute(map $pdmp->$_(), @fields);
        return $insert->{'mysql_insertid'};   # The auto_incremented value
    }
}

=pod

 +------------+-----------------------------+------+-----+---------------------+-------+
 | Field      | Type                        | Null | Key | Default             | Extra |
 +------------+-----------------------------+------+-----+---------------------+-------+
 | sanger_id  | varchar(20)                 |      | PRI |                     |       |
 | dump_time  | datetime                    |      | PRI | 0000-00-00 00:00:00 |       |
 | seq_id     | int(11)                     |      | MUL | 0                   |       |
 | is_current | enum('Y','N')               |      |     | Y                   |       |
 | htgs_phase | enum('1','2','3','4','UNK') |      |     | UNK                 |       |
 +------------+-----------------------------+------+-----+---------------------+-------+

=cut

{
    my @fields = qw(
        sanger_id 
        dump_time 
        seq_id    
        htgs_phase
    );
    
    sub _store_project_dump {
        my( $pdmp ) = @_;
        
        # Unset is_current for previous rows
        my $update = prepare_statement(q{
            UPDATE project_dump
            SET is_current = 'N'
            WHERE sanger_id = ?
              AND seq_id != ?
            });
        $update->execute($pdmp->sanger_id, $pdmp->seq_id);

        my $insert = prepare_statement(q{
            INSERT INTO project_dump(is_current,}
            . join(',', @fields)
            . q{) VALUES ('Y',?,FROM_UNIXTIME(?),?,?)}
            );
        $insert->execute(map $pdmp->$_(), @fields);
    }
}

sub _set_not_current {
    my( $pdmp ) = @_;

    my $seq_id = $pdmp->seq_id
        or confess "No seq_id for dump";

    # Now unset is_current for previous rows
    my $update = prepare_statement(qq{
        UPDATE project_dump
        SET is_current = 'N'
        WHERE seq_id = $seq_id
        });
    $update->execute;
}

{

    my @fields = qw(
        sanger_id
        project_name
        project_suffix
    );
    
    sub _store_project_acc {
        my( $pdmp ) = @_;

        my $sid = $pdmp->sanger_id
            or confess "No Sanger ID";

        my $exists = prepare_statement(qq{
            SELECT count(*)
            FROM project_acc
            WHERE sanger_id = '$sid'
            });
        $exists->execute;
        my ($count) = $exists->fetchrow;
        
        unless ($count) {
            my $insert = prepare_statement(q{
                INSERT INTO project_acc(}
                . join(',', @fields)
                . q{) VALUES (?,?,?)}
                );
            $insert->execute(map $pdmp->$_(), @fields);
        }
    }
}

1;

__END__



=pod

=head1 NAME - Hum::ProjectDump

=head1 DESCRIPTION

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>

