
### Hum::Sequence

package Hum::Sequence;

use strict;
use warnings;
use Carp;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub name {
    my( $seq_obj, $name ) = @_;
    
    if ($name) {
        $seq_obj->{'_name'} = $name;
    }
    return $seq_obj->{'_name'};
}

sub description {
    my( $seq_obj, $description ) = @_;
    
    if ($description) {
        $seq_obj->{'_description'} = $description;
    }
    return $seq_obj->{'_description'};
}

sub sequence_string {
    my( $seq_obj, $sequence_string ) = @_;
    
    if ($sequence_string) {
        $seq_obj->{'_sequence_string'} = $sequence_string;
    }
    return $seq_obj->{'_sequence_string'};
}

sub sequence_length {
    my( $seq_obj ) = @_;
    
    return length($seq_obj->sequence_string);
}

sub lowercase {
    my( $seq_obj ) = @_;
    
    my $seq = $seq_obj->sequence_string;
    $seq =~ tr/[A-Z]/[a-z]/;
    $seq_obj->sequence_string($seq);
}

sub uppercase {
    my( $seq_obj ) = @_;
    
    my $seq = $seq_obj->sequence_string;
    $seq =~ tr/[a-z]/[A-Z]/;
    $seq_obj->sequence_string($seq);
}

sub embl_checksum {
    my( $seq_obj ) = @_;
    
    require Hum::EMBL::Utils;
    my $seq = $seq_obj->sequence_string;
    return Hum::EMBL::Utils::crc32(\$seq);
}

sub sub_sequence {
    my( $seq_obj, $x, $y ) = @_;
    
    if ($x > $y) {
        confess "Start '$x' greater than end '$y'";
    }
    
    my $seq_length = $seq_obj->sequence_length;
    if ($y > $seq_length) {
        confess "Coordinate '$y' is off end of sequence length '$seq_length'";
    }
    
    if ($x < 1) {
        confess "Start '$x' is before the start of the sequence";
    }
    
    my $seq_string = $seq_obj->sequence_string;
    my $offset = $x - 1;
    my $length = $y - $x + 1;
    my $sub_seq_string = substr($seq_string, $offset, $length);
    my $actual_length = length($sub_seq_string);
    if ($length != $actual_length) {
        confess "substr got '$actual_length', not '$length' from sequence";
    }
    
    my $sub_seq = ref($seq_obj)->new;
    $sub_seq->sequence_string($sub_seq_string);
    return $sub_seq;
}

sub fasta_string {
    my( $seq_obj ) = @_;
    
    my $name = $seq_obj->name
        or confess "No name";
    my $desc = $seq_obj->description;
    my $seq  = $seq_obj->sequence_string
        or confess "No sequence in '$name'";
    my $fasta_string = ">$name";
    $fasta_string .= "  $desc" if $desc;
    $fasta_string .= "\n";
    while ($seq =~ /(.{1,60})/g) {
        $fasta_string .= $1 . "\n";
    }
    return $fasta_string;
}

sub ace_string {
    my( $seq_obj ) = @_;
    
    my $name = $seq_obj->name
        or confess "No name";
    my $seq  = $seq_obj->sequence_string
        or confess "No sequence";
    my $ace_string = qq{\nSequence : "$name"\n\nDNA : "$name"\n};
    while ($seq =~ /(.{1,60})/g) {
        $ace_string .= $1 . "\n";
    }
    return $ace_string;
}

# mRNA, EST, Protein etc...
sub type {
	my ( $seq_obj, $type ) = @_;
    
    if ($type) {
        $seq_obj->{'_type'} = $type;
    }
    return $seq_obj->{'_type'};
}

1;

__END__

=head1 NAME - Hum::Sequence

=head1 DESCRIPTION

Baseclass for Hum::Sequence lightweight sequence
modules.

Single letter codes unique to amino acids:

    E   Glu     Glutamic Acid
    F   Phe     Phenylalanine
    I   Ile     Isoleucine
    L   Leu     Leucine
    P   Pro     Proline
    Q   Gln     Glutamine
    X   Unk     Unknown amino acid

Single letter codes only found in nucleotides:

                                      B   C or G or T
                                      U   Uracil

Single letter codes shared by amino acid and nucleotide alphabets:

    A   Ala     Alanine               A   Adenine
    C   Cys     Cysteine              C   Cytosine
    D   Asp     Aspartic Acid         D   A or G or T
    G   Gly     Glycine               G   Guanine
    H   His     Histidine             H   A or C or T
    K   Lys     Lysine                K   G or T
    M   Met     Methionine            M   A or C
    N   Asn     Asparagine            N   any base
    R   Arg     Arginine              R   A or G
    S   Ser     Serine                S   G or C
    T   Thr     Threonine             T   Thymine
    V   Val     Valine                V   A or C or G
    W   Trp     Tryptophan            W   A or T
    Y   Tyr     Tyrosine              Y   C or T

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

