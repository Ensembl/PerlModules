
### Hum::ProjectDump::EMBL::HGMP

package Hum::ProjectDump::EMBL::HGMP;

use strict;
use Hum::ProjectDump::EMBL;
use Hum::EMBL::Utils qw( EMBLdate );

use vars '@ISA';
@ISA = 'Hum::ProjectDump::EMBL';

{
    my( @author_list );

    my $author_list = q{

        Clarke D.
        Connor R.
        Leaves N.I.
        Caveberry L.
        Greystrong J.
        North P.C.
        Hunter G.
        Shufflebottom L.
        Kimberly C.
        Campbell M.
        Jones S.
        Lawrence N.
        Strachan G.L.
        Greenham L.
        Maggott K.
        Botcherby M.R.M.

        };
    
    foreach my $line (split /\n/, $author_list) {
        next unless $line =~ /\w/;
        $line =~ s/^\s+|\s*$//g;
        push(@author_list, $line);
    }

    sub add_Reference {
        my( $pdmp, $embl, $seqlength ) = @_;

        my $date = EMBLdate();
        my $ext_clone = $pdmp->external_clone_name;
        my $bi_nom = $pdmp->species_binomial;
        
        my $ref = $embl->newReference;
        $ref->number(1);
        $ref->comments('HGMP-RC part of the UK Mouse Sequencing Consortium');
        $ref->authors(@author_list);
        $ref->title("The sequence of $bi_nom clone $ext_clone");
        $ref->locations('Unpublished');
        $embl->newXX;

        my $ref2 = $embl->newReference;
        $ref2->number(2);
        $ref->positions("1-$seqlength");
        $ref2->authors('HGMP-RC');
        $ref2->locations(
            "Submitted ($date) to the EMBL/Genbank/DDBJ databases.",
            'Mouse Sequencing Group, HGMP-RC, Hinxton, Cambridge, CB10 1SB, UK.',
            'E-mail enquiries:- mrbotche@hgmp.mrc.ac.uk or dclarke2@hgmp.mrc.ac.uk');
        $embl->newXX;
    }
}

sub add_Description {
    my( $pdmp, $embl ) = @_;
    
    my $ext_clone  = $pdmp->external_clone_name;
    my $contig_num = $pdmp->contig_count;
    my $species    = $pdmp->species;
    my $de = $embl->newDE;
    $de->list(
        "$species DNA sequence *** SEQUENCING IN PROGRESS *** from clone $ext_clone",
        "$contig_num unordered pieces");
    $embl->newXX;
}

sub add_Headers {
    my( $pdmp, $embl, $contig_map ) = @_;
    
    my $num = $pdmp->contig_count;
    $embl->newCC->list(
        '* NOTE: This is a "working draft" sequence. It currently',
        "* consists of $num contigs. The true order of the pieces",
        '* is not known and their order in this sequence record is',
        '* arbitrary. Gaps between the contigs are represented as',
        '* runs of N, but the exact sizes of the gaps are unknown.',
        '* This record will be updated with the finished sequence',
        '* as soon as it is available and the accession number will',
        '* be preserved.',
        
        $pdmp->make_fragment_summary($embl, $contig_map),
        );
}

sub read_latest_fasta {
    my( $pdmp ) = @_;
    
    my $path = $pdmp->online_path;
    
    local *FASTA_PROJ;
    opendir FASTA_PROJ, $path or die "Can't opendir('$path') : $!";
    warn "Looking in '$path'\n";
    my %fasta = map {$_, (stat($_))[9]}
        map "$path/$_",
        grep /\.fasta$/, readdir FASTA_PROJ;
    closedir FASTA_PROJ;
    my ($file) = sort {$fasta{$b} <=> $fasta{$a}} keys %fasta;
    
    local *FASTA;
    open FASTA, $file or die "Can't read '$file' : $!";
    my( $dna );
    while (<FASTA>) {
        chomp;
        if (/^>/) {
            my ($contig) = /(\d+)[^\d]*?$/;
            die "Can't get a contig number from '$_'" unless $contig;
            $dna = $pdmp->new_dna_ref($contig);
        } else {
            $$dna .= $_;
        }
    }
    close FASTA;
    
    if (my $count = $pdmp->contig_count) {
        $pdmp->dump_time(time); # Record the time of the dump
        return $count;
    } else {
        die "Zero contigs read from '$file'";
    }
}

1;

__END__

=head1 NAME - Hum::ProjectDump::EMBL::HGMP

=head1 DESCRIPTION



=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

