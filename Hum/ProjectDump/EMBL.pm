
package Hum::ProjectDump::EMBL;

use strict;
use Carp;
use Hum::ProjectDump;

use vars qw( @ISA );

@ISA = 'Hum::ProjectDump';

use Hum::Tracking qw( ref_from_query
                      library_and_vector
                      is_shotgun_complete
                      );
use Hum::EmblUtils qw( add_source_FT
                       add_Organism
                       );
use Hum::EMBL;
use Hum::EMBL::Utils qw( EMBLdate );
use Hum::Ace::SubSeq;

Hum::EMBL->import(
    'AC *' => 'Hum::EMBL::Line::AC_star',
    'BQ *' => 'Hum::EMBL::Line::BQ_star',
    );

sub make_embl {
    my( $pdmp ) = @_;

    my $project     = $pdmp->project_name;
    my $acc         = $pdmp->accession || '';
    my @sec         = $pdmp->secondary;
    my $embl_id     = $pdmp->embl_name || 'ENTRYNAME';
    my $species     = $pdmp->species;
    my $chr         = $pdmp->chromosome;
    my $map         = $pdmp->fish_map;
    my $ext_clone   = $pdmp->external_clone_name;
    my $binomial    = $pdmp->species_binomial;
    my $division    = $pdmp->EMBL_division;

    # Get the DNA, base quality string,
    # and map of contig positions.
    my($dna, $base_quality, $contig_map) = $pdmp->embl_sequence_and_contig_map;
    my $seqlength = length($dna);

    # New embl file object
    my $embl = Hum::EMBL->new();

    # ID line
    my $id = $embl->newID;
    $id->entryname($embl_id);
    $id->dataclass('standard');
    $id->molecule('DNA');
    $id->division($division);
    $id->seqlength($seqlength);
    $embl->newXX;

    # AC line
    my $ac = $embl->newAC;
    $ac->primary($acc);
    $ac->secondaries(@sec) if @sec;
    $embl->newXX;

    # AC * line
    my $ac_star = $embl->newAC_star;
    $ac_star->identifier($pdmp->sanger_id);
    $embl->newXX;

    # DE line
    $pdmp->add_Description($embl);

    # KW line
    $pdmp->add_Keywords($embl, scalar @$contig_map);

    # Organism
    add_Organism($embl, $species);
    $embl->newXX;

    # Reference
    $pdmp->add_Reference($embl, $seqlength);

    # CC lines
    $pdmp->add_Headers($embl, $contig_map);
    $embl->newXX;

    # Feature table header
    $embl->newFH;

    # Feature table source feature
    my( $libraryname ) = library_and_vector( $project );
    add_source_FT( $embl, $seqlength, $binomial, $ext_clone,
                   $chr, $map, $libraryname );

    # Feature table assembly fragments
    $pdmp->add_FT_entries($embl, $contig_map);
    $embl->newXX;

    # Sequence
    $embl->newSequence->seq($dna);

    # Base Quality
    $embl->newBQ_star->quality($base_quality) if $base_quality;

    $embl->newEnd;

    return $embl;
}

sub EMBL_division {
    my( $pdmp ) = @_;
    
    ### I assume this is the same for other organisms
    return 'HTG';
}

sub species_binomial {
    my( $pdmp ) = @_;
    
    unless ($pdmp->{'_species_binomial'}) {
        my $species = $pdmp->species;
        my $bi = Hum::EmblUtils::species_binomial($species);
        if ($bi) {
            $pdmp->{'_species_binomial'} = $bi;
        } else {
            confess "Can't make species binomail for '$species'";
        }
    }
    return $pdmp->{'_species_binomial'};
}

sub add_Reference {
    my( $pdmp, $embl, $seqlength ) = @_;
    
    return(1) if $pdmp->add_HGMP_Reference($embl, $seqlength);
    
    my $author = $pdmp->author;
    my $date = EMBLdate();
    
    my $query_email = 'humquery';
    if ($pdmp->species eq 'Zebrafish') {
        $query_email = 'zfish-help';
    }

    my $ref = $embl->newReference;
    $ref->number(1);
    $ref->positions("1-$seqlength");
    $ref->authors($author);
    $ref->locations("Submitted ($date) to the EMBL/Genbank/DDBJ databases.",
                    'Wellcome Trust Sanger Institute, Hinxton, Cambridgeshire, CB10 1SA, UK.',
                    "E-mail enquiries: $query_email\@sanger.ac.uk",
                    'Clone requests: clonerequest@sanger.ac.uk');
    $embl->newXX;
}


{
    my( @author_list );

    my $author_list = q{

        North P.
        Leaves N.
        Greystrong J.
        Coppola M.
        Manjunath S.
        Russell E.
        Smith M.
        Strachan G.
        Tofts C.
        Boal E.
        Cobley V.
        Hunter G.
        Kimberley C.
        Thomas D.
        Cave-Berry L.
        Weston P.
        Botcherby M.R.M.

        };
    
    foreach my $line (split /\n/, $author_list) {
        next unless $line =~ /\w/;
        $line =~ s/^\s+|\s*$//g;
        push(@author_list, $line);
    }

    sub add_HGMP_Reference {
        my( $pdmp, $embl, $seqlength ) = @_;

        return(0) unless $pdmp->sequenced_by == 58;

        my $date = EMBLdate();
        my $ext_clone = $pdmp->external_clone_name;
        my $bi_nom = $pdmp->species_binomial;
        
        my $ref = $embl->newReference;
        $ref->number(1);
        $ref->positions("1-$seqlength");
        $ref->comments('HGMP-RC part of the UK Mouse Sequencing Consortium');
        $ref->authors(@author_list);
        #$ref->title("The sequence of $bi_nom clone $ext_clone");
        $ref->locations(
            "Submitted ($date) to the EMBL/Genbank/DDBJ databases.",
            'Mouse Sequencing Group, HGMP-RC, Hinxton, Cambridge, CB10 1SB, UK.',
            'E-mail enquiries:- mrbotche@hgmp.mrc.ac.uk or pnorth@hgmp.mrc.ac.uk');
        $embl->newXX;
        
        return 1;
    }
}


sub add_Description {
    my( $pdmp, $embl ) = @_;
    
    my $species   = $pdmp->species;
    my $ext_clone = $pdmp->external_clone_name;
    my $de = $embl->newDE;
    my $in_progress = 'SEQUENCING IN PROGRESS';
    if ($pdmp->is_cancelled) {
        $in_progress = 'SEQUENCING CANCELLED';
    }
    $de->list("$species DNA sequence *** $in_progress *** from clone $ext_clone");
    $embl->newXX;
}

{
    my $number_Ns = 100;
    my $padding_Ns = 'n'  x $number_Ns;
    my $padding_Zeroes = "\0" x $number_Ns;

    sub embl_sequence_and_contig_map {
        my( $pdmp ) = @_;

        # Make the sequence
        my $dna          = "";
        my $base_quality = "";
        my $pos = 0;

        my @contig_map; # [contig name, start pos, end pos]
        foreach my $contig ($pdmp->contig_list) {
            my $con  = $pdmp->DNA        ($contig);
            my $qual = $pdmp->BaseQuality($contig);

	    my $contig_length = length($$con);

            # Add padding if we're not at the start
            if ($dna) {
	        $dna          .= $padding_Ns;
                $base_quality .= $padding_Zeroes if $qual;
	        $pos          += $number_Ns;
	    }

            # Append dna and quality
            $dna          .= $$con;
            $base_quality .= $$qual if $qual;

            # Record coordinates
	    my $contig_start = $pos + 1;
	    $pos += $contig_length;
	    my $contig_end = $pos;
	    push(@contig_map, [$contig, $contig_start, $contig_end]);
        }

        return( $dna, $base_quality, \@contig_map );
    }
}

sub make_fragment_summary {
    my( $pdmp, $embl, $contig_map ) = @_;

    my( @list );
    for (my $i = 0; $i < @$contig_map; $i++) {
        my ($contig, $start, $end) = @{$contig_map->[$i]};
        my $frag = sprintf("* %8d %8d contig of %d bp in length",
            $start, $end, $end - $start + 1);
        if ($pdmp->can('contig_chain') and my $group = $pdmp->contig_chain($contig)) {
            $frag .= "; fragment_chain $group";
        }
        push(@list, $frag);
    }
    return @list;
}



sub add_FT_entries {
    my( $pdmp, $embl, $contig_map ) = @_;

    my %embl_end = (
        Left  => 'SP6',
        Right => 'T7',
    );

    for (my $i = 0; $i < @$contig_map; $i++) {
	my ($contig, $start, $end) = @{$contig_map->[$i]};
	my $fragment = $embl->newFT;
	$fragment->key('misc_feature');
	my $loc = $fragment->newLocation;
	$loc->exons([$start, $end]);
	$loc->strand('W');
	$fragment->addQualifierStrings('note', "assembly_fragment:$contig");

        # Add note if this is part of a group ordered by read-pairs
        if ($pdmp->can('contig_chain') and my $group = $pdmp->contig_chain($contig)) {
            $fragment->addQualifierStrings('note', "fragment_chain:$group");
        }

        # Mark the left and right end contigs
        if ($pdmp->can('vector_ends') and my $vec_end = $pdmp->vector_ends($contig)) {
            foreach my $end ('Left', 'Right') {
                if (my $side = $vec_end->{$end}) {
                    $fragment->addQualifierStrings('note', "clone_end:$embl_end{$end}");
                    $fragment->addQualifierStrings('note', "vector_side:$side");
                }
            }
        }
    }
}






{
    my %ext_institute_remark = (
        WIBR =>  ['Draft Sequence Produced by Whitehead Institute/MIT',
                  'Center for Genome Research, 320 Charles Street,',
                  'Cambridge, MA 02141, USA',
                  'http://www-seq.wi.mit.edu'],
        WUGSC => ['Draft Sequence Produced by Genome Sequencing Center,',
                  'Washington University School of Medicine, 4444 Forest',
                  'Park Parkway, St. Louis, MO 63108, USA',
                  'http://genome.wustl.edu/gsc/index.shtml'],
        GTC =>   ['Draft Sequence Produced by Genome Therapeutics Corp,',
                  '100 Beaver Street, Waltham, MA 02453, USA',
                  'http://www.genomecorp.com'],
        );

    sub add_external_draft_CC {
        my( $pdmp, $embl ) = @_;
        
        # Special comment for sequences where the draft
        # was produced externally
        if (my $inst = $pdmp->draft_institute) {
            if (my $remark = $ext_institute_remark{$inst}) {
                $embl->newCC->list(@$remark);
                $embl->newXX;
            } else {
                confess "No remark for institute '$inst'";
            }
        }
        
        if ($pdmp->species eq 'Mouse') {
            $embl->newCC->list(
                'Sequence from the Mouse Genome Sequencing Consortium whole genome shotgun',
                'may have been used to confirm this sequence.  Sequence data from the whole',
                'genome shotgun alone has only been used where it has a phred quality of at',
                'least 30.',
            );
            $embl->newXX;
        }
    }
}

{
    my %sequencing_center = (
        5  => ['Center: Wellcome Trust Sanger Institute',
               'Center code: SC',
               'Web site: http://www.sanger.ac.uk',
               'Contact: humquery@sanger.ac.uk',],
        57 => ['Center: UK Medical Research Council',
               'Center code: UK-MRC',
               'Web site: http://mrcseq.har.mrc.ac.uk',
               'Contact: mouseq@har.mrc.ac.uk',],
        );

    # So that the UK-MRC funded sequences end up in the correct
    # bin at http://ray.nlm.nih.gov/genome/cloneserver/
    sub seq_center_lines {
        my( $pdmp ) = @_;
        
        my( $genome_center_lines );
        foreach my $num (grep defined($_), $pdmp->funded_by, $pdmp->sequenced_by, 5) {
            last if $genome_center_lines = $sequencing_center{$num};
        }
        confess "No Genome Center text found" unless $genome_center_lines;
        
        my @seq_center = (
            '-------------- Genome Center',
            @$genome_center_lines,
            );
        
        if ($pdmp->species eq 'Zebrafish') {
            $seq_center[4] =~ s/humquery/zfish-help/;
        }
        
        return @seq_center;
    }
}

sub add_Headers {
    my( $pdmp, $embl, $contig_map ) = @_;

    $pdmp->add_external_draft_CC($embl);

    my $project = $pdmp->project_name;

    my $draft_or_unfinished = is_shotgun_complete($project)
        ? 'working draft'
        : 'unfinished';

    my @comment_lines = (
        $pdmp->seq_center_lines,
        '-------------- Project Information',
        "Center project name: $project",
        '-------------- Summary Statistics',
        'Assembly program: XGAP4; version 4.5',
        $pdmp->make_read_comments(),
        $pdmp->make_consensus_quality_summary(),
        $pdmp->make_consensus_length_report(),
        $pdmp->make_q20_depth_report(),
        '--------------',
        "* NOTE: This is a '$draft_or_unfinished' sequence. It currently",
        "* consists of ". scalar(@$contig_map) ." contigs. The true order of the pieces is",
        "* not known and their order in this sequence record is",
        "* arbitrary.  Where the contigs adjacent to the vector can",
        "* be identified, they are labelled with 'clone_end' in the",
        "* feature table.  Some order and orientation information",
        "* can tentatively be deduced from paired sequencing reads",
        "* which have been identified to span the gap between two",
        "* contigs.  These are labelled as part of the same",
        "* 'fragment_chain', and the order and relative orientation",
        "* of the pieces within a fragment_chain is reflected in",
        "* this file.  Gaps between the contigs are represented as",
        "* runs of N, but the exact sizes of the gaps are unknown.",
    );

    if ($pdmp->is_cancelled) {
        push(@comment_lines,
            "* ",
            "* The sequencing of this clone has been cancelled. The most",
            "* likely reason for this is that its sequence is redundant,",
            "* and therefore not needed to complete the finished genome.",
            "* ",
            );
    } else {
        push(@comment_lines,
            "* This record will be updated with the finished sequence as",
            "* soon as it is available and the accession number will be",
            "* preserved.",
            );
    }

    $embl->newCC->list(
        @comment_lines,
        $pdmp->make_fragment_summary($embl, $contig_map),
    );   
}


=pod         

  NOTE: This is a 'working draft' sequence. It currently
  consists of 10 contigs.  The true order of the pieces is
  not known and their order in this sequence record is
  arbitrary.  Where the contigs adjacent to the vector can
  be identified, they are labelled with 'clone_end' in the
  feature table.  Some order and orientation information
  can tentatively be deduced from paired sequencing reads
  which have been identified to span the gap between two
  contigs.  These are labelled as part of the same
  'fragment_chain', and the order and relative orientation
  of the pieces within a fragment_chain is reflected in
  this file.  Gaps between the contigs are represented as
  runs of N, but the exact sizes of the gaps are unknown.
  This record will be updated with the finished sequence as
  soon as it is available and the accession number will be
  preserved.

=cut

        
        # CC   -------------- Genome Center
        # CC   Center: Whitehead Institute/ MIT Center for Genome Research
        # CC   Center code: WIBR
        # CC   Web site: http://www-seq.wi.mit.edu
        # CC   Contact: sequence_submissions@genome.wi.mit.edu
        # CC   -------------- Project Information
        # CC   Center project name: L651
        # CC   Center clone name: 82_A_1
        # CC   -------------- Summary Statistics
        # CC   Sequencing vector: M13; M77815; 100% of reads
        # CC   Chemistry: Dye-primer-amersham; 44% of reads
        # CC   Chemistry: Dye-terminator Big Dye; 56% of reads
        # CC   Assembly program: Phrap; version 0.960731
        # CC   Consensus quality: 166043 bases at least Q40
        # CC   Consensus quality: 166573 bases at least Q30
        # CC   Consensus quality: 166744 bases at least Q20
        # CC   Insert size: 168000; agarose-fp
        # CC   Insert size: 166889; sum-of-contigs
        # CC   Quality coverage: 8.9 in Q20 bases; agarose-fp
        # CC   Quality coverage: 8.9 in Q20 bases.
        # CC   * NOTE: This is a 'working draft' sequence. It currently
        # CC   * consists of 5 contigs. The true order of the pieces
        # CC   * is not known and their order in this sequence record is
        # CC   * arbitrary. Gaps between the contigs are represented as
        # CC   * runs of N, but the exact sizes of the gaps are unknown.
        # CC   * This record will be updated with the finished sequence
        # CC   * as soon as it is available and the accession number will
        # CC   * be preserved.
        # CC   *        1     9545: contig of 9545 bp in length
        # CC   *     9546 9645: gap of      100 bp
        # CC   *     9646    20744: contig of 11099 bp in length
        # CC   *    20745 20844: gap of      100 bp

sub add_Keywords {
    my( $pdmp, $embl, $contig_count ) = @_;
    
    my $kw = $embl->newKW;
    my @kw_list = ('HTG');

    if ($contig_count == 1) {
        push(@kw_list, 'HTGS_PHASE2');
    } else {
        push(@kw_list, 'HTGS_PHASE1');
    }

    if ($pdmp->is_cancelled) {
        push( @kw_list, 'HTGS_CANCELLED' );
    } else {
        if ($pdmp->is_htgs_draft) {
            # Check that the project really is draft quality
            my ($contig_depth) = $pdmp->contig_and_agarose_depth_estimate;

            if ($contig_depth >= 3) {
                push( @kw_list, 'HTGS_DRAFT' );
            }
        }
    
        # New finishing keywords
        if ($pdmp->is_htgs_fulltop) {
            push( @kw_list, 'HTGS_FULLTOP' );
        }
        if ($pdmp->is_htgs_activefin) {
            push( @kw_list, 'HTGS_ACTIVEFIN' );
        }
    }

    $kw->list(@kw_list);
    $embl->newXX;
}

sub send_warning_email {
    my($subject, $project, @report) = @_;
    
    local *WARN_MAIL;
    open WARN_MAIL, "| mailx -s '$subject Project=$project' jgrg"
        or confess "Can't open pipe to mailx : $!";
    print WARN_MAIL map "$_\n", @report;
    close WARN_MAIL or confess "Error sending warning email : $!";
}

sub make_read_comments {
    my ($pdmp) = @_;
    
    my @comments;

    my $vec_total = 0;
    $pdmp->{'_vector_count'} ||= {};
    while (my ($seq_vec, $count) = each %{$pdmp->{'_vector_count'}}) {
	$vec_total += $count;
    }
    unless ($vec_total) { $vec_total++; }

    while (my ($seq_vec, $count) = each %{$pdmp->{'_vector_count'}}) {
	my $percent = $count * 100 / $vec_total;
	push(@comments,
	     sprintf("Sequencing vector: %s %d%% of reads",
		     $seq_vec, $percent));
	
    }
    my $chem_total = 0;
    $pdmp->{'_chem_count'} ||= {};
    while (my ($chem, $count) = each %{$pdmp->{'_chem_count'}}) {
	$chem_total += $count;
    }
    unless ($chem_total) { $chem_total++; }

    while (my ($chem, $count) = each %{$pdmp->{'_chem_count'}}) {
	my $percent = $count * 100 / $chem_total;
	push(@comments,
	     sprintf("Chemistry: %s; %d%% of reads", $chem, $percent));
    }

    return @comments;
}

sub make_consensus_quality_summary {
    my ($pdmp) = @_;

    my @qual_hist;

    foreach my $contig ($pdmp->contig_list) {
	my $qual = $pdmp->BaseQuality($contig);

        my $length = length($$qual);

        my @values = unpack("C$length", $$qual);
        
        my $v_len = @values;
        
        die "Wrong number of elements ($v_len) for string of length $length"
            unless $v_len == $length;

	foreach my $q (@values) {
	    $qual_hist[$q]++;
	}
    }

    my $total = 0;
    for (my $q = $#qual_hist; $q >= 0; $q--) {
	$total += $qual_hist[$q] || 0;
	$qual_hist[$q] = $total;
    }

    return ("Consensus quality: $qual_hist[40] bases at least Q40",
	    "Consensus quality: $qual_hist[30] bases at least Q30",
	    "Consensus quality: $qual_hist[20] bases at least Q20");
}

sub make_consensus_length_report {
    my ($pdmp) = @_;

    my @report;
    my $len = 0;

    foreach my $contig ($pdmp->contig_list) {
	$len += $pdmp->contig_length($contig);
    }

    push(@report, "Insert size: $len; sum-of-contigs");

    if (my $ag_len = $pdmp->agarose_length()) {
	if (my $ag_err = $pdmp->agarose_error()) {
	    push(@report,
		 sprintf("Insert size: %d; %.1f%% error; agarose-fp",
			 $ag_len,
			 $ag_err * 100 / $ag_len));
	} else {
	    push(@report,
		 sprintf("Insert size: %d; agarose-fp", $ag_len));
	}
    }

    return @report;
}

sub make_q20_depth_report {
    my( $pdmp ) = @_;

    my @contig_agarose = $pdmp->contig_and_agarose_depth_estimate
        or confess "No depth estimate";

    my @report;
    push(@report,
        sprintf("Quality coverage: %.2fx in Q20 bases; sum-of-contigs",
        $contig_agarose[0]));

    if ($contig_agarose[1]) {
        push(@report,
            sprintf("Quality coverage: %.2fx in Q20 bases; agarose-fp",
            $contig_agarose[1]));
    }
    return @report;
}


1;

__END__



=pod

=head1 NAME - Hum::ProjectDump::EMBL

=head1 DESCRIPTION

=head2 Author

James Gilbert email B<jgrg@sanger.ac.uk>
