
### Hum::ProjectDump::EMBL::Finished

package Hum::ProjectDump::EMBL::Finished;

use strict;

use Carp;
use Hum::EMBL::FeatureSet;
use Hum::Tracking qw{
    library_and_vector
    prepare_track_statement
    project_from_clone
    intl_clone_name
    };
use Hum::ProjectDump::EMBL;
use Hum::EMBL::LocationUtils qw{
    simple_location
    locations_from_subsequence
    location_from_homol_block
    };
use Hum::EmblUtils qw{
    projectAndSuffix
    };
use Hum::Ace::CloneSeq;

use vars qw{ @ISA };
@ISA = qw{ Hum::ProjectDump::EMBL };


### These first subroutines override
### subroutines in Hum::ProjectDump::EMBL

=pod

=head2 EMBL Database Divisions

    Division                Code
    -----------------       ----
    ESTs                    EST
    Bacteriophage           PHG
    Fungi                   FUN
    Genome survey           GSS
    High Throughput cDNA    HTC
    High Throughput Genome  HTG
    Human                   HUM
    Invertebrates           INV
    Mus musculus            MUS
    Organelles              ORG
    Other Mammals           MAM
    Other Vertebrates       VRT
    Plants                  PLN
    Prokaryotes             PRO
    Rodents                 ROD
    STSs                    STS
    Synthetic               SYN
    Unclassified            UNC
    Viruses                 VRL

=cut

{
    my %species_division = (
        'Human'         => 'HUM',
        'Gibbon'        => 'PRI',
        'Mouse'         => 'MUS',
        'Rat'           => 'ROD',
        'Dog'           => 'MAM',

        'Fugu'          => 'VRT',
        'Zebrafish'     => 'VRT',
        'B.floridae'    => 'VRT',

        'Drosophila'    => 'INV',
        
        'Arabidopsis'   => 'PLN',
        );

    sub EMBL_division {
        my( $pdmp ) = @_;

        my $species = $pdmp->species;
        return $species_division{$species} || 'VRT';
    }
}

sub add_Description {
    my( $pdmp, $embl ) = @_;
    
    my $species   = $pdmp->species;
    my $ext_clone = $pdmp->external_clone_name;
    my $species_chr_desc = "$species DNA sequence from clone $ext_clone";
    if (my $chr = $pdmp->chromosome) {
        if ($species eq 'Zebrafish') {
            $species_chr_desc .= " in linkage group $chr";
        } else {
            $species_chr_desc .= " on chromosome $chr";
        }
    }
    if (my $map = $pdmp->fish_map) {
        $species_chr_desc .= $map;
    }
    
    my @desc = ($species_chr_desc);
    if (my $ace = $pdmp->ace_Sequence_object) {
        # Add any further DE lines
        foreach my $d ($ace->at('DB_info.EMBL_dump_info.DE_line[1]')) {
            push( @desc, "$d" );
        }
    }
    
    my $de = $embl->newDE;
    $de->list(@desc);
    $embl->newXX;
}

sub add_Keywords {
    my( $pdmp, $embl ) = @_;

    my @key_words = ('HTG');
    if (my $ace = $pdmp->ace_Sequence_object) {
        push(@key_words, map $_->name, $ace->at('DB_info.Keyword[1]'));
    }
    
    my $kw = $embl->newKW;
    $kw->list(@key_words);
    $embl->newXX;
}

sub add_Headers {
    my( $pdmp, $embl ) = @_;
    
    $pdmp->add_standard_CC($embl);
    unless ($pdmp->add_MHC_Consortium_CC($embl)) {
        $pdmp->add_chromosomal_CC($embl);
    }
    $pdmp->add_extra_CC($embl);
    $pdmp->add_library_CC($embl);
    $pdmp->add_external_draft_CC($embl);
    $pdmp->add_overlap_CC($embl);
}

sub add_FT_entries {
    my( $pdmp, $embl ) = @_;
    
    # Can't do this without an attached AcePerl sequence object
    return unless $pdmp->ace_Sequence_object;
    
    $pdmp->add_genes_FT($embl);
    $pdmp->add_GSS_STS_FT($embl);
    $pdmp->add_AssemblyTags_FT($embl);
    $pdmp->add_Repeats_FT($embl);
}

### Most of the following subs use an AcePerl object
### to get add annotation to the EMBL entry.

sub ace_Sequence_object {
    my( $self, $ace ) = @_;
    
    if ($ace) {
        $self->{'_ace_Sequence_object'} = $ace;
    }
    return $self->{'_ace_Sequence_object'};
}

sub remove_ace_Sequence_object_ref {
    my( $self, $ace ) = @_;
    
    $self->{'_ace_Sequence_object'} = undef;
}

sub add_extra_CC {
    my( $pdmp, $embl ) = @_;
    
    return unless my $ace = $pdmp->ace_Sequence_object;

    # Add any CC lines
    my( @comment );
    foreach my $c ($ace->at('DB_info.EMBL_dump_info.CC_line[1]')) {
        push( @comment, "$c" );
    }
    
    return unless @comment;
    
    my $cc = $embl->newCC;
    $cc->list( @comment );
    $embl->newXX;
}

sub add_overlap_CC {
    my( $pdmp, $embl ) = @_;
    
    return unless my $ace = $pdmp->ace_Sequence_object;
    
    my $name            = $pdmp->sequence_name;
    my $external_clone  = $pdmp->external_clone_name;
    
    my $length = $embl->ID->seqlength
        or confess "length not yet set in embl object";

    # Determine if we have the entire insert of the clone
    # in this sequence, and if not, then report any ends
    # which we do have.
    my( $cle, $cre );
    eval{ $cle = $ace->at("Structure.Clone_left_end.\Q$name\E[1]") ->name };
    eval{ $cre = $ace->at("Structure.Clone_right_end.\Q$name\E[1]")->name };

    my(@lines);
    if (($cle and $cre) and ($cle == 1 and $cre == $length)) {
        push(@lines, "This sequence is the entire insert of clone $external_clone");
    } else {
        push(@lines,
"IMPORTANT: This sequence is not the entire insert of clone $external_clone
It may be shorter because we sequence overlapping sections only once,
except for a short overlap.");
        push(@lines, "The true left end of clone $external_clone is at $cle in this sequence.") if $cle;
        push(@lines, "The true right end of clone $external_clone is at $cre in this sequence.") if $cre;
    }
    
    # List left and right ends of other clones in this sequence
    foreach my $end (qw( left right )) {
        #warn "Looking for $end\n";
        # Each clone tag which isn't the sequence we are dumping itself
        foreach my $c_tag (grep $_ ne $name, $ace->at("Structure.Clone_${end}_end[1]")) {
            warn "clone tag: $c_tag\n";
            if (my $c_pos = $c_tag->at) {
                my $ext_name = intl_clone_name($c_tag->name);
                push(@lines, "The true $end end of clone $ext_name is at $c_pos in this sequence.");
            }
        }
    }
    
    # Add sequence overlap data
    my @overlap = qw( left start right end );
    for (my $i = 0; $i < @overlap; $i += 2) {
        my( $end, $piece ) = @overlap[$i,$i+1];
        foreach my $c_tag ($ace->at("Structure.Overlap_$end".'[1]')) {
            my $cl = $c_tag->fetch;
            my $cl_name = $cl->name;
            my( $acc );
            if ($cl_name =~ s/^em://i) {
                $acc = $cl_name;
            } else {
                my( $project, $suffix ) = projectAndSuffix( $cl );
                $project ||= "$cl"; # Project may not be finished yet
                $acc = (accession_list($project, $suffix))[0];
            }
            if ($acc) {
                push(@lines, "The $piece of this sequence overlaps with sequence $acc");
            } else {
                warn "Can't get accession number for '$cl'\n";
            }
        }
    }
    
    my $cc = $embl->newCC;
    $cc->list(@lines);    
}

{
    
    # Standard comment blocks
    my @std = ( 
'During sequence assembly data is compared from overlapping clones.
Where differences are found these are annotated as variations
together with a note of the overlapping clone name. Note that the
variation annotation may not be found in the sequence submission
corresponding to the overlapping clone, as we submit sequences with
only a small overlap as described above.',

'This sequence was finished as follows unless otherwise noted: all regions
were either double-stranded or sequenced with an alternate chemistry or
covered by high quality data (i.e., phred quality >= 30); an attempt was
made to resolve all sequencing problems, such as compressions and repeats;
all regions were covered by at least one plasmid subclone or more than one
M13 subclone; and the assembly was confirmed by restriction digest, except
on the rare occasion of the clone being a YAC.',


'The following abbreviations are used to associate primary accession
numbers given in the feature table with their source databases:
Em:, EMBL; Sw:, SWISSPROT; Tr:, TREMBL; Wp:, WORMPEP;
Information on the WORMPEP database can be found at
http://www.sanger.ac.uk/Projects/C_elegans/wormpep');
    
    my @zfish_specific = (
'Clone-derived Zebrafish pUC subclones occasionally display inconsistency
over the length of mononucleotide A/T runs and conserved TA repeats. 
Where this is found the longest good quality representation will be 
submitted.',

'Repeat names beginning "Dr" were identified by the Recon repeat discovery
system (Zhirong Bao and Sean Eddy, submitted), and those beginning "drr"
were identified by Rick Waterman (Stephen Johnson lab, WashU).  For
further information see
http://www.sanger.ac.uk/Projects/D_rerio/fishmask.shtml');

    sub add_standard_CC {
        my( $pdmp, $embl ) = @_;

        # STD sequencing centre comment for Greg Schuler
        # (see: http://ray.nlm.nih.gov/genome/cloneserver/)
        my $seq_cen = $embl->newCC;
        $seq_cen->list($pdmp->seq_center_lines, '--------------');
        $embl->newXX;

        # Add the standard headers
        foreach my $t (@std) {
            my $cc = $embl->newCC;
            $cc->list($t);
            $embl->newXX;
        }
        
        if ($pdmp->species eq 'Zebrafish') {
            foreach my $entry (@zfish_specific) {
                my $cc = $embl->newCC;
                $cc->list($entry);
                $embl->newXX;
            }
        }
    }
}

{
    my %mhc_prefix = map {$_, 1} qw{ bPG bCX bAZ bQB bMC bSS bMA bAP };

    sub add_MHC_Consortium_CC {
        my( $pdmp, $embl ) = @_;
        
        my ($tlp) = $pdmp->sequence_name =~ /^(...)/;
        if ($mhc_prefix{$tlp}) {
            my $t = 
"This sequence was generated from part of bacterial clone contigs
constructed by the MHC Haplotype Consortium and collaborators.
Further information can be found at
http://www.sanger.ac.uk/HGP/Chr6/MHC";

            my $cc = $embl->newCC;
            $cc->list($t);
            $embl->newXX;
        } else {
            return 0;
        }
    }
}

{
    # List of human chromosomes which have Sanger HGP pages
    my %www        = map {$_, 1} qw(1 6 9 10 13 20 22 X);

    sub add_chromosomal_CC {
        my( $pdmp, $embl ) = @_;

        my $species = $pdmp->species;
        my $chr     = $pdmp->chromosome;

        return unless $species eq 'Human';
        return unless $www{$chr};

        my $t = 
"This sequence was generated from part of bacterial clone contigs of
human chromosome $chr, constructed by the Sanger Centre Chromosome $chr
Mapping Group.  Further information can be found at
http://www.sanger.ac.uk/HGP/Chr$chr";

        my $cc = $embl->newCC;
        $cc->list($t);
        $embl->newXX;
    }
}

{

    my( $sth, %lib_comments );

    $lib_comments{'CITF22'} =
"is from the human chromosome 22-specific Fosmid library
described in Kim U-J. et al Genet_Anal 12(2): 81-84, and is part of a
cosmid contig isolated using YACs and markers from the Sanger Centre
chromosome 22 YAC contig described in Collins, J.E. et al Nature 377
Suppl., 367-379.";

    foreach (qw( CIT978SK-A1 CIT978SK-A2 CIT978SK-B )) {
        $lib_comments{$_} =
"is from the human BAC library described in U-J. Kim et al.
(1996) Genomics 34, 213-218.";
    }

    foreach (qw( CIT-HSP-D1 CIT-HSP-D2 )) {
        $lib_comments{$_} =
"is from the CalTech genomic sperm BAC library D.";
    }

        $lib_comments{'CIT-HSP-C'} =
"is from the CalTech genomic sperm BAC library C.";

    $lib_comments{'Genome_Systems_ReleaseI'} =
"is from the library Genome_Systems_ReleaseI";

    $lib_comments{'LA16'} =
"is part of a clone contig from the tip of the short arm of
chromosome 16 spanning 2Mb of p13.3 (Higgs D.R., Flint J., Daniels R.,
MRC Molecular Haematology Unit, Institute of Molecular Medicine,
Oxford (unpublished)), and is from the Los Alamos, flow sorted human
Chromosome 16 libraries constructed by Norman Doggett (unpublished).";

    $lib_comments{'SCb'} =
"is from the Research Genetics total human BAC library
that was screened by D. Ruddy and A. Gnirke from Mercator
Genetics Inc. as published in Lauer et al (1997) Gen Res. 7: 457-470.";

    $lib_comments{'SC22cB'} =
"is from the human chromosome 22-specific cosmid library
(SC22cB) constructed at the Sanger Centre by Mark Ross and Cordelia
Langford.";

    $lib_comments{'SCcI'} =
"is from the ICRF flow-sorted human chromosome 6 cosmid library
(cell line RPETO1)";

    $lib_comments{'SCcV'} =
"is from a whole genomic cosmid library (Holland et al.,
Genomics 15: 297)";

$lib_comments{'SCLUCA'} =
"is part of a clone contig from chromosome 3p21.3 described
in Ming-Hui Wei et al., Cancer Research 56, 1487-1492, 1996, and is
from a Stratagene male, caucasian, placental cosmid library.";

    foreach (qw( LL22NC01 LL22NC03 )) {
        $lib_comments{$_} =
"is from the human chromosome 22-specific cosmid library
$_, constructed at the Biomedical Sciences Division, Lawrence
Livermore National Laboratory, Livermore, CA 94550 under the auspices
of the National Laboratory Gene Library Project sponsored by the US
Department of Energy.  The source of the flow sorted chromosomes was a
human/hamster hybrid containing chromosomes Y, 22 and 9.";
    }

    $lib_comments{'LL0XNC01'} =
"is from the Lawrence Livermore National Laboratory flow-sorted
X chromosome cosmid library LL0XNC01";

    foreach (qw( RPCI-1 RPCI-3 RPCI-4 RPCI-5 RPCI-6
                 RPCI-11.1 RPCI-11.2 RPCI-11.3 RPCI-11.4
                 RPCI-13.1 RPCI-13.2 RPCI-13.3 RPCI-13.4 )) {
        $lib_comments{$_} =
"is from the library $_ constructed by the group of 
Pieter de Jong. For further details see 
http://www.chori.org/bacpac/home.htm"
    }

    # RPCI-21 is PAC
    $lib_comments{'RPCI-21'} =
"is from the RPCI-21 Mouse PAC Library
constructed by the group of Pieter de Jong.
For further details see http://www.chori.org/bacpac/home.htm";

    # ... but RPCI-22 and 23 are BAC
    foreach (qw( RPCI-22 RPCI-23 )) {
        $lib_comments{$_} =
"is from the $_ Mouse BAC Library
constructed by the group of Pieter de Jong.
For further details see http://www.chori.org/bacpac/home.htm"
    }

    $lib_comments{'CITB-CJ7-B'} =
"is from the Research Genetics 129 mouse BAC library (CITB-CJ7-B).";

    sub add_library_CC {
        my( $pdmp, $embl ) = @_;
        
        my $project = $pdmp->project_name;
        my ($lib, $vector, $des) = library_and_vector($project);
        
        return unless $lib;
        
        my $comment = $lib_comments{$lib};
        unless ($comment) {
            if ($des and $des =~ /\S/) {
                if ($des =~ /library\s*(.*)/i) {
                    if ($1) {
                        $comment = "is from the $des";
                    } else {
                        $comment = "is from a $des";
                    }
                } else {
                    $comment = "is from a $des library";
                }
            } else {
                die "No comment found for '$lib'";
            }
        }
        
        my $clone = $pdmp->external_clone_name;
        my @list = ("$clone $comment");
        push(@list, "VECTOR: $vector") if $vector;
        
        my $cc = $embl->newCC;
        $cc->list(@list);
        $embl->newXX;
    }
}

sub add_genes_FT {
    my( $pdmp, $embl ) = @_;
    
    my $ace = $pdmp->ace_Sequence_object;
    my $set = 'Hum::EMBL::FeatureSet'->new;
    
    ### Should replace all current code with
    ### code that uses Hum::Ace objects.
    my $clone = Hum::Ace::CloneSeq
        ->new_from_name_and_db_handle($ace->name, $ace->db);
    foreach my $sub ($clone->get_all_SubSeqs) {
        $pdmp->add_SubSeq_PolyA_to_Set($set, $sub);
    }
        
    # Load up the genes hash
    my( %genes );
    
    # We use SI prefix for Zebrafish genes
    my $prefix = $pdmp->species eq 'Zebrafish' ? 'SI:' : '';
    
    my $clone_name = $ace->name;
    foreach my $g ($ace->at('Structure.Subsequence[1]')) {
        my $nam = $clone_name;
        
        # Allow for sloppy capitalization of sequence name
        $nam =~ s{^([A-Za-z])}{ my $f = $1; '['. lc($f) . uc($f) .']' }e;
        
        if ($g =~ /^$nam\.(\d+)(?:\.(\d+))?(\.mRNA)?/) {
            my $num = $1;       # The gene number
            my $iso = $2 || 0;  # The isoform number -- zero if no isoforms
            my $key = $3 ? 'mRNA' : 'CDS';
            $genes{$num}->[$iso]{$key} = $g;
        }
    }
    
    
    # Rules for remarks:
    # The remark for the /product qualifier comes from CDS
    # object, or the corresponding CDS isoform, if there
    # are isoforms.
    # If there are no CDS objects, then the remark for the
    # /product qualfier comes from each mRNA itself.
    foreach my $n (sort {$a <=> $b} keys %genes) {
        my( $locusname );
        my $trans = $genes{$n};
        my $pseudo = 0;
        for (my $i = 0; $i < @$trans; $i++) {
            my $iso = $trans->[$i] or next;
            
            # Make the name of the product
            my $product_name = "$prefix$ace.$n";
            $product_name .= ".$i" if $i;
            
            my( $cds_loc, $mrna_loc );
            foreach my $sub_tag (values %$iso) {
                # Get Hum::EMBL::Location objects for CDS and mRNA
                my @locs = locations_from_subsequence($sub_tag);
                if ($locs[0]) {
                    if ($mrna_loc) {
                        die "Processing '$sub_tag' : already have a mRNA"
                    } else {                        
                        $mrna_loc = $locs[0];
                    }
                }
                if ($locs[1]) {
                    if ($cds_loc) {
                        die "Processing '$sub_tag' : already have a CDS"
                    } else {                        
                        $cds_loc = $locs[1];
                    }
                }
                
            }
            
            foreach my $v ('CDS', 'mRNA') {
                my $key = $v;
                my $sub_tag = $iso->{$key};
                
                # If we don't have a subsequence tag for mRNA, but
                # it is a new-style combined object (because we
                # have an mRNA Location object), then we use the CDS
                # location tag.
                my $is_combined = 0;
                if (! $sub_tag and $key eq 'mRNA' and $mrna_loc) {
                    $sub_tag = $iso->{'CDS'};
                    $is_combined = 1;
                }

                my( $loc );
                if ($key eq 'CDS') {
                    $loc =  $cds_loc or next;
                } else {
                    $loc = $mrna_loc or next;
                }
                
                # Shouldn't get here without a Subsequence
                die "No $key Subsequence for product '$product_name'"
                    unless $sub_tag;

                # Fetch the object from the database
                my $g = $sub_tag->fetch;
                my $method = $g->at('Method[1]');
                $method = $method ? $method->name : '';

                if ($method eq 'Transposon') {
                    $key = 'transposon';
                }

                # Create a feature
                my $ft = $set->newFeature;
                $ft->key($key);
                $ft->location($loc);

                # Get the locus name
                my( $locus );
                eval{ $locus = $g->at('Visible.Locus[1]')->name };
                die "No locus defined in '$g'" unless $locus;
                if (defined $locusname) {
                    die "Locus '$locus' from '$g' doesn't match '$locusname' from same gene"
                        unless $locus eq $locusname;
                } else {
                    $locusname = $locus;
                }
                
                unless ($method eq 'Transposon') {
                    if ($clone_name eq substr($locusname, 0, length($clone_name))) {
                        $ft->addQualifierStrings('gene', "$prefix$locusname");
                    } else {
                        $ft->addQualifierStrings('gene', $locusname);
                    }
                }

                # Add /product qualifier, and any further remarks
                {
                    my( $product, @remarks );
                    my $r;  # First remark line to take
                    if ($product = $trans->[0]{'product'} || $iso->{'product'}) {
                        $r = 0; # /product is from another object, so
                                # we take all $iso's remarks
                        
                        # ... unless it is a combined mRNA/CDS object
                        if ($is_combined) {
                            $r = 1;
                        }
                    } else {
                        $product = $pdmp->make_product_qualifier($g, $product_name, \$pseudo);
                        $iso->{'product'} = $product;
                        $r = 1; # /product is from $iso, so we skip the
                                # first remark field
                    }
                    $ft->addQualifierStrings('pseudo') if $pseudo;
                    $ft->addQualifier($product);

                    # Get just the remarks we need
                    @remarks = get_visible_remarks($g);
                    foreach my $remark (@remarks[$r..$#remarks]) {
                        $ft->addQualifierStrings('note', "$remark");
                    }
                }

                # Add supporting evidence - database matches
                $pdmp->addSupportingEvidence( $g, $ft, $cds_loc && $mrna_loc );

                # Is it supported by experimental evidence?
                if ($method =~ /^GD_/) {
                    # Gene_ID genes have method GD_mRNA or GD_CDS
                    $ft->addQualifierStrings('evidence','EXPERIMENTAL');
                } else {
                    $ft->addQualifierStrings('evidence','NOT_EXPERIMENTAL');
                }
            }
        }
    }
    
    # Get polyA sites
    $pdmp->addPolyA_toSet($set);
    
    # Get CpG islands
    $pdmp->addCpG_toSet($set);
    
    # Add the genes and other features into the entry
    $set->sortByPosition;
    $set->removeDuplicateFeatures;
    $set->addToEntry($embl);
}


sub make_product_qualifier {
    my( $pdmp, $g, $name, $pseudo ) = @_;
    
    my ($remark) = get_visible_remarks($g);
    
    if ($remark) {        
        my( $prod_qual );
        if ($g->at('Properties.Pseudogene')) {
            # EMBL don't allow the /product qualifier for pseudogenes
            $$pseudo = 1;   # Set pseudo flag in caller
            $prod_qual = 'note';
        } else {
            $prod_qual = 'product';
        }
	my $description = "$name ($remark)";
        my $product = 'Hum::EMBL::Qualifier'->new;
        $product->name($prod_qual);
        $product->value($description);
        
        return $product;
    } else {
        die "No description under Visible.Remark for '$name'\n";
    }
    
}

sub get_visible_remarks {
    my( $g ) = @_;
    
    my @rem = map $_->name, $g->at('Visible.Remark[1]');
    foreach my $r (@rem) {
        if (! $r and $r eq "") {
            my $name = $g->name;
            die "Error: Invisible empty string under Visible.Remark in Sequence '$name'\n",
              "This can be fixed by parsing in the following:\n\n",
              qq{Sequence "$name"\n},
              qq{-D Remark ""\n\n},;
        }
    }
    return @rem;
}

BEGIN {

    # For adding supporting evidence to a feature
    my @Seq_Matches = (
                       ['cDNA_match',    'match: cDNAs:'      , 'mRNA' ],
                       ['EST_match',     'match: ESTs:'       , 'mRNA' ],
                       ['Protein_match', 'match: proteins:'   , 'CDS'  ],
                       ['Genomic_match', 'match: genomic DNA:', 'mRNA' ],
                       );
    
    sub addSupportingEvidence {
        my( $pdmp, $seq, $ft, $filter_flag ) = @_;

        # $key is CDS or mRNA
        my $key = $ft->key;

        foreach my $m (@Seq_Matches) {
            my ($m_type, $m_text, $m_key) = @$m;
        
            # We confine certain types of matches to CDS
            # or mRNA if we are making both
            if ($filter_flag) {
                next unless $m_key eq $key,
            }
        
            if (my @matches = $seq->at("Annotation.Sequence_matches.$m_type".'[1]')) {
                # May not have any valid matches left after fixing names!
                if (@matches = $pdmp->fixNames(@matches)) {
                    $ft->addQualifierStrings('note', "$m_text @matches");
                }
            }
        }
    }
}

# New way to get PolyA
sub add_SubSeq_PolyA_to_Set {
    my( $pdmp, $set, $sub ) = @_;
    
    my $strand = $sub->strand;
    foreach my $poly ($sub->get_all_PolyA) {
        my $site = $set->newFeature;
        $site->key('polyA_site');
        my $site_loc = Hum::EMBL::Location->new;
        $site_loc->exons($poly->site_position);
        if ($strand == 1) {
            $site_loc->strand('W');
        } else {
            $site_loc->strand('C');
        }
        $site->location($site_loc);
        
        my $sig = $set->newFeature;
        $sig->key('polyA_signal');
        my $sig_loc = Hum::EMBL::Location->new;
        my $sig_start = $poly->signal_position;
        my $sig_end = $sig_start + ($strand * 5);
        $sig->location(simple_location($sig_start, $sig_end));
    }
}

sub addPolyA_toSet {
    my( $pdmp, $set ) = @_;
    
    my $ace = $pdmp->ace_Sequence_object;
    
    foreach my $sig ($ace->at('Feature.polyA_signal[1]')) {
        my($x, $y) =  map $_->name, $sig->row;
        confess "Bad polyA_signal coordinates ('$x','$y')"
            unless $x and $y;
        my $ft = $set->newFeature;
        $ft->key('polyA_signal');
        $ft->location(simple_location($x, $y));
    }
    
    # The two numbers for the polyA_site are the last
    # two bases of the mRNA in the genomic sequence
    # (Laurens' counterintuitive idea.)
    foreach my $site ($ace->at('Feature.polyA_site[1]')) {
        my($x, $y) = map $_->name, $site->row;
        confess "Bad polyA_site coordinates ('$x','$y')"
            unless $x and $y;
        my $ft = $set->newFeature;
        $ft->key('polyA_site');
        my $loc = Hum::EMBL::Location->new;
        if ($x < $y) {
            $loc->exons($y);
            $loc->strand('W');
        }
        elsif ($x > $y) {
            $loc->exons($y);
            $loc->strand('C');
        }
        else {
            confess "Illegal polyA_site position ($x,$y)";
        }
        $ft->location($loc);
    }

}

sub addCpG_toSet {
    my( $pdmp, $set ) = @_;
    
    my $ace = $pdmp->ace_Sequence_object;
    
    foreach my $cpg ($ace->at('Feature.Predicted_CpG_island[1]')) {
        my( $x, $y ) = map $_->name, $cpg->row();
        my $ft = $set->newFeature;
        $ft->key('misc_feature');
        $ft->location( simple_location($x, $y) );
        $ft->addQualifierStrings('note', 'CpG island');
        $ft->addQualifierStrings('evidence','NOT_EXPERIMENTAL');
    }
}


sub add_GSS_STS_FT {
    my( $pdmp, $embl ) = @_;
    
    my $ace = $pdmp->ace_Sequence_object;
    
    my $set = Hum::EMBL::FeatureSet->new;
    
    # Add GSS matches
    $pdmp->addHomolFeatures_toSet($set, 70, 'GSS', 
        ['GSS_homol'],
        ['GSS_blastn', 'GSS_eg']);
    
    # Add STS matches
    $pdmp->addHomolFeatures_toSet($set, 70, 'STS',
        ['STS_homol', 'Sanger_STS_homol'],
        ['STS_blastn', 'STS_eg', 'sanger_sts_eg']);
    
    # Add the features into the entry
    $set->sortByPosition;
    $set->mergeFeatures;
    $set->addToEntry($embl);
}

sub addHomolFeatures_toSet {
    my( $pdmp, $set, $score, $type, $matches, $homol_tags ) = @_;
    
    my $ace = $pdmp->ace_Sequence_object;
    
    # %locstore stores location objects, keyed on strings
    # which are the same for identical locations.  Names
    # of matches are stored under this key, so that matches
    # in the same place are listed under the same location
    # in the EMBL file.
    my( %locstore );
    
    foreach my $match_type (@$matches) {
        foreach my $homol_tag (@$homol_tags) {
            foreach my $homol ($ace->at("Homol.\Q$match_type\E[1]")) {

                # Skip names containing question marks!
                #warn "Skipping bad name '$homol'\n" and next if $homol =~ /\?/;

                my( @block );
                foreach my $coords ($homol->at("\Q$homol_tag\E[1]")) {
                    my( @row ) = map $_->name, $coords->row;
                    die "Incomplete data row Homol.$match_type.$homol.$homol_tag '@row'"
                        unless @row == 5;

                    # Store data in @block array
                    push( @block, [@row] );
                }

                if (my @loc_objects = location_from_homol_block(\@block, $score, 300)) {

                    # Don't add data for this match unless it has a sensible name
                    my ($homol_name) = $pdmp->fixNames( $homol->name );
                    next unless $homol_name;

                    foreach my $loc (@loc_objects) {
                        my $loc_string = $loc->hash_key;
                        $locstore{$loc_string}->{'loc'} = $loc;
                        $locstore{$loc_string}->{'names'}{$homol_name}++
                    }
                }
            }
        }
    }
    
    foreach my $s (keys %locstore) {
        my $loc = $locstore{$s}->{'loc'};
        my @names = sort keys %{$locstore{$s}->{'names'}};
        
        # Warn about db data duplication
        foreach my $n (@names) {
            my $i = $locstore{$s}->{'names'}{$n};
            warn "Match to sequence '$n' found in $i databases\n" if $i > 1;
        }
        
        # Make a new feature object
        my $feat = $set->newFeature;
        $feat->key('misc_feature');
        $feat->location( $loc );
        $feat->addQualifierStrings('note', "match: $type: @names");
    }
}


BEGIN {
    
    # Mapping of assembly tags to variation types for notes in features
    my %TN = ('Variation - Substitution' => 'substitution',
	      'Variation - Insertion' => 'insertion',
	      'Variation - Deletion' => 'deletion');

    sub add_AssemblyTags_FT {
        my( $pdmp, $embl ) = @_;

        my $set = Hum::EMBL::FeatureSet->new;

        # Add data from the unsure tag
        foreach my $row ($pdmp->get_all_assembly_tags('Assembly_tags.unsure')) {
            my ($x, $y, @notes) = @$row;
	    # Make a new feature object
	    my $feat = $set->newFeature;
	    $feat->key('unsure');
	    $feat->location( simple_location($x, $y) );
            foreach my $n (@notes) {
	        $feat->addQualifierStrings('note', $n);
            }
        }

        # Add data from the - tag (This now goes under "misc_feature").
        foreach my $row ($pdmp->get_all_assembly_tags('Assembly_tags.-')) {
            my ($x, $y, @notes) = @$row;
	    # Make a new feature object
	    my $feat = $set->newFeature;
	    $feat->key('misc_feature');
	    $feat->location( simple_location($x, $y) );
            foreach my $n (@notes) {
	        $feat->addQualifierStrings('note', $n);
            }
        }

        # Add variation data
        # Case won't matter for each of the types
        foreach my $type ( keys %TN ) {
            my $var_type = $TN{$type};
            my $tag_string = "Assembly_tags.$type";

    	    # Get data for this variation type
          ROW: foreach my $row ($pdmp->get_all_assembly_tags($tag_string)) {
                my ($x, $y, $note) = @$row;
                
		my ($feat,  # The new feature
		    @quals  # Qualifiers to add to the feature
		    );

		# Get the text for the qualifiers
		my ($other_seq)     = $note =~ /Sequence in other clone -\s*(\w+)/i;
		my ($other_clone)   = $note =~ /Other clone -\s*(\w+)/i;
		my ($this_seq)      = $note =~ /Sequence in this clone -\s*(\w+)/i;

		# Check we got something from each pattern match:
		foreach my $txt ($other_seq, $other_clone, $this_seq) {
		    unless ($txt) {
			warn "Unparseable line: $tag_string: [",
			    (join ', ', map "'$_'", @$row), "]\n";
			next ROW;
		    }
		}
		$other_seq = lc $other_seq;
		$this_seq = lc $this_seq;

                # Give the correct international clone name for the other sequence
                my $ext_name = intl_clone_name($other_clone);
		$other_clone = "clone $ext_name";
		$this_seq .= ' in this entry';

		# Make a new feature object
		$feat = $set->newFeature;
		$feat->key('variation');
		$feat->location( simple_location($x,$y) );
                $feat->addQualifierStrings('replace', $other_seq   );
                $feat->addQualifierStrings('note',    $other_clone );
                $feat->addQualifierStrings('note',    $this_seq    );
                $feat->addQualifierStrings('note',    $var_type    );
	    }
        }
        # Add the features into the entry
        $set->sortByPosition;
        $set->mergeFeatures;
        $set->addToEntry($embl);
    }
}


sub get_all_assembly_tags {
    my( $pdmp, $tag_string ) = @_;
    
    my $ace = $pdmp->ace_Sequence_object;
    
    # Yes, it's a loop 3 levels deep to get all the data!
    my( @table );
    foreach my $x ($ace->at($tag_string .'[1]')) {
        foreach my $y ($x->col(1)) {
            my $ass_tag = [$x->name, $y->name];
            foreach my $note ($y->col(1)) {
                my $note_text = $note->name;
                push(@$ass_tag, $note_text) if $note_text;
            }
            push(@table, $ass_tag);
        }
    }
    return @table;
}

sub add_Repeats_FT {
    my( $pdmp, $embl ) = @_;
    
    my $ace = $pdmp->ace_Sequence_object;
    
    my $tan = Hum::EMBL::FeatureSet->new;
    foreach my $tag (qw{ trf tandem }) {
        my $have_tan = 0;
        foreach my $t ($ace->at("Feature.$tag". '[1]')) {
            my($x, $y, $pc, $desc) = map $_->name, $t->row;
            next unless $desc;
            $pc = sprintf("%2d", $pc);

            $have_tan = 1;

            my $ft = $tan->newFeature;
            $ft->key('repeat_region');
            $ft->location(simple_location($x, $y));
            $ft->addQualifierStrings('note', "$desc $pc\% conserved");
        }
        last if $have_tan;  # Don't add features from both trf and tandem
    }
    $tan->sortByPosition;
    $tan->mergeFeatures;
    $tan->addToEntry($embl);
    
    my $complex = Hum::EMBL::FeatureSet->new;
    foreach my $repeat ($ace->at('Homol.Motif_homol[1]')) {
        foreach my $score ($repeat->col(2)) {
            foreach my $row ($score->col(1)) {
                my( $x, $y, $b, $e ) = map $_->name, $row->row;
                my $ft = $complex->newFeature;
                $ft->key('repeat_region');
                $ft->location(simple_location($x, $y));
                $ft->addQualifierStrings('note', "$repeat repeat: matches $b..$e of consensus");
            }
        }
    }
    $complex->sortByPosition;
    $complex->mergeFeatures;
    $complex->addToEntry($embl);
}


BEGIN {

    # List of known prefixes
    my %DBprefixes = map {$_, 1} qw( Em Sw Tr Wp );
    
    sub fixNames {
        my( $pdmp, @matches ) = @_;
        
        for (my $i = 0; $i < @matches;) {
            my $m = $matches[$i];
            my ($prefix, $acc) = $m =~ /^(..):(.+)/;
            eval{
                die "No prefix\n" unless $prefix and $acc;
                if ($acc =~ s/(\.\d+)//) {
                    #warn "Removed suffix '$1' from '$acc$1'\n";
                }
                $prefix = ucfirst lc $prefix;
                die "Unknown DB prefix '$prefix'\n" unless $DBprefixes{ $prefix };
            };
            
            if ($@) {
                warn "Removing '$m' from list: $@";
                splice(@matches, $i, 1);
            } else {
                $matches[$i] = "$prefix:$acc";
                $i++;
            }
        }
        return @matches;
    }
}


1;

__END__

=head1 NAME - Hum::ProjectDump::EMBL::Finished

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

