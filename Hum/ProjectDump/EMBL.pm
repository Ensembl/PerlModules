
package Hum::ProjectDump::EMBL;

use strict;
use warnings;
use Carp;
use Hum::ProjectDump;
use Hum::Species;

use vars qw( @ISA );

@ISA = 'Hum::ProjectDump';

use Hum::Submission qw(
  header_supplement_code
);
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
use Hum::Species;

Hum::EMBL->import(
    'AC *' => 'Hum::EMBL::Line::AC_star',
    'ST *' => 'Hum::EMBL::Line::ST_star',
    'BQ *' => 'Hum::EMBL::Line::BQ_star',
);

sub make_embl {
    my ($pdmp) = @_;

    my $project     = $pdmp->project_name;
    my $acc         = $pdmp->accession || '';
    my @sec         = $pdmp->secondary;
    my $species     = $pdmp->species;
    my $chr         = $pdmp->chromosome;
    my $map         = $pdmp->fish_map;
    my $ext_clone   = $pdmp->external_clone_name;
    my $binomial    = $pdmp->species_binomial;
    my $dataclass   = $pdmp->EMBL_dataclass;
    my $division    = $pdmp->EMBL_division;
    my $primer_pair = $pdmp->primer_pair;

    # Get the DNA, base quality string,
    # and map of contig positions.
    my ($dna, $base_quality, $contig_map) = $pdmp->embl_sequence_and_contig_map;
    my $seqlength = length($dna);

    # New embl file object
    my $embl = Hum::EMBL->new();

    # ID line
    my $id = $embl->newID;
    $id->accession($acc);
    $id->molecule('genomic DNA');
    $id->dataclass($dataclass);
    $id->division($division);
    $id->seqlength($seqlength);
    $embl->newXX;

    # AC line
    my $ac = $embl->newAC;
    $ac->primary($acc);
    $ac->secondaries(@sec);
    $embl->newXX;

    # AC * line
    my $ac_star = $embl->newAC_star;
    $ac_star->identifier($pdmp->sanger_id);
    $embl->newXX;

    # ST * line (was HD * line)
    if ($pdmp->is_private) {

        # Hold date of half a year from now
        my $hold_date = time + (0.5 * 365 * 24 * 60 * 60);
        my $hd = $embl->newST_star;
        $hd->hold_date($hold_date);
        $embl->newXX;
    }

    # DE line
    $pdmp->add_Description($embl);

    # KW line
    $pdmp->add_Keywords($embl);

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
    my ($libraryname) = library_and_vector($project);
    add_source_FT($embl, $seqlength, $binomial, $ext_clone, $chr, $map, $libraryname, $primer_pair);

    # Feature table assembly fragments
    $pdmp->add_FT_entries($embl, $contig_map);
    
    # If present, add misc-features
    $pdmp->add_assembly_tags($embl);
    
    $embl->newXX;

    # Sequence
    $embl->newSequence->seq($dna);

    # Base Quality
    $embl->newBQ_star->quality($base_quality) if $base_quality;

    $embl->newEnd;

    return $embl;
}

sub EMBL_division {
    my ($pdmp) = @_;

    my $name    = $pdmp->species;
    my $species = Hum::Species->fetch_Species_by_name($name)
      or confess "Can't fetch species '$name'";
    return $species->division;
}

sub EMBL_dataclass {
    my ($pdmp) = @_;

    # Unfinished entries are 'HTG'
    # Finsihed entries are 'STD'
    return $pdmp->htgs_phase > 2 ? 'STD' : 'HTG';
}

sub species_binomial {
    my ($pdmp) = @_;

    unless ($pdmp->{'_species_binomial'}) {
        my $name    = $pdmp->species;
        my $species = Hum::Species->fetch_Species_by_name($name);
        $pdmp->{'_species_binomial'} = $species->binomial;
    }
    return $pdmp->{'_species_binomial'};
}

=pod

Do not put clonerequest email if library is one of:

  LIBRARYNAME                     EXTERNAL_PREFIX
  ------------------------------  ---------------
  APD                             DAAP
  CHORI-211                       CH211
  CHORI-242                       CH242
  CHORI-25                        CH25
  CHORI-29                        CH29
  CHORI-507-HSA21                 CH507
  CHORI-73                        CH73
  CHORI1073                       CH1073
  DNA-Arts BAC library MANN.1     DAMA
  DNA-Arts.org BAC library MCF.1  DAMC
  DNA-arts-BAC.1-DBB.1            DADB
  DNA-arts-BAC.1-QBL.1            DAQB
  DNA-arts-BAC.1-SSTO.1           DASS
  DanioKey                        DKEY
  DanioKey BAC_end                DKEY
  DanioKeypilot                   DKEYP
  Gorilla CHORI-255 BACs          CH255
  Graves Wallaby BAC library      GRWB
  ME_KBa Wallaby Library          MEKBa
  MtH2 Medicago truncatula BACs   MTH2
  NOD mouse library               DN
  PigE                            PigE
  RPCI-23                         RP23
  RPCI-24                         RP24
  SBAB                            XX
  SBAB bI Clones                  XX
  WUABG-WL                        WAG

=cut

sub add_Reference {
    my ($pdmp, $embl, $seqlength) = @_;

    my $author  = $pdmp->author;
    my $date    = EMBLdate();
    my $species = $pdmp->species;

    my $query_email = 'grc-help';

    # my $query_email  = 'vega'; is now obsolete
    # clonerequest@sanger.ac.uk' is now obsolete
    my $clonerequest = qq{Geneservice (http://www.geneservice.co.uk/) and BACPAC Resources (http://bacpac.chori.org/)};
    if ($species eq 'Zebrafish') {

        #            $query_email  = 'zfish-help'; # see above
        $clonerequest = "http://www.sanger.ac.uk/Projects/D_rerio/faqs.shtml#dataeight";
    }

    my $ref = $embl->newReference;
    $ref->number(1);
    $ref->positions("1-$seqlength");
    $ref->authors($author);
    $ref->locations(
        "Submitted ($date) to the EMBL/Genbank/DDBJ databases.",
        'Wellcome Trust Sanger Institute, Hinxton, Cambridgeshire, CB10 1SA, UK.',
        "E-mail enquiries: $query_email\@sanger.ac.uk",
        "Clone requests: $clonerequest",
    );

    if ($species eq 'Human' or $species eq 'Mouse' or $species eq 'Zebrafish') {
        $ref->group('Genome Reference Consortium');
    }

    $embl->newXX;

    $pdmp->add_extra_headers($embl, 'reference', $seqlength);
}

sub add_Description {
    my ($pdmp, $embl) = @_;

    my $species     = $pdmp->species;
    my $ext_clone   = $pdmp->external_clone_name;
    my $de          = $embl->newDE;
    my $in_progress = 'SEQUENCING IN PROGRESS';
    if ($pdmp->is_cancelled) {
        $in_progress = 'SEQUENCING CANCELLED';
    }
    my $clone_type;
    if ($pdmp->clone_type eq 'Genomic clone') {
        $clone_type = 'clone';
    }
    elsif ($pdmp->clone_type eq 'PCR product') {
        $clone_type = 'PCR product';
    }
    else {
        confess "Unsupported clone type: ", $pdmp->clone_type;
    }
    $de->list("$species DNA sequence *** $in_progress *** from $clone_type $ext_clone");
    $embl->newXX;
}

{
    my $number_Ns      = 100;
    my $padding_Ns     = 'n' x $number_Ns;
    my $padding_Zeroes = "\0" x $number_Ns;

    sub embl_sequence_and_contig_map {
        my ($pdmp) = @_;

        # Make the sequence
        my $dna          = "";
        my $base_quality = "";
        my $pos          = 0;

        my @contig_map;    # [contig name, start pos, end pos]
        foreach my $contig ($pdmp->contig_list) {
            my $con  = $pdmp->DNA($contig);
            my $qual = $pdmp->BaseQuality($contig);

            my $contig_length = length($$con);

            # Add padding if we're not at the start
            if ($dna) {
                $dna .= $padding_Ns;
                $base_quality .= $padding_Zeroes if $qual;
                $pos += $number_Ns;
            }

            # Append dna and quality
            $dna .= $$con;
            $base_quality .= $$qual if $qual;

            # Record coordinates
            my $contig_start = $pos + 1;
            $pos += $contig_length;
            my $contig_end = $pos;
            push(@contig_map, [ $contig, $contig_start, $contig_end ]);
        }

        return ($dna, $base_quality, \@contig_map);
    }
}

sub make_fragment_summary {
    my ($pdmp, $embl, $contig_map) = @_;

    my (@list);
    for (my $i = 0; $i < @$contig_map; $i++) {
        my ($contig, $start, $end) = @{ $contig_map->[$i] };
        my $frag = sprintf("* %8d %8d contig %6d bp long", $start, $end, $end - $start + 1);
        if ($pdmp->can('contig_chain') and my $group = $pdmp->contig_chain($contig)) {
            $frag .= "; fragment_chain $group";
        }
        push(@list, $frag);
    }
    return @list;
}

sub add_FT_entries {
    my ($pdmp, $embl, $contig_map) = @_;

    my %embl_end = (
        Left  => 'SP6',
        Right => 'T7',
    );

    for (my $i = 0; $i < @$contig_map; $i++) {
        my ($contig, $start, $end) = @{ $contig_map->[$i] };
        my $fragment = $embl->newFT;
        $fragment->key('misc_feature');
        my $loc = $fragment->newLocation;
        $loc->exons([ $start, $end ]);
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

sub add_assembly_tags {
	my ($pdmp, $embl) = @_;
	
	if($pdmp->assembly_tags) {
		foreach my $assembly_tag ($pdmp->assembly_tags) {
			my $assembly_tag_feature = $embl->newFT;
			$assembly_tag_feature->key($assembly_tag->type);
			my $loc = $assembly_tag_feature->newLocation;
			$loc->strand('W');
			$loc->exons([$assembly_tag->start,$assembly_tag->end]);
			if($assembly_tag->comment and $assembly_tag->comment !~ /^\s*$/) {
				$assembly_tag_feature->addQualifierStrings('note', $assembly_tag->comment);
			}
		}
	}
	
	return;
}

{
    my %ext_institute_remark = (
        GTC => [
            'Draft Sequence Produced by Genome Therapeutics Corp,',
            '100 Beaver Street, Waltham, MA 02453, USA',
            'http://www.genomecorp.com'
        ],
        UWGC => [
            'Draft Sequence Produced by Genome Center, University of Washington,',
            'Box 352145, Seattle, WA 98195, USA'
        ],
        WIBR => [
            'Draft Sequence Produced by Whitehead Institute/MIT',
            'Center for Genome Research, 320 Charles Street,',
            'Cambridge, MA 02141, USA',
            'http://www-seq.wi.mit.edu'
        ],
        WUGSC => [
            'Draft Sequence Produced by Genome Sequencing Center,',
            'Washington University School of Medicine, 4444 Forest',
            'Park Parkway, St. Louis, MO 63108, USA',
            'http://genome.wustl.edu/gsc/index.shtml'
        ],
        SDSTC => [
            'Draft Sequence Produced by Stanford Genome Technology Center,',
            '855 S. California Avenue, Palo Alto, CA 94304, USA',
            'http://med.stanford.edu/sgtc/'
        ],
        BCM => [
            'Draft Sequence Produced by Baylor College of Medicine,',
            'One Baylor Plaza, Houston, TX 77030, USA,',
            'http://www.bcm.edu/'
        ],
    );

    sub add_external_draft_CC {
        my ($pdmp, $embl) = @_;

        # Special comment for sequences where the draft
        # was produced externally
        if (my $inst = $pdmp->draft_institute) {
            if (my $remark = $ext_institute_remark{$inst}) {
                $embl->newXX;
                $embl->newCC->list(@$remark);
            }
            else {
                confess "No remark for institute '$inst'";
            }
        }

        # I moved this part to Finished.pm as there is a zebrafish_specific comments.
        # This should be easier to maintain organism comments all in one script

        #if ($pdmp->species eq 'Mouse') {
        #    $embl->newCC->list(
        #        'Sequence from the Mouse Genome Sequencing Consortium whole genome shotgun',
        #        'may have been used to confirm this sequence.  Sequence data from the whole',
        #        'genome shotgun alone has only been used where it has a phred quality of at',
        #        'least 30.',
        #    );
        #    $embl->newXX;
        #}
    }
}

{
    my %sequencing_center = (
        5 => [
            'Center: Wellcome Trust Sanger Institute',
            'Center code: SC',
            'Web site: http://www.sanger.ac.uk',
            'Contact: grc-help@sanger.ac.uk',
        ],
        57 => [ 'Center: UK Medical Research Council', 'Center code: UK-MRC', 'Web site: http://mrcseq.har.mrc.ac.uk', ]
        ,    # contact is removed as it became obsolete
    );

    # So that the UK-MRC funded sequences end up in the correct
    # bin at http://ray.nlm.nih.gov/genome/cloneserver/
    sub seq_center_lines {
        my ($pdmp) = @_;

        my ($genome_center_lines);
        foreach my $num (grep defined($_), $pdmp->funded_by, $pdmp->sequenced_by, 5) {
            last if $genome_center_lines = $sequencing_center{$num};
        }
        confess "No Genome Center text found" unless $genome_center_lines;

        my @seq_center = ('-------------- Genome Center', @$genome_center_lines,);

        #if ($pdmp->species eq 'Zebrafish') {
        #    $seq_center[4] =~ s/grc-help/zfish-help/;
        #}

        return @seq_center;
    }
}

sub add_Headers {
    my ($pdmp, $embl, $contig_map) = @_;

    $pdmp->add_external_draft_CC($embl);

    my $project = $pdmp->project_name;

    my $draft_or_unfinished =
      is_shotgun_complete($project)
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
        "* consists of " . scalar(@$contig_map) . " contigs. The true order of the pieces is",
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
    }
    else {
        push(@comment_lines,
            "* This record will be updated with the finished sequence as",
            "* soon as it is available and the accession number will be",
            "* preserved.",
        );
    }

    $embl->newCC->list(@comment_lines, $pdmp->make_fragment_summary($embl, $contig_map),);

    $pdmp->add_extra_headers($embl, 'comment');
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
    my ($pdmp, $embl) = @_;

    my (@kw_list);
    if ($pdmp->clone_type eq 'Genomic clone') {
        @kw_list = $pdmp->htg_keywords;
    }
    push(@kw_list, $pdmp->non_htg_keywords);

    my $kw = $embl->newKW;
    $kw->list(@kw_list);
    $embl->newXX;
}

sub htg_keywords {
    my ($pdmp) = @_;

    my @kw_list = ('HTG');

    my $phase = $pdmp->htgs_phase or confess 'htgs_phase not set';
    push(@kw_list, "HTGS_PHASE$phase");

    my $type = $pdmp->project_type;
    if ($type eq 'POOLED') {
        push(@kw_list, 'HTGS_POOLED_CLONE');
    }
    elsif ($type eq 'PROJECT_POOL') {
        push(@kw_list, 'HTGS_POOLED_MULTICLONE');
    }

    if ($pdmp->is_cancelled) {
        push(@kw_list, 'HTGS_CANCELLED');
    }
    else {
        if ($pdmp->is_htgs_draft) {

            # Check that the project really is draft quality
            my ($contig_depth) = $pdmp->contig_and_agarose_depth_estimate;

            if ($contig_depth >= 3) {
                push(@kw_list, 'HTGS_DRAFT');
            }
        }

        # New finishing keywords
        if ($pdmp->is_htgs_fulltop) {
            push(@kw_list, 'HTGS_FULLTOP');
        }
        if ($pdmp->is_htgs_activefin) {
            push(@kw_list, 'HTGS_ACTIVEFIN');
        }
        if ($pdmp->is_htgs_limited_order) {
            push(@kw_list, 'HTGS_LIMITED_ORDER');
        }
    }
    
    return @kw_list;
}

sub non_htg_keywords {
    my ($pdmp) = @_;
    
    if ($pdmp->seq_reason eq 'PCR_correction') {
        return ('PCR_CORRECTION');
    }
    elsif ($pdmp->seq_reason eq 'Gap closure') {
        return ('GAP_CLOSURE');
    }
    else {
        return;
    }
}

sub send_warning_email {
    my ($subject, $project, @report) = @_;

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
    while (my ($seq_vec, $count) = each %{ $pdmp->{'_vector_count'} }) {
        $vec_total += $count;
    }
    unless ($vec_total) { $vec_total++; }

    while (my ($seq_vec, $count) = each %{ $pdmp->{'_vector_count'} }) {
        my $percent = $count * 100 / $vec_total;
        push(@comments, sprintf("Sequencing vector: %s %d%% of reads", $seq_vec, $percent));

    }
    my $chem_total = 0;
    $pdmp->{'_chem_count'} ||= {};
    while (my ($chem, $count) = each %{ $pdmp->{'_chem_count'} }) {
        $chem_total += $count;
    }
    unless ($chem_total) { $chem_total++; }

    while (my ($chem, $count) = each %{ $pdmp->{'_chem_count'} }) {
        my $percent = $count * 100 / $chem_total;
        push(@comments, sprintf("Chemistry: %s; %d%% of reads", $chem, $percent));
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

    return (
        "Consensus quality: $qual_hist[40] bases at least Q40",
        "Consensus quality: $qual_hist[30] bases at least Q30",
        "Consensus quality: $qual_hist[20] bases at least Q20"
    );
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
            push(@report, sprintf("Insert size: %d; %.1f%% error; agarose-fp", $ag_len, $ag_err * 100 / $ag_len));
        }
        else {
            push(@report, sprintf("Insert size: %d; agarose-fp", $ag_len));
        }
    }

    return @report;
}

sub make_q20_depth_report {
    my ($pdmp) = @_;

    my @contig_agarose = $pdmp->contig_and_agarose_depth_estimate
      or confess "No depth estimate";

    my @report;
    push(@report, sprintf("Quality coverage: %.2fx in Q20 bases; sum-of-contigs", $contig_agarose[0]));

    if ($contig_agarose[1]) {
        push(@report, sprintf("Quality coverage: %.2fx in Q20 bases; agarose-fp", $contig_agarose[1]));
    }
    return @report;
}

sub add_extra_headers {
    my ($pdmp, $embl, $key, $seqlength) = @_;

    confess "No key given" unless $key;

    my @subs = header_supplement_code($key, $pdmp->sanger_id);
    for (my $i = 0; $i < @subs; $i++) {
        my $code = $subs[$i];

        # If we are adding references they need to be numbered.
        # We have always added a sequence reference, hence the
        # number of the reference is $i + 2
        # (If it isn't a reference this parameter can be ignored.)
        $code->($pdmp, $embl, $seqlength, $i + 2);
    }
}

1;

__END__



=pod

=head1 NAME - Hum::ProjectDump::EMBL

=head1 DESCRIPTION

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>

