
package Hum::ProjectDump;

use strict;
use Carp;
use Hum::Submission qw( sub_db
                        acc_data
                        );
use Hum::Tracking qw( track_db
                      ref_from_query
                      is_finished
                      project_finisher
                      project_team_leader
                      fishData
                      );
use Hum::Conf qw( FTP_ROOT FTP_GHOST );
use File::Path;

# Object methods

sub new {
    my( $pkg ) = @_;

    my $self = {
	_vector_count => {},
	_chem_count   => {},
    };

    return bless $self, $pkg;
}

# Generate simple data access functions using closures
BEGIN {
        
    # List of fields we want scalar access fuctions to
    my @scalar_fields = qw(
        accession
        agarose_error
	agarose_length
        author
        dump_time
        chromosome
        embl_name
        htgs_phase
        online_path
        project_name
        fish_map
        sanger_id
        seq_id
        sequence_name
        sequence_version
        species
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

sub set_ftp_path {
    my( $pdmp ) = @_;
    return $pdmp->set_path($FTP_ROOT);
}
sub set_ghost_path {
    my( $pdmp ) = @_;
    return $pdmp->set_path($FTP_GHOST);
}

# Where to dump different projects
BEGIN {

    my %species_dirs = (
                        'Human'         => [ 'human/sequences', 'Chr_' ],
                        'Mouse'         => [ 'mouse',           'Chr_' ],
                        'Chicken'       => [ 'chicken'                 ],
                        'Fugu'          => [ 'fugu'                    ],
                        'Zebrafish'     => [ 'zebrafish'               ],
                        'Drosophila'    => [ 'drosophila'              ],
                        'Arabidopsis'   => [ 'arabidopsis'             ],
                        );
    sub set_path {
        my( $pdmp, $base_dir ) = @_;
        
        $base_dir ||= '.';
        my $species = $pdmp->species;
        my $chr     = $pdmp->chromosome;
        my $phase   = $pdmp->htgs_phase;
        my $p = $species_dirs{$species}
            or confess "Don't know about '$species'";

        my $path = "$base_dir/$p->[0]";
        $path .= "/$p->[1]$chr" if $p->[1];
        if ($phase == 0 or $phase == 1) {
            $path .= "/unfinished_sequence";
        }
        return $pdmp->file_path($path);
    }
}

sub file_path {
    my( $pdmp, $path ) = @_;
    
    if ($path) {
        $pdmp->{'_file_path'} = $path;
    }
    return $pdmp->{'_file_path'} || confess "file_path not set";
}

sub new_from_project_name {
    my( $pkg, $project ) = @_;
    
    my $pdmp = $pkg->new;
    $pdmp->project_name($project);
    $pdmp->read_tracking_details;
    $pdmp->sanger_id('_'. uc $project);
    $pdmp->read_accession_data;
    return $pdmp;
}


sub new_from_sanger_id {
    my( $pkg, $sanger_id ) = @_;
    
    my $sub_db = sub_db();
    my $get_dump = $sub_db->prepare(q{
        SELECT UNIX_TIMESTAMP(d.dump_time) dump_time
          , d.htgs_phase
          , s.sequence_name
          , s.sequence_version
          , s.embl_checksum
          , s.unpadded_length
          , s.contig_count
          , s.file_path
        FROM project_dump d
          , sequence s
        WHERE d.seq_id = s.seq_id
          AND d.is_current = 1
          AND d.sanger_id = ?
        });
    $get_dump->execute($sanger_id);
    if (my $ans = $get_dump->fetchrow_hashref) {
        my $pdmp = $pkg->new;
        map $pdmp->$_($ans->{$_}), keys %$ans; 
        return $pdmp;
    } else {
        return;
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
            foreach my $contig ($pdmp->contig_list) {
                $length += $pdmp->contig_length($contig);
            }
            return $length;
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
    my $dna = $pdmp->DNA($contig)
        or confess "No such DNA '$contig'";
    $$dna = reverse($$dna);
    $$dna =~ tr{acgtrymkswhbvdnACGTRYMKSWHBVDN}
               {tgcayrkmswdvbhnTGCAYRKMSWDVBHN};
    my $qual = $pdmp->BaseQuality
        or confess "No such BaseQuality '$contig'";
    $$qual = reverse($$qual);
    
    if (my $v_end = $pdmp->vector_ends($contig)) {
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

    $cutoff = 1000 unless defined $cutoff;

    foreach my $contig ($pdmp->contig_list) {
        my $dna  = $pdmp->DNA($contig);
        my $qual = $pdmp->BaseQuality($contig);

        # Depad BaseQuality array
        my $pos = length($$dna);
        while (($pos = rindex($$dna, '-', $pos)) >= 0) {
	    #splice(@$qual, $pos, 1);
	    substr($qual, $pos, 1) = '';
	    $pos--;
        }
        # Depad DNA
        $$dna =~ s/\-//g;

        # Report traling n's
        {
            my $n = 0;
            for (my $i = (length($$dna) - 1);
                 substr($$dna, $i, 1) eq 'n';
                 $i--) {
                print STDERR '.';
                $n++;
            }
            if ($n) {
                warn "\nIn project '", $pdmp->project_name,
                    "' contig '$contig' has $n trailing n's\n";
            }
        }
        ## Trim trailing n's from the contig
        #if ($$dna =~ s/(n+)$//) {
        #    my $n_len = length($&);
        #    my $n_pre = length($`);
        #    splice(@$qual, $n_pre, $n_len);
        #    print "Stripped $n_len n's from contig $n\n";
        #}

        # Filter out contigs shorter than minimum contig length
	if (length($$dna) < $cutoff) {
            $pdmp->delete_contig($contig);
        }
    }
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
    open(GAP2CAF, "cd $db_dir; gap2caf -project $db_name -version 0 -silent -cutoff 2 -bayesian -staden -contigs $contig_prefix 2> /dev/null | caf_depad |")
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
		    $pdmp->parse_assembled_from($contig, \$value);
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
    $pdmp->order_contigs;
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
    if (/Template\s+(\S+)/) {
	$template = $1;
    } else {
	$template = $name;
	$template =~ s/\..*//;
    }
    $pdmp->read_template($name, $template);

    if (/Insert_size\s+\d+\s+(\d+)/) {
	#$pdmp->{_template_max_insert}->{$template} = $1;
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

sub read_extents_ref {
    my( $pdmp ) = @_;
    
    return $pdmp->{'_read_extents'};
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

sub parse_assembled_from {
    my ($pdmp, $name, $seq) = @_;

    my @af;
    #my $read_extents = $pdmp->read_extents;

    foreach my $line (split(/\n/, $$seq)) {
	my ($af, $read, $cs, $ce, $rs, $re) = split(" ", $line);
	if ($af eq "Assembled_from") {
	    push(@af, [$read, $cs, $ce, $rs, $re]);
	    my $dirn = ($cs > $ce);
	    if ($dirn) { ($cs, $ce) = ($ce, $cs); }
	    #if (exists($read_extents->{$read})) {
	    if (my $extent = $pdmp->read_extent($read)) {

		my ($contig, $ecs, $ece, $ers, $ere) = @{$extent};

		if ($cs > $ecs) { $cs = $ecs; }
		if ($ce < $ece) { $ce = $ece; }
		if ($rs > $ers) { $rs = $ers; }
		if ($re < $ere) { $re = $ere; }
	    }

	    #$read_extents->{$read} = [$name, $cs, $ce, $rs, $re, $dirn];
            $pdmp->read_extent($read, [$name, $cs, $ce, $rs, $re, $dirn]);
	}
    }

    @af = sort { $a->[0] cmp $b->[0] || $a->[3] <=> $b->[3] || $a cmp $b } @af;

    #$pdmp->{_assembled_from}->{$name} = \@af;
    $pdmp->assembled_from($name, \@af);
}

{
    my %vector_string = (
        m13mp18 => 'M13; M77815;',
	puc18   => 'plasmid; L08752;',
    );

    sub count_vector {
        my ($pdmp, $vector) = @_;

        my $ncbi_vec = $vector_string{lc $vector} or return;

        $pdmp->{_vector_count}->{$ncbi_vec}++;
    }
}

sub count_chemistry {
    my ($pdmp, $name) = @_;

    if (my ($suffix) = $name =~ /\.(...)/) {
	if (exists($pdmp->{suffix_chemistry}->{$suffix})) {
	    $pdmp->{_chem_count}->{$pdmp->{suffix_chemistry}->{$suffix}}++;
	}
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

    #my %ends;
    #my $read_extents = $pdmp->read_extents;

    unless (exists $pdmp->{'_vector_ends'}) {
        $pdmp->{'_vector_ends'} = undef;
        
        foreach my $vec_end ('Left', 'Right') {

            my @ends = $pdmp->get_vector_end_reads($vec_end) or next;

	    #next unless (exists($pdmp->{_vector_end}->{$vec_end}));

	    my $contig;
	    my $contig_end;

	    #foreach my $found_vec (@{$pdmp->{_vector_end}->{$vec_end}}) {
	    foreach my $found_vec (@ends) {
	        my ($read, $start, $end) = @$found_vec;

	        #next unless (exists($read_extents->{$read}));
                my $extent = $pdmp->read_extent($read) or next;

                #my ($name, $cs, $ce, $rs, $re, $dirn)
                #= @{$read_extents->{$read}};
                my ($name, $cs, $ce, $rs, $re, $dirn) = @$extent;

	        unless ($contig) { $contig = $name; }
	        if ($contig ne $name) {
		    $contig = "";
		    last;
	        }

	        my $rcontig_end;

	        if ($dirn) {
		    # Reverse read
		    if    ($end   < $rs) { $rcontig_end = "right"; }
		    elsif ($start > $re) { $rcontig_end = "left";  }
	        } else {
		    # Forward read
		    if    ($end   < $rs) { $rcontig_end = "left";  }
		    elsif ($start > $re) { $rcontig_end = "right"; }
	        }
	        #unless ($rcontig_end) { next; }
                next unless $rcontig_end;

	        #unless ($contig_end) { $contig_end = $rcontig_end; }
                $contig_end ||= $rcontig_end;
	        if ($contig_end ne $rcontig_end) {
		    $contig = "";
		    last;
	        }
	    }

	    if ($contig) {
	        #$ends{$vec_end}->{$contig} = $contig_end;
                $pdmp->{'_vector_ends'}{$contig}{$vec_end} = $contig_end;
	    }
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

    #return unless (exists($pdmp->{_read_templates}));
    #return unless (exists($pdmp->{_template_max_insert}));
    #return unless (exists($pdmp->{_read_extents}));

    # Do we have read information?
    my @read_names = $pdmp->read_list or return;

    #my $read_templates = $pdmp->{_read_templates};
    #my $insert_sizes = $pdmp->{_template_max_insert};
    #my $extents = $pdmp->read_extents_ref;
    
    my %contig_lengths = map {$_, $pdmp->contig_length($_)} $pdmp->contig_list;

    my %overhanging_templates;

    # First find reads which point out from the ends of the contigs.

    #while (my ($read, $extent) = each %$extents) {
        #my $template = $read_templates->{$read};
        #my $insert_size = $insert_sizes->{$template};
    foreach my $read (@read_names) {
        my $extent      = $pdmp->read_extent($read);
	my $template    = $pdmp->read_template($read);
	my $insert_size = $pdmp->insert_size($template);

	my ($contig, $cs, $ce, $rs, $re, $dirn) = @$extent;
	next unless (exists($contig_lengths{$contig}));
	my $clen = $contig_lengths{$contig};

	if ($dirn) {
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
	#my @c = %$contigs;
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
                
		#my $fwd = ($c_dirn eq 'L') ? "F" : "R";
		#unshift(@chain, "$c_contig.$fwd");
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
                
		#my $fwd = ($c_dirn eq 'R') ? "F" : "R";
		#push(@chain, "$c_contig.$fwd");
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
            #$pdmp->add_contig_chain(\@chain);
	} else {
	    #push(@group, ["$contig.F"]);
	    push(@group, [$contig]);
	    $visited{$contig} = 1;
	}
    }
    
    # Find contigs which are at left and right, because
    # they're at the SP6 or T7 primer sites.
    my( $left_contig, $right_contig );
    $left_contig = $right_contig = '__NOT_FOUND__';
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
                    $left_contig = $contig;
                }
                elsif ($side eq 'right') {
                    $right_contig = $contig;
                }
            }
        }
    }

    # Remove the left and right chains from @group if we
    # can find them
    my( $left_chain, $right_chain );
    CHAIN: for (my $i = 0; $i < @group;) {
        my $chain = $group[$i];
        foreach my $contig (@$chain) {
            if ($contig eq $left_contig) {
                $left_chain = $chain;
                splice(@group, $i, 1);
                next CHAIN;
            }
            elsif ($contig eq $right_contig) {
                $right_chain = $chain;
                splice(@group, $i, 1);
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

sub read_fasta_file {
    my( $pdmp ) = @_;
    
    my $dir = $pdmp->file_path or confess "file_path not set";
    my $seq_name = $pdmp->sequence_name;
    my $file = "$dir/$seq_name";
    
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
    my $dir = $pdmp->file_path;
    my $file = "$dir/$seq_name";
    
    local *FASTA;
    open FASTA, "> $file" or confess "Can't write to '$file' : $!";
    foreach my $contig ($pdmp->contig_list) {
        my $dna = $pdmp->DNA($contig);
        my $len = length($$dna);
        my $c_name = "$seq_name.$contig";
        my $header = join('  ', $c_name,
                               "Unfinished sequence: $seq_name",
                               "Contig_ID: $contig",
                               "acc=$accno",
                               "Length: $len bp");
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
    my $dir = $pdmp->file_path;
    my $file = "$dir/$seq_name.qual";
    
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

sub write_embl_file {
    my( $pdmp ) = @_;

    my $seq_name = $pdmp->sequence_name;
    my $dir = $pdmp->file_path;
    my $file = "$dir/$seq_name.embl";
    
    my $embl = $pdmp->embl_file;
    
    local *EMBL;
    open EMBL, "> $file" or confess "Can't write to '$file' : $!";
    print EMBL $embl->compose or confess "Can't write to '$file' : $!";
    close EMBL or confess "Error creating EMBL file ($?) $!";
}

sub embl_file {
    my( $pdmp ) = @_;
    
    unless ($pdmp->{'_embl_file'}) {
        # Add EMBL dumping capability
        require Hum::ProjectDump::EMBL;
        bless $pdmp, 'Hum::ProjectDump::EMBL';
        
        $pdmp->{'_embl_file'} = $pdmp->make_embl($pdmp);
    }
    return $pdmp->{'_embl_file'}
}

sub embl_checksum {
    my( $pdmp ) = @_;
    
    return $pdmp->embl_file->Sequence->embl_checksum;
}

sub read_accession_data {
    my( $pdmp ) = @_;

    my( $accession, $embl_name, @secondaries ) = acc_data($pdmp->sanger_id);
    $pdmp->accession($accession);
    $pdmp->embl_name($embl_name);
    $pdmp->secondary(@secondaries) if @secondaries;
}

# Fills in information found in the oracle Tracking database
sub read_tracking_details {
    my( $pdmp ) = @_;

    my $project = $pdmp->project_name;
    my $dbh = track_db();
    my $query = qq{
        SELECT c.clonename sequence_name
          , c.speciesname species
          , c_dict.chromosome
          , o.online_path
        FROM chromosomedict c_dict
          , clone c
          , clone_project cp
          , project p
          , online_data o
        WHERE c_dict.id_dict = c.chromosome
          AND c.clonename = cp.clonename
          AND cp.projectname = p.projectname
          AND p.id_online = o.id_online (+)
          AND p.projectname = '$project'
    };
    my $project_details = $dbh->prepare($query);
    $project_details->execute;
    if (my $ans = $project_details->fetchrow_hashref) {
        foreach my $field (keys %$ans) {
            my $meth = lc $field;
            $pdmp->$meth($ans->{$field});
        }
        $pdmp->htgs_phase(is_finished($project) ? 3 : 1);
        $pdmp->fish_map(fishData( $project ));
        my( $author );
        eval{
            $author = project_finisher($project);
        };
        $author ||= project_team_leader($project);
        $pdmp->author($author);
	$pdmp->get_agarose_est_length();
	$pdmp->get_suffix_chemistries();
    } else {
        die "Couldn't get project details with query:\n$query"
    }
}

{
    my %chem_name = (
        'ABI'         => ' ABI',
	'DYEnamic_ET' => ' ET',
	'BigDye'      => ' Big Dye',
	'MegaBace_ET' => ' ET',
    );

    sub get_suffix_chemistries {
        my ($pdmp) = @_;

        my $dbh = track_db();

        my $query = qq{
            SELECT seqchem.suffix
              , seqchem.is_primer
              , dyeset.name
            FROM seqchemistry seqchem
              , dyeset
            WHERE dyeset.id_dyeset = seqchem.id_dyeset};
        my $get_chem = $dbh->prepare($query);
        $get_chem->execute();

        while (my ($suffix, $is_primer, $dyeset) = $get_chem->fetchrow_array()) {
	    $suffix =~ s/^\.//;

	    unless (exists($pdmp->{suffix_chemistry}->{$suffix})) {
	        my $chem = ($is_primer ? "Dye-primer" : "Dye-terminator");
	        my $chem2 = $chem_name{$dyeset} || "";
	        if ($chem2 eq ' ET') {
		    $chem2 = ($is_primer ? "-amersham" : " ET-amersham");
	        }
	        $pdmp->{suffix_chemistry}->{$suffix} = "$chem$chem2";
	    }
        }
        $get_chem->finish();
    }
}

sub get_agarose_est_length {
    my ($pdmp) = @_;

    my $dbh = track_db();

    my $query = qq{
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
          AND request.clonename = ?};

    my $get_lengths = $dbh->prepare($query);
    $get_lengths->execute($pdmp->sequence_name());
    my ($count, $avg, $stddev) = $get_lengths->fetchrow_array();
    $get_lengths->finish();

    if ($count > 0) { $pdmp->agarose_length($avg);   }
    if ($count > 2) { $pdmp->agarose_error($stddev); }
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
    my $seq_id = $pdmp->_store_sequence
        or confess "Got no seq_id from _store_sequence()";
    $pdmp->seq_id($seq_id);
    $pdmp->_store_project_dump;
}

=pod

 +------------------+--------------+------+-----+---------+----------------+
 | Field            | Type         | Null | Key | Default | Extra          |
 +------------------+--------------+------+-----+---------+----------------+
 | seq_id           | int(11)      |      | PRI | 0       | auto_increment |
 | sequence_name    | varchar(20)  |      | MUL |         |                |
 | sequence_version | int(11)      | YES  |     | NULL    |                |
 | embl_checksum    | int(11)      |      | MUL | 0       |                |
 | unpadded_length  | int(11)      |      | MUL | 0       |                |
 | contig_count     | int(11)      |      |     | 0       |                |
 | file_path        | varchar(200) |      |     |         |                |
 +------------------+--------------+------+-----+---------+----------------+

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
 | sanger_id  | varchar(20)                 |      | MUL |                     |       |
 | dump_time  | datetime                    |      | MUL | 0000-00-00 00:00:00 |       |
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
        my $update = $sub_db->prepare(q{
            UPDATE project_dump
            SET is_current = 'N'
            WHERE sanger_id = ?
            });
        $update->execute($pdmp->sanger_id);
        
        my $insert = $sub_db->prepare(q{
            INSERT INTO project_dump(is_current,}
            . join(',', @fields)
            . q{) VALUES ('Y',?,FROM_UNIXTIME(?),?,?)}
            );
        $insert->execute(map $pdmp->$_(), @fields);
    }
}

1;

__END__



=pod

=head1 NAME - Hum::ProjectDump

=head1 DESCRIPTION

=head2 Author

James Gilbert email B<jgrg@sanger.ac.uk>
