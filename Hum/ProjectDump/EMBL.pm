
package Hum::ProjectDump::EMBL;

use strict;
use Carp;

use Hum::Tracking qw( ref_from_query
                      external_clone_name
                      library_and_vector
                      is_shotgun_complete
                      );
use Hum::EmblUtils qw( add_source_FT
                       add_Organism
                       species_binomial
                       );
use Hum::EMBL::Line::AC_star;
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
       '//' => 'Hum::EMBL::Line::End',
    );
use Hum::EMBL::Utils qw( EMBLdate );

BEGIN {
    my $number_Ns = 800;
    my $eight_hundred_Ns = 'n' x $number_Ns;

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
        my $dna = "";
	my %contig_lengths;
	my $pos = 0;
	my @contig_order; # [contig name, start pos, end pos]

	# $pdmp->get_contig_order();

        foreach my $contig ($pdmp->contig_list) {
            my $con = $pdmp->DNA($contig);
	    my $contig_length = length($$con);
            $contig_lengths{$contig} = $contig_length;
            if ($dna) {
		$dna .= $eight_hundred_Ns;
		$pos += $number_Ns;
	    }
	    my $contig_start = $pos + 1;
            $dna .= $$con;
	    $pos += $contig_length;
	    my $contig_end = $pos;
	    push(@contig_order, [$contig, $contig_start, $contig_end]);
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
        
        # Comments
	my $reads_cc = $embl->newCC;
	$reads_cc->list($pdmp->make_read_comments());
	$embl->newCC->list("Assembly program: XGAP4; version 4.5");
	$embl->newCC->list($pdmp->make_consensus_q_summary(),
			   $pdmp->make_consensus_length_report());
	$embl->newCC->list($pdmp->make_q20_depth_report());
	$embl->newXX;

        my $unfin_cc = $embl->newCC;
        $unfin_cc->list(
"IMPORTANT: This sequence is unfinished and does not necessarily
represent the correct sequence.  Work on the sequence is in progress and
the release of this data is based on the understanding that the sequence
may change as work continues.  The sequence may be contaminated with
foreign sequence from E.coli, yeast, vector, phage etc.");
        $embl->newXX;
        
        my $contig_cc = $embl->newCC;
        $contig_cc->list(
            "Order of segments is not known; 800 n's separate segments.",
            map "Contig_ID: $_  Length: $contig_lengths{$_}bp", $pdmp->contig_list );
        $embl->newXX;
    
        # Feature table source feature
        my( $libraryname ) = library_and_vector( $project );
        add_source_FT( $embl, $seqlength, $binomial, $ext_clone,
                       $chr, $map, $libraryname );	
	my $vec_ends = $pdmp->find_vector_ends();
	foreach my $cpos (@contig_order) {
	    my ($contig, $start, $end) = @$cpos;
	    my $fragment = $embl->newFT;
	    $fragment->key('misc_feature');
	    my $loc = $fragment->newLocation;
	    $loc->exons([$start, $end]);
	    $loc->strand('W');
	    $fragment->addQualifierStrings('note', "assembly_fragment:$contig");
	    if (exists($vec_ends->{'Left'}->{$contig})) {
		$fragment->addQualifierStrings('note', "clone_end:SP6");
		$fragment->addQualifierStrings('note', "vector_side:$vec_ends->{'Left'}->{$contig}");
	    }
	    if (exists($vec_ends->{'Right'}->{$contig})) {
		$fragment->addQualifierStrings('note', "clone_end:T7");
		$fragment->addQualifierStrings('note', "vector_side:$vec_ends->{'Right'}->{$contig}");
	    }
	}
        $embl->newXX;
    
        # Sequence
        my $sq = $embl->newSequence;
        $sq->seq($dna);
        
        $embl->newEnd;
        
        return $embl;
    }
}


1;

__END__



=pod

=head1 NAME - Hum::ProjectDump::EMBL

=head1 DESCRIPTION

=head2 Author

James Gilbert email B<jgrg@sanger.ac.uk>
