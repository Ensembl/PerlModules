
### Hum::ProjectDump::EMBL::Unfinished

package Hum::ProjectDump::EMBL::Unfinished;

use strict;
use warnings;
use Carp;
use Hum::Submission 'prepare_statement';
use Hum::Tracking 'prepare_track_statement';
use Hum::Conf 'HUMPUB_BLAST';

use base 'Hum::ProjectDump::EMBL';

my $CONTIG_PREFIX = "Contig_prefix_ezelthrib";

# Overrides method in Hum::ProjectDump
sub embl_checksum {
    my( $pdmp ) = @_;
    
    return $pdmp->embl_file->Sequence->embl_checksum;
}

# Overrides method in Hum::ProjectDump
#sub htgs_phase {
#    my( $pdmp ) = @_;
#    
#    $pdmp->{'_actual_htgs_phase'} ||=
#        Hum::Tracking::is_finished($pdmp->project_name) ? 3 : 1;
#    return $pdmp->{'_actual_htgs_phase'};
#}

sub process_repository_data {
    my ($pdmp) = @_;
    
    warn "Reading gap contigs\n";
    $pdmp->read_gap_contigs;

    if ($pdmp->current_status_number == 50) {
        warn "Using contig order from caf file\n";
        $pdmp->fetch_contig_order_from_caf_file;
        $pdmp->contig_length_cutoff(1);
    }
    else {
        warn "Removing contigs under 1kb\n";
        $pdmp->contig_length_cutoff(1000);
        $pdmp->cleanup_contigs;
        $pdmp->contig_length_cutoff($pdmp->htgs_phase == 2 ? 250 : 2000);
    }

    warn "Making Q20 depth report\n";
    $pdmp->contig_and_agarose_depth_estimate;

    warn "Decontaminating contigs\n";
    $pdmp->decontaminate_contigs;

    # Set the htgs_phase for the EMBL keyword line to 2 if we've got a single contig
    if ($pdmp->contig_count == 1) {
        $pdmp->htgs_phase(2);
    }

    if ($pdmp->current_status_number != 50) {
        warn "Ordering contigs\n";
        $pdmp->order_contigs;
    }
}

sub store_dump {
    my( $pdmp ) = @_;
    
    $pdmp->SUPER::store_dump;
    $pdmp->store_draft_info;
}

sub store_draft_info {
    my( $pdmp ) = @_;

    my $seq_id = $pdmp->seq_id;
    my $is_draft = ($pdmp->is_htgs_draft) ? 'Y' : 'N';
    my ($q20_depth) = $pdmp->contig_and_agarose_depth_estimate;
    my $sth = prepare_statement(qq{
        INSERT draft_status(seq_id
              , is_htgs_draft
              , q20_contig_depth)
        VALUES($seq_id, '$is_draft', $q20_depth)
        });
    $sth->execute;
}

sub read_gap_contigs {
    my( $pdmp ) = @_;
    
    my $db_name          = uc $pdmp->project_name;
    my $db_dir              = $pdmp->online_path || confess "No online path";
    my $contam_report_file  = $pdmp->contamination_report_file;
    
    local *GAP2CAF;
    local $/ = ""; # Paragraph mode for reading caf file

    $pdmp->dump_time(time); # Record the time of the dump
    #my $gaf_pipe = "ssh -T -n -x -o 'StrictHostKeyChecking no' $cluster 'cd $db_dir; gap2caf -project $db_name -version 0 -silent -cutoff 2 -bayesian -staden -contigs $CONTIG_PREFIX | caf_depad | caftagfeature -tagid CONT -clean -vector $HUMPUB_BLAST/contamdb' |";
    my $save_gap2caf_output = '';
    if ($pdmp->current_status_number == 50) {
        my $tee_file = $pdmp->tee_file;
        $save_gap2caf_output = "| tee $tee_file";
    }
    my $gaf_pipe = "cd $db_dir; gap2caf -project $db_name -version 0 -silent -cutoff 2 -bayesian -staden -contigs $CONTIG_PREFIX $save_gap2caf_output | caf_depad | caftagfeature -tagid CONT -clean -vector $HUMPUB_BLAST/contamdb |";
    warn "gap2caf pipe: $gaf_pipe\n";
    open(GAP2CAF, $gaf_pipe)
        || die "COULDN'T OPEN PIPE FROM GAP2CAF : $!\n";

    while (<GAP2CAF>) {
        my ($object, $value) = split("\n", $_, 2);
        
        # Read contig DNA BaseQuality and Sequence objects.
        # We know which ones the contigs are without looking for Is_contig
        # tags as gap2caf was told to put $CONTIG_PREFIX in front of the
        # contig staden id.
        
        if (my ($class, $name) = $object =~ /(DNA|BaseQuality|Sequence)\s+\:\s+(\S+)/) {

            if (my ($contig) = $name =~ /$CONTIG_PREFIX(\d+)/o) {
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
    close(GAP2CAF) || confess "ERROR RUNNING GAP2CAF : exit status '$?' : '$!'\n";
}


sub contig_length_cutoff {
    my( $pdmp, $cutoff ) = @_;
    
    if (defined $cutoff) {
        $cutoff =~ /^\d+$/ or confess "Not a positive int '$cutoff'";
        $pdmp->{'_contig_length_cutoff'} = $cutoff;
    } else {
        $cutoff = $pdmp->{'_contig_length_cutoff'};
        $cutoff = 2000 unless defined($cutoff);
    }
    return $cutoff;
}

sub decontaminate_contigs {
    my( $pdmp ) = @_;
    
    my $cutoff = $pdmp->contig_length_cutoff;

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
                warn "$contig: Removing $length characters at $offset\n";
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
    
    $pdmp->cleanup_contigs;
}

sub cleanup_contigs {
    my( $pdmp ) = @_;

    my $cutoff = $pdmp->contig_length_cutoff;

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
        my $dna_len  = length($$dna);
        my $qual_len = length($$qual);
        if ($qual_len != $dna_len) {
            my $msg = "Differing DNA ($dna_len) and BaseQuality ($qual_len) lengths detected in contig '$contig'";
            if ($dna >= 1000) {
                $msg .= "\nDNA = '$dna'";
            }
            confess $msg;
        }
    }
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

sub contamination_report_file {
    my( $pdmp, $file ) = @_;
    
    if ($file) {
        $pdmp->{'_contamination_report_file'} = $file;
    }
    return $pdmp->{'_contamination_report_file'} || '/dev/null';
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

            # Store read extent
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
    $pdmp->contamination($name, \@contamination) if @contamination;
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

sub contig_and_agarose_depth_estimate {
    my( $pdmp ) = @_;
    
    my( $contig_agarose );
    if ($contig_agarose = $pdmp->{'_contig_and_agarose_depth_estimate'}) {
        warn "Returning pre-calculated Q20 depth report\n";
    } else {
        my $contig_len = 0;
        my $q20_bases  = 0;

        foreach my $contig ($pdmp->contig_list) {
            $contig_len += $pdmp->contig_length       ($contig);
            $q20_bases  += $pdmp->count_q20_for_contig($contig);
        }
        confess "No contig length!" unless $contig_len;
        
        $contig_agarose = [ ($q20_bases / $contig_len) ];
        if (my $ag_len = $pdmp->agarose_length) {
            push(@$contig_agarose, ($q20_bases / $ag_len));
        }
        $pdmp->{'_contig_and_agarose_depth_estimate'} = $contig_agarose;
    }
    return @$contig_agarose;
}

sub count_q20_for_contig {
    my ($pdmp, $contig) = @_;

    my $afs = $pdmp->{_assembled_from}->{$contig};

    my $read = "";
    my $quals;
    my $q20_count = 0;
    
    foreach my $af (@$afs) {
        
        # Get the quality string for the current read
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

                #warn "Looking at: $dirn\tvec_end[$start,$end]\tread[$rs,$re]\n";

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

        if ($insert_size) {
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
#        print STDERR "$contig1 joins to:\n";
#        while (my ($dirn, $contigs) = each %$dirns) {
#            while (my ($contig2, $joins) = each %$contigs) {
#                print STDERR "    $dirn $contig2 @$joins\n";
#            }
#        }
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

    # If there is only one group (fragment chain), then the
    # project is ordered and oriented, and is therefore phase 2
    $pdmp->htgs_phase(2) if @group == 1;

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

    my $contig_order = [];
    my $c_num = 0;
    
    # Add the left hand chain if we know what it is
    if ($left_chain) {
        @$contig_order = @$left_chain;
        $pdmp->record_contig_chains(\$c_num, $left_chain);
    }
    
    # Add the rest of the chains
    foreach my $chain (@group) {
        push(@$contig_order, @$chain);
        $pdmp->record_contig_chains(\$c_num, $chain);
    }

    # Add the right hand chain if we know what it is
    if ($right_chain) {
        push(@$contig_order, @$right_chain);
        $pdmp->record_contig_chains(\$c_num, $right_chain);
    }
    
    # Record the order of the contigs
    $pdmp->contig_order($contig_order);
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
        #use Data::Dumper;
        #warn "$contig=", Dumper($v_end);
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

sub fetch_contig_order_from_caf_file {
    my ($pdmp) = @_;

    my $caf_file = $pdmp->tee_file;
    my @caf_order = ('cafcat', '-summary', '-caf', $caf_file);
    warn "Running: @caf_order";
    open my $CAF, '-|', @caf_order or confess "Can't open pipe '@caf_order'; $!";
    my $contig_order = [];
    while (<$CAF>) {
        if (/$CONTIG_PREFIX(\d+)/o) {
            print STDERR $_;
            push(@$contig_order, $1);
        }
    }
    close $CAF or confess "Error running '@caf_order'; exit $?";
    unlink $caf_file or confess "Failed to remove file '$caf_file'; $!";
    $pdmp->contig_order($contig_order);
}

sub tee_file {
    my ($pdmp) = @_;

    return sprintf '/tmp/tee_%s_%p', $$, $pdmp;
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
            my $get_chem = prepare_track_statement(q{
                SELECT seqchem.suffix
                  , seqchem.is_primer
                  , dyeset.name
                FROM seqchemistry seqchem
                  , dyeset
                WHERE dyeset.id_dyeset = seqchem.id_dyeset
                });
            $get_chem->execute;

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

        my $get_lengths = prepare_track_statement(qq{
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


1;

__END__

=head1 NAME - Hum::ProjectDump::EMBL::Unfinished

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

and

Rob Davies B<email> rmd@sanger.ac.uk

who did the read_gap_contigs code.
