
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
use Bio::Otter::EMBL::Factory;
use Hum::Species;

use vars qw{ @ISA };
@ISA = qw{ Hum::ProjectDump::EMBL };


### These first subroutines override
### subroutines in Hum::ProjectDump::EMBL

sub get_FT_Factory {
    my( $pdmp ) = @_;

    # Can't do this without an attached Otter database
    # and the acc and sv to use to get the data from it
    my $ds  = $pdmp->DataSet          or return;
    my $acc = $pdmp->accession        or return;
    my $sv  = $pdmp->sequence_version or return;
    
    my( $ft_factory );
    unless ($ft_factory = $pdmp->{'_ft_factory'}) {
    
        $ft_factory = Bio::Otter::EMBL::Factory->new;
        $ft_factory->DataSet($ds);
        $ft_factory->accession($acc);
        $ft_factory->sequence_version($sv);

        $pdmp->{'_ft_factory'} = $ft_factory;
    }
    return $ft_factory;
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
    if (my $ft_factory = $pdmp->get_FT_Factory) {
        push(@desc, $ft_factory->get_description_from_otter);
    }
    
    my $de = $embl->newDE;
    $de->list(@desc);
    $embl->newXX;
}

sub add_Keywords {
    my( $pdmp, $embl ) = @_;

    my @key_words = ('HTG');
    if (my $ft_factory = $pdmp->get_FT_Factory) {
        push(@key_words, $ft_factory->get_keywords_from_otter);
    }
    
    my $kw = $embl->newKW;
    $kw->list(@key_words);
    $embl->newXX;
}

sub add_Headers {
    my( $pdmp, $embl, $contig_map ) = @_;
    
    $pdmp->add_standard_CC($embl);
    unless ($pdmp->add_MHC_Consortium_CC($embl)) {
        $pdmp->add_chromosomal_CC($embl);
    }
    $pdmp->add_extra_CC($embl);
    $pdmp->add_library_CC($embl);
    $pdmp->add_external_draft_CC($embl);
    #$pdmp->add_overlap_CC($embl);
    $pdmp->add_extra_headers($embl, 'comment');
}

sub add_FT_entries {
    my( $pdmp, $embl, $contig_map ) = @_;
    
    my $ft_factory = $pdmp->get_FT_Factory or return;    
    $ft_factory->make_embl_ft($embl);
}

sub DataSet {
    my( $self, $DataSet ) = @_;
    
    if ($DataSet) {
        $self->{'_DataSet'} = $DataSet;
    }
    return $self->{'_DataSet'};
}


sub add_extra_CC {
    my( $pdmp, $embl ) = @_;
    
    return unless my $ds = $pdmp->DataSet;

    #warn "Adding Comment lines from otter database not yet implemented";
    return;

    # Add any CC lines
    my( @comment );
    #foreach my $c (...) {
    #    push( @comment, $c );
    #}
    
    return unless @comment;
    
    my $cc = $embl->newCC;
    $cc->list( @comment );
    $embl->newXX;
}


{
    
    # Standard comment blocks
    my @std = (

'This sequence was finished as follows unless otherwise noted: all regions were either double-stranded or sequenced with an alternate chemistry or covered by high quality data (i.e., phred quality >= 30); an attempt was made to resolve all sequencing problems, such as compressions and repeats; all regions were covered by at least one subclone; and the assembly was confirmed by restriction digest, except on the rare occasion of the clone being a YAC.',

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

'Any regions longer than 1kb tagged as misc-feature "unsure" are part of
a tandem repeat of more than 10kb in length where it has not been possible
to anchor the base differences between repeat copies.  The region has been
built up based on the repeat element to match the total size of repeat
indicated by restriction digest, but repeat copies may not be in the
correct order and the usual finishing criteria may not apply.');

    my @mouse_specific = ('Sequence from the Mouse Genome Sequencing Consortium whole genome shotgun may have been used to confirm this sequence.  Sequence data from the whole genome shotgun alone has only been used where it has a phred quality of at least 30.');

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
	if ($pdmp->species eq 'Mouse') {
            foreach my $entry (@mouse_specific) {
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
http://bacpac.chori.org/"
    }

    # RPCI-21 is PAC
    $lib_comments{'RPCI-21'} =
"is from the RPCI-21 Mouse PAC Library
constructed by the group of Pieter de Jong.
For further details see http://bacpac.chori.org/";

    # ... but RPCI-22 and 23 are BAC
    foreach (qw( RPCI-22 RPCI-23 )) {
        $lib_comments{$_} =
"is from the $_ Mouse BAC Library
constructed by the group of Pieter de Jong.
For further details see http://bacpac.chori.org/"
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


1;

__END__

=head1 NAME - Hum::ProjectDump::EMBL::Finished

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


