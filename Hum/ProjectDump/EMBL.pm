
package Hum::ProjectDump::EMBL;

use strict;
use Carp;
use vars qw( @ISA );

@ISA = 'Hum::ProjectDump';

use Hum::Tracking qw( ref_from_query
                      external_clone_name
                      library_and_vector
                      is_shotgun_complete
                      );
use Hum::EmblUtils qw( add_source_FT
                       add_Organism
                       species_binomial
                       );
use Hum::EMBL (
         ID => 'Hum::EMBL::Line::ID',
         AC => 'Hum::EMBL::Line::AC',
     'AC *' => 'Hum::EMBL::Line::AC_star',
         DT => 'Hum::EMBL::Line::DT',
         DE => 'Hum::EMBL::Line::DE',
         KW => 'Hum::EMBL::Line::KW',
         OS => 'Hum::EMBL::Line::Organism',
         OC => 'Hum::EMBL::Line::Organism',
         RN => 'Hum::EMBL::Line::Reference',
         RC => 'Hum::EMBL::Line::Reference',
         RP => 'Hum::EMBL::Line::Reference',
         RX => 'Hum::EMBL::Line::Reference',
         RA => 'Hum::EMBL::Line::Reference',
         RT => 'Hum::EMBL::Line::Reference',
         RL => 'Hum::EMBL::Line::Reference',
         FH => 'Hum::EMBL::Line::FH',
         FT => 'Hum::EMBL::Line::FT',
         CC => 'Hum::EMBL::Line::CC',
         XX => 'Hum::EMBL::Line::XX',
         SQ => 'Hum::EMBL::Line::Sequence',
       '  ' => 'Hum::EMBL::Line::Sequence',
     'BQ *' => 'Hum::EMBL::Line::BQ_star',
       '//' => 'Hum::EMBL::Line::End',
    );
use Hum::EMBL::Utils qw( EMBLdate );

{
    my $number_Ns = 100;
    my $padding_Ns = 'n'  x $number_Ns;
    my $padding_Zeroes = "\0" x $number_Ns;

    sub make_embl {
        my( $pdmp ) = @_;

        my $project = $pdmp->project_name;
        my $acc     = $pdmp->accession || 'AL000000';
        my @sec     = $pdmp->secondary;
        my $embl_id = $pdmp->embl_name || 'ENTRYNAME';
        my $author  = $pdmp->author;
        my $species = $pdmp->species;
        my $chr     = $pdmp->chromosome;
        my $map     = $pdmp->fish_map;
        my( $ext_clone );
        {
            my $e = external_clone_name($project);
            $ext_clone = $e->{$project}
                or die "Can't make external clone name";
        }
        my $date = EMBLdate();
        my $binomial = species_binomial($species)
            or die "Can't get latin name for '$species'";

        # Make the sequence
        my $dna          = "";
        my $base_quality = "";
	my $pos = 0;

	my @contig_pos; # [contig name, start pos, end pos]
        foreach my $contig ($pdmp->contig_list) {
            my $con  = $pdmp->DNA        ($contig);
            my $qual = $pdmp->BaseQuality($contig);
            
	    my $contig_length = length($$con);
            
            # Add padding if we're not at the start
            if ($dna) {
		$dna          .= $padding_Ns;
                $base_quality .= $padding_Zeroes;
		$pos          += $number_Ns;
	    }
            
            # Append dna and quality
            $dna          .= $$con;
            $base_quality .= $$qual;
            
            # Record coordinates
	    my $contig_start = $pos + 1;
	    $pos += $contig_length;
	    my $contig_end = $pos;
	    push(@contig_pos, [$contig, $contig_start, $contig_end]);
        }
        my $seqlength = length($dna);

        # New embl file object
        my $embl = Hum::EMBL->new();
        
        # ID line
        my $id = $embl->newID;
        $id->entryname($embl_id);
        $id->dataclass('standard');
        $id->molecule('DNA');
        $id->division('HTG'); ### I assume this is the same for other organisms
        $id->seqlength($seqlength);
        $embl->newXX;
        
        # AC line
        my $ac = $embl->newAC;
        $ac->primary($acc);
        $ac->secondaries(@sec) if @sec;
        $embl->newXX;
        
        # AC * line
        my $ac_star = $embl->newAC_star;
        my $identifier = '_'. uc $project;
        $ac_star->identifier($identifier);
        $embl->newXX;
    
        # DE line
        my $de = $embl->newDE;
        $de->list("$species DNA sequence *** SEQUENCING IN PROGRESS *** from clone $ext_clone");
        $embl->newXX;
        
        # KW line
        my $kw = $embl->newKW;
        my @kw_list = ('HTG', 'HTGS_PHASE1');
        push( @kw_list, 'HTGS_DRAFT' ) if is_shotgun_complete($project);
        $kw->list(@kw_list);
        $embl->newXX;
    
        # Organism
        add_Organism($embl, $species);
        $embl->newXX;
        
        # Reference
        my $ref = $embl->newReference;
        $ref->number(1);
        $ref->authors($author);
        $ref->locations("Submitted ($date) to the EMBL/Genbank/DDBJ databases.",
                        'Sanger Centre, Hinxton, Cambridgeshire, CB10 1SA, UK.',
                        'E-mail enquiries: humquery@sanger.ac.uk',
                        'Clone requests: clonerequest@sanger.ac.uk');
        $embl->newXX;
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
        $embl->newCC->list(
            '-------------- Genome Center',
            'Center: Sanger Centre',
            'Center code: SC',
            'Web site: http://www.sanger.ac.uk',
            'Contact: humquery@sanger.ac.uk',
            '-------------- Project Information',
            "Center project name: $project",
            '-------------- Summary Statistics',
            'Assembly program: XGAP4; version 4.5',     # This is a lie
            $pdmp->make_read_comments(),
            $pdmp->make_consensus_quality_summary(),
            $pdmp->make_consensus_length_report(),
            $pdmp->make_q20_depth_report(),
            '--------------',
            '* NOTE: This is a \'working draft\' sequence. It currently',
            "* consists of ". scalar(@contig_pos) ." contigs. The true order of the pieces",
            '* is not known and their order in this sequence record is',
            '* arbitrary. Gaps between the contigs are represented as',
            '* runs of N, but the exact sizes of the gaps are unknown.',
            '* This record will be updated with the finished sequence',
            '* as soon as it is available and the accession number will',
            '* be preserved.',
            $pdmp->make_fragment_summary($embl, $number_Ns, @contig_pos),
        );
        
#        my $unfin_cc = $embl->newCC;
#        $unfin_cc->list(
#"IMPORTANT: This sequence is unfinished and does not necessarily
#represent the correct sequence.  Work on the sequence is in progress and
#the release of this data is based on the understanding that the sequence
#may change as work continues.  The sequence may be contaminated with
#foreign sequence from E.coli, yeast, vector, phage etc.");
#        $embl->newXX;
        
        #my $contig_cc = $embl->newCC;
        #$contig_cc->list(
        #    "Order of segments is not known; 800 n's separate segments.",
        #    map "Contig_ID: $_  Length: $contig_lengths{$_}bp", $pdmp->contig_list );
        $embl->newXX;
    
        # Feature table source feature
        my( $libraryname ) = library_and_vector( $project );
        add_source_FT( $embl, $seqlength, $binomial, $ext_clone,
                       $chr, $map, $libraryname );
        
        # Feature table assembly fragments
        {
            my %embl_end = (
                Left  => 'SP6',
                Right => 'T7',
            );
            
	    for (my $i = 0; $i < @contig_pos; $i++) {
	        my ($contig, $start, $end) = @{$contig_pos[$i]};
	        my $fragment = $embl->newFT;
	        $fragment->key('misc_feature');
	        my $loc = $fragment->newLocation;
	        $loc->exons([$start, $end]);
	        $loc->strand('W');
	        $fragment->addQualifierStrings('note', "assembly_fragment:$contig");
                
                # Add note if this is part of a group ordered by read-pairs
                if (my $group = $pdmp->contig_chain($contig)) {
                    $fragment->addQualifierStrings('note', "group:$group");
                }
                
                # Mark the left and right end contigs
                if (my $vec_end = $pdmp->vector_ends($contig)) {
                    foreach my $end ('Left', 'Right') {
                        if (my $side = $vec_end->{$end}) {
                            $fragment->addQualifierStrings('note', "clone_end:$embl_end{$end}");
                            $fragment->addQualifierStrings('note', "vector_side:$side");
                        }
                    }
                }
                
                ## Add gap features
                #unless ($i == $#contig_pos) {
                #    my $spacer = $embl->newFT;
                #    $spacer->key('misc_feature');
                #    my $loc = $spacer->newLocation;
                #$loc->exons([$end + 1, $end + $number_Ns]);
                #$loc->strand('W');
                #    $spacer->addQualifierStrings('note', 'gap of unknown length');
                #}
	    }
        }
        $embl->newXX;
    
        # Sequence
        $embl->newSequence->seq($dna);
        
        # Base Quality
        $embl->newBQ_star->quality($base_quality);
        
        $embl->newEnd;
        
        return $embl;
    }
}

sub make_fragment_summary {
    my( $pdmp, $embl, $spacer_length, @contig_pos ) = @_;
    
    my( @list );
    for (my $i = 0; $i < @contig_pos; $i++) {
        my ($contig, $start, $end) = @{$contig_pos[$i]};
        my $frag = sprintf("* %8d %8d contig of %d bp in length",
            $start, $end, $end - $start + 1);
        if (my $group = $pdmp->contig_chain($contig)) {
            $frag .= "; group $group";
        }
        push(@list, $frag);
        #unless ($i == $#contig_pos) {
        #    push(@list,
        #        sprintf("* %8d %8d gap of unknown length",
        #            $end + 1, $end + $spacer_length, $spacer_length)
        #    );
        #}
    }
    return @list;
}

sub make_read_comments {
    my ($pdmp) = @_;
    
    my @comments;

    my $vec_total = 0;
    while (my ($seq_vec, $count) = each %{$pdmp->{_vector_count}}) {
	$vec_total += $count;
    }
    unless ($vec_total) { $vec_total++; }

    while (my ($seq_vec, $count) = each %{$pdmp->{_vector_count}}) {
	my $percent = $count * 100 / $vec_total;
	push(@comments,
	     sprintf("Sequencing vector: %s %d%% of reads",
		     $seq_vec, $percent));
	
    }
    my $chem_total = 0;
    while (my ($chem, $count) = each %{$pdmp->{_chem_count}}) {
	$chem_total += $count;
    }
    unless ($chem_total) { $chem_total++; }

    while (my ($chem, $count) = each %{$pdmp->{_chem_count}}) {
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
    my ($pdmp) = @_;

    my $est_len   = 0;
    my $q20_bases = 0;

    foreach my $contig ($pdmp->contig_list) {
	$est_len += $pdmp->contig_length($contig);
	$q20_bases += $pdmp->count_q20_for_contig($contig);
    }
    unless ($est_len) { $est_len = 1; }
    my @report;
    push(@report,
	 sprintf("Quality coverage: %.2fx in Q20 bases; sum-of-contigs",
		 $q20_bases / $est_len));
    
    if (my $ag_len = $pdmp->agarose_length()) {
    push(@report,
	 sprintf("Quality coverage: %.2fx in Q20 bases; agarose-fp",
		 $q20_bases / $ag_len));
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
