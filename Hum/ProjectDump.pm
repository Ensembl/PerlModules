
package Hum::ProjectDump;

use strict;
use Carp;
use Hum::Submission qw( sub_db acc_data );
use Hum::Tracking 'track_db';
use Hum::ProjectDump::EMBL;
use Hum::EMBL;
use Hum::EBI_FTP;
use Hum::Conf qw( FTP_ROOT FTP_GHOST FTP_STRUCTURE );
use File::Path;

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}

sub get_all_dumps_for_project {
    my( $pkg, $project ) = @_;
    
    my $sub_db = sub_db();
    my $get_sids = $sub_db->prepare(q{
        SELECT a.sanger_id
        FROM project_acc a
          , project_dump d
        WHERE a.sanger_id = d.sanger_id
          AND d.is_current = 'Y'
          AND a.project_name = ?
        });
    $get_sids->execute($project);
    
    my(@dumps);
    while (my($sid) = $get_sids->fetchrow) {
        my $pdmp = $pkg->new_from_sanger_id($sid);
        push(@dumps, $pdmp);
    }
    
    if (@dumps) {
        return @dumps;
    } else {
        my $pdmp = $pkg->create_new_dump_object($project);
        return($pdmp);
    }
}

sub create_new_dump_object {
    my( $pkg, $project ) = @_;
    
    my $sub_db = sub_db();
    my $is_active = $sub_db->selectall_arrayref(q{
        SELECT count(*)
        FROM project_check
        WHERE is_active = 'Y'
          AND project_name = ?
        })->[0];
    if ($is_active) {
        my $pdmp = $pkg->new;
        $pdmp->project_name($project);
        $pdmp->sanger_id("_\U$project");
        return $pdmp;
    } else {
        confess "Project '$project' is not active";
    }
}

sub new_from_sanger_id {
    my( $pkg, $sanger_id ) = @_;
    
    my $pdmp = $pkg->new;
    $pdmp->sanger_id($sanger_id);
    $pdmp->read_accession_data;
    $pdmp->read_submission_data;
    
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
        submission_type
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

sub online_path {
    my( $pdmp ) = @_;
    
    unless (exists $pdmp->{'_online_path'}) {
        $pdmp->{'_online_path'} = Hum::Tracking::online_path_from_project($pdmp->project_name);
    }
    return $pdmp->{'_online_path'};
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
        $pdmp->{'_chromosome'} = Hum::Tracking::chromosome_from_project($pdmp->project_name);
    }
    return $pdmp->{'_chromosome'};
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
        $value =~ /^(1|3)$/
            or confess "Value of htgs_phase '$value' can only be '1' or '3'";
        $pdmp->{'_htgs_phase'} = $value;
        return $value;
    }
    elsif (! $pdmp->{'_htgs_phase'}) {
        $pdmp->{'_htgs_phase'} = Hum::Tracking::is_finished($pdmp->project_name) ? 3 : 1;
    }
    return $pdmp->{'_htgs_phase'};
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
        my $chr     = $pdmp->chromosome;
        my $phase   = $pdmp->htgs_phase;
        my $p = $FTP_STRUCTURE->{$species}
            or confess "Don't know about '$species'";

        my $path = "$base_dir/$p->[0]";
        $path .= "/$p->[1]$chr" if $p->[1];
        if ($phase == 0 or $phase == 1) {
            $path .= "/$unfinished";
        }
        return $pdmp->file_path($path);
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
        foreach my $species (sort keys %$FTP_STRUCTURE) {
            my($dir_name, $chr_prefix) = @{$FTP_STRUCTURE->{$species}};
            
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
    my $sub_db = sub_db();
    my $get_dump = $sub_db->prepare(q{
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
        FROM project_acc a
          , project_dump d
          , sequence s
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

sub contig_chain {
    my( $pdmp, $contig, $i ) = @_;
    
    if (defined $i) {
        $pdmp->{'_contig_chain'}{$contig} = $i;
    }
    return $pdmp->{'_contig_chain'}{$contig};
}

sub revcomp_contig {
    my( $pdmp, $contig ) = @_;

    confess "Can't call revcomp_contig() without contig name"
        unless defined $contig;
    warn "Reverse complementing contig '$contig'\n";
    my $dna = $pdmp->DNA($contig)
        or confess "No such DNA '$contig'";
    $$dna = reverse($$dna);
    $$dna =~ tr{acgtrymkswhbvdnACGTRYMKSWHBVDN}
               {tgcayrkmswdvbhnTGCAYRKMSWDVBHN};
    my $qual = $pdmp->BaseQuality($contig)
        or confess "No such BaseQuality '$contig'";
    $$qual = reverse($$qual);
    
    if (my $v_end = $pdmp->vector_ends($contig)) {
        use Data::Dumper;
        warn "$contig=", Dumper($v_end);
        while (my($end, $side) = each %$v_end) {
            if ($side eq 'left') {
                $v_end->{$end} = 'right';
            }
            elsif ($side eq 'right') {
                $v_end->{$end} = 'left';
            }
            else {
                confess "Unknown side '$side'";
            }
        }
    }
}

sub cleanup_contigs {
    my( $pdmp, $cutoff ) = @_;

    $cutoff = 2000 unless defined $cutoff;

    # Remove any detected contamination
    foreach my $contig ($pdmp->contig_list) {
        my $dna  = $pdmp->DNA        ($contig);
        my $qual = $pdmp->BaseQuality($contig);
        
        if (my $contam = $pdmp->contamination($contig)) {
            #warn "Contig '$contig' is contaminated\n";
            foreach my $c (@$contam) {
                my $offset = $c->[0] - 1;
                my $length = $c->[1] - $c->[0] + 1;
                # Mask DNA and qual with characters which won't appear
                # Max score for quality is 99, so shouldn't be any with
                # score of 255 (which is octal 177)
                substr($$dna,  $offset, $length) = '#'    x $length;
                substr($$qual, $offset, $length) = "\177" x $length;
            }
            
            # Get dna and quality strings which are above the cutoff length
            my @dna_bits  = grep length($_) >= $cutoff, split /#+/,    $$dna;
            my @qual_bits = grep length($_) >= $cutoff, split /\177+/, $$qual;
            
            # Delete the old contig
            $pdmp->delete_contig($contig);
            
            # Store any significant fragments remaining
            for (my $i = 0; $i < @dna_bits; $i++) {
                my $name = "$contig.$i";
                $pdmp->DNA        ($name,  \$dna_bits[$i]);
                $pdmp->BaseQuality($name, \$qual_bits[$i]);
            }
        }
    }

    foreach my $contig ($pdmp->contig_list) {
        my $dna  = $pdmp->DNA        ($contig);
        my $qual = $pdmp->BaseQuality($contig);

        # Check that all pads are removed
        confess "Bad characters in dna contig '$contig':\n$$dna"
            if $$dna =~ /[^acgtn]/;
    
        # Remove trailing n's from contig
        if ($$dna =~ s/(n+)$//) {
            my $n_len = length($1);
            warn "Removed $n_len trailing N's from contig '$contig'";
            my $q_offset = length($$qual) - $n_len;
            substr($$qual, $q_offset, $n_len) = '';
        }

        # Filter out contigs shorter than minimum contig length
	if (length($$dna) < $cutoff) {
            $pdmp->delete_contig($contig);
        }
    }
    confess "No significant contigs found" unless $pdmp->contig_count;
    
    # Check that dna and basequality strings are all the same length
    $pdmp->validate_contig_lengths;
}

sub validate_contig_lengths {
    my( $pdmp ) = @_;

    foreach my $contig ($pdmp->contig_list) {
        my $dna  = $pdmp->DNA($contig);
        my $qual = $pdmp->BaseQuality($contig);
        my $dna_len  = length($dna);
        my $qual_len = length($qual);
        confess "Differing DNA ($dna_len) and BaseQuality ($qual_len) lengths detected in contig '$contig'"
            unless $qual_len == $dna_len;
    }
}

sub add_contig_chain {
    my( $pdmp, $chain ) = @_;

    confess "No chain supplied" unless $chain;
    push(@{$pdmp->{'_contig_chain'}}, $chain);
}

sub read_gap_contigs {
    my( $pdmp ) = @_;
    my $db_name  = uc $pdmp->project_name;
    my $db_dir   = $pdmp->online_path || confess "No online path";
    
    local *GAP2CAF;
    local $/ = ""; # Paragraph mode for reading caf file

    my $contig_prefix = "Contig_prefix_ezelthrib";

    $pdmp->dump_time(time); # Record the time of the dump
    my $gaf_pipe = "cd $db_dir; gap2caf -project $db_name -version 0 -silent -cutoff 2 -bayesian -staden -contigs $contig_prefix | caf_depad | caftagfeature -tagid CONT -clean -vector /nfs/disk100/humpub/blast/contamdb 2>/dev/null |";
    warn "gap2caf pipe: $gaf_pipe\n";
    open(GAP2CAF, $gaf_pipe)
	|| die "COULDN'T OPEN PIPE FROM GAP2CAF : $!\n";
    
    while (<GAP2CAF>) {
	my ($object, $value) = split("\n", $_, 2);
	
	# Read contig DNA BaseQuality and Sequence objects.
	# We know which ones the contigs are without looking for Is_contig
	# tags as gap2caf was told to put $contig_prefix in front of the
	# contig staden id.
	
	if (my ($class, $name) = $object =~ /(DNA|BaseQuality|Sequence)\s+\:\s+(\S+)/) {

	    if (my ($contig) = $name =~ /$contig_prefix(\d+)/o) {
		# It's a Contig object
		if ($class eq 'DNA') {
		    $value =~ s/\s+//g;
		    $value = lc $value;
		    $pdmp->DNA($contig, \$value);
		}
                elsif ($class eq 'BaseQuality') {
                    my $qual = pack('C*', split(/\s+/, $value));
		    $pdmp->BaseQuality($contig, \$qual);
		}
                elsif ($class eq 'Sequence') {
		    $pdmp->parse_contig_tags($contig, \$value);
		}
	    } else {
		# It's a Read object
		if ($class eq 'Sequence' && $value =~ /Is_read/) {
		    $pdmp->parse_read_sequence($name, \$value);
		}
                elsif ($class eq 'BaseQuality') {
		    $pdmp->read_quality($name, pack('C*', split(/\s+/, $value)));
		}
	    }
	}
    }
    close(GAP2CAF) || confess $! ? "ERROR RUNNING GAP2CAF : exit status $?\n"
                                 : "ERROR RUNNING GAP2CAF : $!\n";
}

sub parse_read_sequence {
    my ($pdmp, $name, $seq) = @_;
    
    # Accumulate statistics for the sequencing vectors used
    my ($seq_vec) = $$seq =~ /Sequencing_vector\s+\"(\S+)\"/;
    $pdmp->count_vector($seq_vec);
    
    # The suffix of the read name shows what chemistry was used
    $pdmp->count_chemistry($name);
    
    # Record wether this read includes the vector end
    $pdmp->record_vector_end_reads($name, $seq);
    
    # The template is the name of the subclone
    # which the read is from.
    my $template;
    if ($$seq =~ /Template\s+(\S+)/) {
	$template = $1;
    } else {
	$template = $name;
	$template =~ s/\..*//;
    }
    $pdmp->read_template($name, $template);

    if ($$seq =~ /Insert_size\s+\d+\s+(\d+)/) {
        $pdmp->insert_size($template, $1);
    }
}

sub insert_size {
    my( $pdmp, $template, $value ) = @_;
    
    if (defined $value) {
        $pdmp->{'_template_max_insert'}{$template} = $value;
    }
    return $pdmp->{'_template_max_insert'}{$template};
}


{
    sub read_list {
        my( $pdmp ) = @_;

        return keys %{$pdmp->{'_read_templates'}};
    }

    sub read_template {
        my( $pdmp, $name, $value ) = @_;

        if (defined $value) {
            $pdmp->{'_read_templates'}{$name} = $value;
        }
        return $pdmp->{'_read_templates'}{$name};
    }

    sub read_extent {
        my( $pdmp, $name, $value ) = @_;

        if ($value) {
            $pdmp->{'_read_extents'}{$name} = $value;
        }
        return $pdmp->{'_read_extents'}{$name};
    }

    sub remove_read_info_for_contigs {
        my $pdmp = shift;
        my %contig_to_delete = map {$_, 1} @_;

        foreach my $read ($pdmp->read_list) {
            my $extent = $pdmp->read_extent($read) or next;
            if ($contig_to_delete{$extent->[0]}) {
                delete($pdmp->{'_read_templates'}{$read});
                delete($pdmp->{'_read_extents'  }{$read});
            }
        }
    }
}

sub read_quality {
    my ($pdmp, $name, $qual) = @_;

    if (defined $qual) {
	$pdmp->{'_read_quality'}{$name} = $qual;
    }

    return $pdmp->{'_read_quality'}{$name};
}

sub assembled_from {
    my( $pdmp, $name, $from_array ) = @_;
    
    if ($from_array) {
        $pdmp->{'_assembled_from'}{$name} = $from_array;
    }
    return $pdmp->{'_assembled_from'}{$name};
}

sub contamination {
    my( $pdmp, $name, $contam_array ) = @_;
    
    if ($contam_array) {
        $pdmp->{'_assembled_contam'}{$name} = $contam_array;
    }
    return $pdmp->{'_assembled_contam'}{$name};
}

sub parse_contig_tags {
    my ($pdmp, $name, $seq) = @_;

    my @af;
    my @contamination;

    foreach my $line (split(/\n/, $$seq)) {
        my ($key, @values) = split(" ", $line);
	if ($key eq "Assembled_from") {
            my ($read, $cs, $ce, $rs, $re) = @values;
	    push(@af, [$read, $cs, $ce, $rs, $re]);
	    my $reverse = ($cs > $ce);
	    if ($reverse) { ($cs, $ce) = ($ce, $cs); }
	    if (my $extent = $pdmp->read_extent($read)) {

		my ($contig, $ecs, $ece, $ers, $ere) = @{$extent};

		if ($cs > $ecs) { $cs = $ecs; }
		if ($ce < $ece) { $ce = $ece; }
		if ($rs > $ers) { $rs = $ers; }
		if ($re < $ere) { $re = $ere; }
	    }

            $pdmp->read_extent($read, [$name, $cs, $ce, $rs, $re, $reverse]);
	}
        elsif ($key eq "Tag") {
            my ($tag, $from, $to) = @values;
            if ($tag eq "CONT") {
                if ($from > $to) {
                    ($from, $to) = ($to, $from);
                }
                push(@contamination, [$from, $to]);
            }
        }
    }

    @af = sort { $a->[0] cmp $b->[0] || $a->[3] <=> $b->[3] || $a cmp $b } @af;
    $pdmp->assembled_from($name, \@af);
    $pdmp->contamination($name, \@contamination);
}

{
    my %vector_string = (
        m13mp18 => 'M13; M77815;',
	puc18   => 'plasmid; L08752;',
    );

    sub count_vector {
        my ($pdmp, $vector) = @_;

        my $ncbi_vec = $vector_string{lc $vector} or return;

        $pdmp->{'_vector_count'}{$ncbi_vec}++;
    }
}

sub count_q20_for_contig {
    my ($pdmp, $contig) = @_;

    my $afs = $pdmp->{_assembled_from}->{$contig};

    my $read = "";
    my $quals;
    my $q20_count = 0;
    
    foreach my $af (@$afs) {
	if ($read ne $af->[0]) {
	    $read = $af->[0];
	    $quals = $pdmp->read_quality($read);
	}

	my ($start, $end) = ($af->[3], $af->[4]);
	if ($start > $end) { ($start, $end) = ($end, $start); }
	my $part = substr($quals, $start - 1, $end - $start + 1);
        
        # ascii 023 = decimal 19
        # This counts the number of characters which are not
        # in the range 0-19
	$q20_count += $part =~ tr/\000-\023//c;
    }

    return $q20_count;
}

sub record_vector_end_reads {
    my ($pdmp, $name, $read) = @_;

    my ($start, $end, $vec_end)
	= $$read =~ /Clone_vec\s+CVEC\s+(\d+)\s+(\d+)\s+\"CAF\:End\=(Left|Right)/;

    return unless ($vec_end);

    push(@{$pdmp->{'_vector_end_reads'}{$vec_end}}, [$name, $start, $end]);
}

sub get_vector_end_reads {
    my( $pdmp, $vec_end ) = @_;
    
    if (my $end_list = $pdmp->{'_vector_end_reads'}{$vec_end}) {
        return @$end_list;
    } else {
        return;
    }
}

sub vector_ends {
    my( $pdmp, $contig ) = @_;

    # Fill in the _vector_ends hash the first time we're called
    unless (exists $pdmp->{'_vector_ends'}) {
        $pdmp->{'_vector_ends'} = undef;
        
        VECTOR_END: foreach my $vec_end ('Left', 'Right') {

            my @ends = $pdmp->get_vector_end_reads($vec_end) or next;

	    my $contig;
	    my $contig_end;

	    foreach my $found_vec (@ends) {
	        my ($read, $start, $end) = @$found_vec;

                my $extent = $pdmp->read_extent($read) or next;

                my ($name, $cs, $ce, $rs, $re, $dirn) = @$extent;

	        $contig ||= $name;
	        if ($contig ne $name) {
                    # Contradictory vector end info
		    next VECTOR_END;
	        }

	        my $rcontig_end;

                warn "Looking at: $dirn\tvec_end[$start,$end]\tread[$rs,$re]\n";

                # rmd wrote this, and I don't understand it. -- jgrg
	        if ($dirn) {
		    # Reverse read
		    if    ($end   < $rs) { $rcontig_end = "right"; }
		    elsif ($start > $re) { $rcontig_end = "left";  }
	        } else {
		    # Forward read
		    if    ($end   < $rs) { $rcontig_end = "left";  }
		    elsif ($start > $re) { $rcontig_end = "right"; }
	        }
                next unless $rcontig_end;

                $contig_end ||= $rcontig_end;
	        if ($contig_end ne $rcontig_end) {
                    # Contradictory vector end info
		    next VECTOR_END;
	        }
	    }
            
            $pdmp->{'_vector_ends'}{$contig}{$vec_end} = $contig_end
                if $contig_end; # $contig_end is sometimes not set
        }
    }

    if (defined($contig)) {
        return $pdmp->{'_vector_ends'}{$contig};
    } else {
        # Just return a ref to the whole damn thing.
        return $pdmp->{'_vector_ends'};
    }
}

sub order_contigs {
    my ($pdmp) = @_;

    # Do we have read information?
    my @read_names = $pdmp->read_list or return;
    
    my %contig_lengths = map {$_, $pdmp->contig_length($_)} $pdmp->contig_list;

    my %overhanging_templates;

    # First find reads which point out from the ends of the contigs.
    foreach my $read (@read_names) {
        my $extent      = $pdmp->read_extent($read) or next;
	my $template    = $pdmp->read_template($read);
	my $insert_size = $pdmp->insert_size($template);

	my ($contig, $cs, $ce, $rs, $re, $reverse) = @$extent;
	next unless (exists($contig_lengths{$contig}));
	my $clen = $contig_lengths{$contig};

	if ($reverse) {
	    if ($ce < $insert_size) {
		$overhanging_templates{$template}->{$contig} =
		    [$read, 'L', $ce, $insert_size - $ce];
	    }
	} else {
	    if (($clen - $cs) < $insert_size) {
		$overhanging_templates{$template}->{$contig} =
		    [$read, 'R', $clen - $cs, $insert_size - ($clen - $cs)];
	    }
	}
    }

    # Next make a graph of which contigs are joined by read pairs.
    my %joined_contigs;
    my @anomalies;

    while (my ($template, $contigs) = each %overhanging_templates) {
	my $count = scalar(keys %$contigs);

	next unless ($count == 2);
	my ($contig1, $contig2) = keys %$contigs;
	my ($read1, $dirn1, $in_contig1, $overhang1) = @{$contigs->{$contig1}};
	my ($read2, $dirn2, $in_contig2, $overhang2) = @{$contigs->{$contig2}};

	next if ($overhang1 < $in_contig2);
	next if ($overhang2 < $in_contig1);

	# $joined_contigs{$contig1}->{$contig2} = [values %$contigs];
	push(@{$joined_contigs{$contig1}->{$dirn1}->{$contig2}}, $dirn2);
	push(@{$joined_contigs{$contig2}->{$dirn2}->{$contig1}}, $dirn1);

	# Look for contig pairs where the joined ends are inconsistent
	if ($dirn2 ne $joined_contigs{$contig1}->{$dirn1}->{$contig2}->[0]
	    || $dirn1 ne $joined_contigs{$contig2}->{$dirn2}->{$contig1}->[0]){
	    push(@anomalies, [$contig1, $contig2]);
	}
    }

    # Remove joins where joined ends are inconsistent
    foreach my $anomaly (@anomalies) {
	my ($contig1, $contig2) = @$anomaly;
	delete($joined_contigs{$contig1}->{'L'}->{$contig2});
	delete($joined_contigs{$contig1}->{'R'}->{$contig2});
	delete($joined_contigs{$contig2}->{'L'}->{$contig1});
	delete($joined_contigs{$contig2}->{'R'}->{$contig1});
    }

    # Deal with branches.  If one scores better than the rest, use it
    # else delete all the possible branches
    while (my ($contig1, $dirns) = each %joined_contigs) {
	while (my ($dirn, $contigs) = each %$dirns) {
	    my @scores = ( 0, 0 );
	    while (my ($contig2, $joins) = each %$contigs) {
		push(@scores, scalar(@$joins));
	    }
	    my ($best_score, $next_best) = sort { $b <=> $a } @scores;
	    if ($next_best) {
		# Have found a branch
		if ($next_best == $best_score) {
		    # Don't know which one is best, so get rid of all of them
		    $best_score = 0;
		}
		foreach my $contig2 (keys %$contigs) {
		    my $score = scalar(@{$contigs->{$contig2}});
		    if ($score == $best_score) { next; }

		    my $dirn2 = $contigs->{$contig2}->[0];
		    delete($joined_contigs{$contig2}->{$dirn2}->{$contig1});
		    delete($joined_contigs{$contig1}->{$dirn}->{$contig2});
		}
	    }
	}
    }
#    while (my ($contig1, $dirns) = each %joined_contigs) {
#	print STDERR "$contig1 joins to:\n";
#	while (my ($dirn, $contigs) = each %$dirns) {
#	    while (my ($contig2, $joins) = each %$contigs) {
#		print STDERR "    $dirn $contig2 @$joins\n";
#	    }
#	}
#    }

    # Make chains of contigs based on the remaining read pair links
    my( %visited, @group );
    foreach my $contig ($pdmp->contig_list()) {
	next if ($visited{$contig});
	if (exists($joined_contigs{$contig})) {
	    my @chain;

	    # Look for links to left of current contig
	    my $c_dirn = 'L';
	    my $c_contig = $contig;
	    while ($c_contig) {
		last if (exists $visited{$c_contig});
                
                unless ($c_dirn eq 'L') {
                    $pdmp->revcomp_contig($c_contig);
                }
                unshift(@chain, $c_contig);
                
		$visited{$c_contig} = 1;
		last unless (exists($joined_contigs{$c_contig}->{$c_dirn}));
		my ($n_contig) = keys %{$joined_contigs{$c_contig}->{$c_dirn}};
		last unless ($n_contig);
		my ($n_dirn)
		    = @{$joined_contigs{$c_contig}->{$c_dirn}->{$n_contig}};
		last unless ($n_dirn);
		$c_contig = $n_contig;
		$c_dirn = ($n_dirn eq 'R') ? 'L' : 'R';
	    }

	    # Look for links to right of current contig
	    $c_dirn = 'R';
	    $c_contig = $contig;
	    pop(@chain);
	    delete($visited{$contig});
	    while ($c_contig) {
		last if (exists $visited{$c_contig});
                
                unless ($c_dirn eq 'R') {
                    $pdmp->revcomp_contig($c_contig);
                }
                push(@chain, $c_contig);
                
		$visited{$c_contig} = 1;
		last unless (exists($joined_contigs{$c_contig}->{$c_dirn}));
		my ($n_contig) = keys %{$joined_contigs{$c_contig}->{$c_dirn}};
		last unless ($n_contig);
		my ($n_dirn)
		    = @{$joined_contigs{$c_contig}->{$c_dirn}->{$n_contig}};
		last unless ($n_dirn);
		$c_contig = $n_contig;
		$c_dirn = ($n_dirn eq 'R') ? 'L' : 'R';
	    }
	    push(@group, \@chain);
	} else {
	    push(@group, [$contig]);
	    $visited{$contig} = 1;
	}
    }
    
    # Find contigs which are at left and right, because
    # they're at the SP6 or T7 primer sites.
    my( $left_contig, $right_contig );
    if (my $ends = $pdmp->vector_ends) {

        # Structure of $ends can be:
        #
        #   ends = {
        #       contig1 => {
        #           Left => 'left',
        #       },
        #       contig2 => {
        #           Right => 'right',
        #       },
        #   };
        #
        # or:
        #   ends = {
        #       contig1 => {
        #           Left => 'right',
        #           Right => 'left',
        #       },
        #   };
        #
        # etc...
                
        foreach my $contig (keys %$ends) {
            foreach my $v_end (keys %{$ends->{$contig}}) {
                my $side = $ends->{$contig}{$v_end};
                if ($side eq 'left') {
                    if ($left_contig) {
                        confess "'$contig' : Already have both left ('$left_contig') and right ('$right_contig') contigs"
                            if $right_contig;
                        if ($v_end eq 'Left') {
                            $right_contig = $left_contig;
                            $left_contig = $contig;
                        } else {
                            $right_contig = $contig;
                        }
                    } else {
                        $left_contig = $contig;
                    }
                }
                elsif ($side eq 'right') {
                    if ($right_contig) {
                        confess "'$contig' : Already have both left ('$left_contig') and right ('$right_contig') contigs"
                            if $left_contig;
                        if ($v_end eq 'Right') {
                            $left_contig = $right_contig;
                            $right_contig = $contig;
                        } else {
                            $left_contig = $contig;
                        }
                    } else {
                        $right_contig = $contig;
                    }
                }
            }
        }
    }

    # Remove the left and right chains from @group if we can find them
    my( $left_chain, $right_chain );
    CHAIN: for (my $i = 0; $i < @group;) {
        my $chain = $group[$i];
        foreach my $contig (@$chain) {
            if ($left_contig and $contig eq $left_contig) {
                $left_chain = $chain;
                splice(@group, $i, 1);
                
                # Reverse this chain if it isn't tagged as 'left'
                my $v_end = $pdmp->vector_ends($contig);
                unless (
                        $v_end->{'Left'} and $v_end->{'Left'}  eq 'left'
                    or $v_end->{'Right'} and $v_end->{'Right'} eq 'left'
                    ) {
                    @$left_chain = reverse(@$left_chain);
                    foreach my $c (@$left_chain) {
                        $pdmp->revcomp_contig($c);
                    }
                }
                next CHAIN;
            }
            elsif ($right_contig and $contig eq $right_contig) {
                $right_chain = $chain;
                splice(@group, $i, 1);
                
                # Reverse this chain if it isn't tagged as 'right'
                my $v_end = $pdmp->vector_ends($contig);
                unless (
                        $v_end->{'Left'} and $v_end->{'Left'}  eq 'right'
                    or $v_end->{'Right'} and $v_end->{'Right'} eq 'right'
                    ) {
                    @$right_chain = reverse(@$right_chain);
                    foreach my $c (@$right_chain) {
                        $pdmp->revcomp_contig($c);
                    }
                }
                next CHAIN;
            }
        }
        $i++;
    }

    # Sort the chains by longest first, or the name
    # of the first contig in the chain.
    @group = sort {scalar(@$b) <=> scalar(@$a)
        || $a->[0] cmp $b->[0]} @group;

    my( @contig_order );
    my $c_num = 0;
    
    # Add the left hand chain if we know what it is
    if ($left_chain) {
        @contig_order = @$left_chain;
        $pdmp->record_contig_chains(\$c_num, $left_chain);
    }
    
    # Add the rest of the chains
    foreach my $chain (@group) {
        push(@contig_order, @$chain);
        $pdmp->record_contig_chains(\$c_num, $chain);
    }

    # Add the right hand chain if we know what it is
    if ($right_chain) {
        push(@contig_order, @$right_chain);
        $pdmp->record_contig_chains(\$c_num, $right_chain);
    }
    
    # Record the order of the contigs
    $pdmp->{'_contig_order'} = \@contig_order;
}

sub record_contig_chains {
    my( $pdmp, $i, $chain ) = @_;
    
    # A chain of length one isn't a chain.
    return unless @$chain > 1;
    
    # Increment counter
    $$i++;
    
    foreach my $contig (@$chain) {
        $pdmp->contig_chain($contig, $$i);
    }
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
            $$dna .= $_;
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

sub write_quality_file {
    my( $pdmp ) = @_;
    
    my $seq_name = $pdmp->sequence_name;
    my $accno    = $pdmp->accession || '';
    my $file = $pdmp->quality_file_path;
    
    my $N = 30; # Number of quality values per line
    my $pat = 'A3' x $N;

    local *QUAL;
    open QUAL, "> $file" or confess "Can't write to '$file' : $!";
    foreach my $contig ($pdmp->contig_list) {
        my $qual = $pdmp->BaseQuality($contig);
        my $len = length($$qual);
        my $c_name = "$seq_name.$contig";
        my $header = join('  ', $c_name,
                               "Unfinished sequence: $seq_name",
                               "Contig_ID: $contig",
                               "acc=$accno",
                               "Length: $len bp");
	print QUAL ">$header\n" or confess "Can't print to '$file' : $!";
        my $whole_lines = int( $len / $N );

        for (my $l = 0; $l < $whole_lines; $l++) {
            
            my $offset = $l * $N;
            # Print a slice of the array on one line
            print QUAL pack($pat, unpack('C*', substr($$qual, $offset, $N))), "\n"
                or confess "Can't print to '$file' : $!";
        }
        
        if (my $r = $len % $N) {
            my $pat = 'A3' x $r;
            my $offset = $whole_lines * $N;
            print QUAL pack($pat, unpack('C*', substr($$qual, $offset))), "\n"
                or confess "Can't print to '$file' : $!";
        }

    }
    close QUAL or confess "Error creating quality file ($?) $!";
}

sub read_embl_file {
    my( $pdmp ) = @_;
    
    my $file = $pdmp->embl_file_path;
    
    
    if (-e $file) {
        local *EMBL;
        my $parser = Hum::EMBL->new;
        open EMBL, $file or die "Can't read '$file' : $!";
        my $embl = $parser->parse(\*EMBL) or die "No embl file returned";
        close EMBL;
        return $embl;
    } else {
        return;
    }    
}

sub write_embl_file {
    my( $pdmp ) = @_;

    my $file = $pdmp->embl_file_path;    
    my $embl = $pdmp->embl_file;
    
    local *EMBL;
    open EMBL, "> $file" or confess "Can't write to '$file' : $!";
    print EMBL $embl->compose or confess "Can't write to '$file' : $!";
    close EMBL or confess "Error creating EMBL file ($?) $!";
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
            if ($pdmp->read_list) {
                # We have read details, so it's a new dump
                bless $pdmp, 'Hum::ProjectDump::EMBL';
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
    $pdmp->secondary(@secondaries) if @secondaries;
}

{
    my( $record_submission );

    sub ebi_submit {
        my( $pdmp ) = @_;

        unless ($record_submission) {
            my $sub_db = sub_db();
            $record_submission = $sub_db->prepare(q{
                INSERT submission( seq_id
                                 , submission_time
                                 , submission_type )
                VALUES (?,FROM_UNIXTIME(?),?)
            });
        }

        my $sub_type = $pdmp->submission_type;
        unless ($sub_type) {
            my $phase = $pdmp->htgs_phase;
            if ($phase eq '1') {
                $sub_type = 'UNFIN';
            }
            elsif ($phase eq '3') {
                $sub_type = 'FIN';
            }
            else {
                confess("Can't determine submission type");
            }
        }
        my $time = time;
        
        my $seq_name = $pdmp->sequence_name or confess "sequence_name not set";
        my $em_file = $pdmp->embl_file_path;
        confess "No such file '$em_file'" unless -e $em_file;
        
        my $ebi_ftp = 'Hum::EBI_FTP'->new();
        $ebi_ftp->put_project( $seq_name, $em_file );
        
        $record_submission->execute($pdmp->seq_id, $time, $sub_type);
    }
}

{
    my %chem_name = (
        'ABI'         => ' ABI',
	'DYEnamic_ET' => ' ET',
	'BigDye'      => ' Big Dye',
	'MegaBace_ET' => ' ET',
    );

    my( %suffix_chem_map );

    sub count_chemistry {
        my ($pdmp, $name) = @_;

        unless (%suffix_chem_map) {
            my $get_chem = track_db()->prepare(q{
                SELECT seqchem.suffix
                  , seqchem.is_primer
                  , dyeset.name
                FROM seqchemistry seqchem
                  , dyeset
                WHERE dyeset.id_dyeset = seqchem.id_dyeset
                });
            $get_chem->execute();

            while (my ($suffix, $is_primer, $dyeset) = $get_chem->fetchrow_array()) {
	        $suffix =~ s/^\.//;

	        unless ($suffix_chem_map{$suffix}) {
	            my $chem = ($is_primer ? "Dye-primer" : "Dye-terminator");
	            my $chem2 = $chem_name{$dyeset} || "";
	            if ($chem2 eq ' ET') {
		        $chem2 = ($is_primer ? "-amersham" : " ET-amersham");
	            }
	            $suffix_chem_map{$suffix} = "$chem$chem2";
	        }
            }
            $get_chem->finish();
        }

        if (my ($suffix) = $name =~ /\.(...)/) {
	    if (my $c = $suffix_chem_map{$suffix}) {
	        $pdmp->{'_chem_count'}{$c}++;
	    }
        }
    }
}

{
    sub agarose_length {
        my( $pdmp ) = @_;

        $pdmp->_get_agarose_estimated_length
            unless exists($pdmp->{'_agarose_length'});
        return $pdmp->{'_agarose_length'};
    }

    sub agarose_error {
        my( $pdmp ) = @_;

        $pdmp->_get_agarose_estimated_length
            unless exists($pdmp->{'_agarose_length'});
        return $pdmp->{'_agarose_error'};
    }

    sub _get_agarose_estimated_length {
        my ($pdmp) = @_;

        my $dbh = track_db();

        my $get_lengths = $dbh->prepare(qq{
            SELECT COUNT(image.insert_size_bp)
              , AVG(image.insert_size_bp)
              , STDDEV(image.insert_size_bp)
            FROM rdrequest request
              , rdgel_lane lane
              , rdgel_lane_image image
              , rdrequest_enzyme enzyme
            WHERE request.id_rdrequest = lane.id_rdrequest
              AND lane.id_rdgel = image.id_rdgel
              AND lane.lane = image.lane
              AND request.id_rdrequest = enzyme.id_rdrequest
              AND image.isgood = 1
              AND request.clonename = ?
              });
        $get_lengths->execute($pdmp->project_name);
        
        my ($count, $avg, $stddev) = $get_lengths->fetchrow_array();
        $get_lengths->finish();

        $pdmp->{'_agarose_length'} = ($count > 0 ? $avg : undef);
        $pdmp->{'_agarose_error'}  = $stddev if $count > 2;
    }
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
    
    my $sub_db = sub_db();
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
 +------------------+---------------------------+------+-----+------------+----------------+

=cut

BEGIN {

    my @fields = qw(
        sequence_name
        sequence_version
        embl_checksum
        unpadded_length
        contig_count
        file_path
    );
    
    sub _store_sequence {
        my( $pdmp ) = @_;

        my $sub_db = sub_db();
        my $insert = $sub_db->prepare(q{
            INSERT INTO sequence(seq_id,}
            . join(',', @fields)
            . q{) VALUES (NULL,?,?,?,?,?,?)}
            );
        $insert->execute(map $pdmp->$_(), @fields);
        return $insert->{'insertid'};   # The auto_incremented value
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

BEGIN {

    my @fields = qw(
        sanger_id 
        dump_time 
        seq_id    
        htgs_phase
    );
    
    sub _store_project_dump {
        my( $pdmp ) = @_;

        my $sub_db = sub_db();
        
        # Unset is_current for previous rows
        my $update = $sub_db->prepare(q{
            UPDATE project_dump
            SET is_current = 'N'
            WHERE sanger_id = ?
              AND seq_id != ?
            });
        $update->execute($pdmp->sanger_id, $pdmp->seq_id);

        my $insert = $sub_db->prepare(q{
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
    my $update = sub_db()->prepare(q{
        UPDATE project_dump
        SET is_current = 'N'
        WHERE seq_id = ?
        });
    $update->execute($seq_id);
}


BEGIN {

    my @fields = qw(
        sanger_id
        project_name
        project_suffix
    );
    
    sub _store_project_acc {
        my( $pdmp ) = @_;

        my $sub_db = sub_db();
        my $replace = $sub_db->prepare(q{
            REPLACE INTO project_acc(}
            . join(',', @fields)
            . q{) VALUES (?,?,?)}
            );
        $replace->execute(map $pdmp->$_(), @fields);
    }
}

1;

__END__



=pod

=head1 NAME - Hum::ProjectDump

=head1 DESCRIPTION

=head2 Author

James Gilbert email B<jgrg@sanger.ac.uk>
