
### Hum::ProjectDump::EMBL::Finished

package Hum::ProjectDump::EMBL::Finished;

use strict;

use Carp;
use Hum::ProjectDump::EMBL;
use Hum::Tracking qw{
    library_and_vector
    prepare_track_statement };

use vars qw{ @ISA };
@ISA = qw{ Hum::ProjectDump::EMBL };

sub add_Description {
    my( $pdmp, $embl ) = @_;
    
    my $species   = $pdmp->species;
    my $ext_clone = $pdmp->external_clone_name;
    my $desc = "$species DNA sequence from clone $ext_clone";
    if (my $chr = $pdmp->chromosome) {
        if ($species eq 'Zebrafish') {
            $desc .= " in linkage group $chr";
        } else {
            $desc .= " on chromosome $chr";
        }
    }
    if (my $map = $pdmp->fish_map) {
        $desc .= $map;
    }
    my $de = $embl->newDE;
    $de->list($desc);
    $embl->newXX;
}

sub add_Keywords {
    my( $pdmp, $embl ) = @_;
    
    my $kw = $embl->newKW;
    $kw->list('HTG');
    $embl->newXX;
}

sub add_Headers {
    my( $pdmp, $embl ) = @_;
    
    $pdmp->      add_standard_CC($embl);
    $pdmp->   add_chromosomal_CC($embl);
    $pdmp->       add_library_CC($embl);
    $pdmp->add_external_draft_CC($embl);
    
    ### Can't add overlap info yet because this depends on acedb data
    #$pdmp->add_overlap_CC($embl);
}

sub add_FT_entries {
    # Nothing to add (but maybe some genes and stuff in the future?)
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
M13 subclone; and the assembly was confirmed by restriction digest.',


'The following abbreviations are used to associate primary accession
numbers given in the feature table with their source databases:
Em:, EMBL; Sw:, SWISSPROT; Tr:, TREMBL; Wp:, WORMPEP;
Information on the WORMPEP database can be found at
http://www.sanger.ac.uk/Projects/C_elegans/wormpep');
    
    sub add_standard_CC {
        my( $pdmp, $embl ) = @_;

        # Add the standard headers
        foreach my $t (@std) {
            my $cc = $embl->newCC;
            $cc->list($t);
            $embl->newXX;
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

    foreach (qw( RPCI-21 RPCI-23 RPCI-22 )) {
        $lib_comments{$_} =
"is from the $_ Mouse PAC Library
constructed by the group of Pieter de Jong.
For further details see http://www.chori.org/bacpac/home.htm"
    }

    $lib_comments{'CITB-CJ7-B'} =
"is from the Research Genetics 129 mouse BAC library (CITB-CJ7-B).";

    sub add_library_CC {
        my( $pdmp, $embl ) = @_;
        
        my $project = $pdmp->project_name;
        my ($lib, $vector) = library_and_vector($project);
        
        return unless $lib;
        
        my $comment = $lib_comments{$lib};
        unless ($comment) {
            $sth ||= prepare_track_statement(q{
                SELECT description
                FROM library
                WHERE libraryname = ?
                });
            $sth->execute($lib);
            my ($des) = $sth->fetchrow;
            if ($des =~ /\S/) {
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
    }
}

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

1;

__END__

=head1 NAME - Hum::ProjectDump::EMBL::Finished

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

