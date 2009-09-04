
### Hum::Translator

package Hum::Translator;

use strict;
use warnings;
use Hum::Sequence::Peptide;
use Carp;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub new_seleno {
    my ($pkg) = @_;
    
    my $self = $pkg->new;
    $self->codon_table('seleno_standard');
    return $self;
}

sub unknown_amino_acid {
    my( $self, $unk ) = @_;
    
    if ($unk) {
        $self->{'_unknown_amino_acid'} = $unk;
    }
    return $self->{'_unknown_amino_acid'} || 'X';
}

{

    my %tables = (
        standard => {

            'tca' => 'S',    # Serine
            'tcc' => 'S',    # Serine
            'tcg' => 'S',    # Serine
            'tct' => 'S',    # Serine

            'ttc' => 'F',    # Phenylalanine
            'ttt' => 'F',    # Phenylalanine
            'tta' => 'L',    # Leucine
            'ttg' => 'L',    # Leucine

            'tac' => 'Y',    # Tyrosine
            'tat' => 'Y',    # Tyrosine
            'taa' => '*',    # Stop
            'tag' => '*',    # Stop

            'tgc' => 'C',    # Cysteine
            'tgt' => 'C',    # Cysteine
            'tga' => '*',    # Stop or Selenocysteine (U)
            'tgg' => 'W',    # Tryptophan

            'cta' => 'L',    # Leucine
            'ctc' => 'L',    # Leucine
            'ctg' => 'L',    # Leucine
            'ctt' => 'L',    # Leucine

            'cca' => 'P',    # Proline
            'ccc' => 'P',    # Proline
            'ccg' => 'P',    # Proline
            'cct' => 'P',    # Proline

            'cac' => 'H',    # Histidine
            'cat' => 'H',    # Histidine
            'caa' => 'Q',    # Glutamine
            'cag' => 'Q',    # Glutamine

            'cga' => 'R',    # Arginine
            'cgc' => 'R',    # Arginine
            'cgg' => 'R',    # Arginine
            'cgt' => 'R',    # Arginine

            'ata' => 'I',    # Isoleucine
            'atc' => 'I',    # Isoleucine
            'att' => 'I',    # Isoleucine
            'atg' => 'M',    # Methionine

            'aca' => 'T',    # Threonine
            'acc' => 'T',    # Threonine
            'acg' => 'T',    # Threonine
            'act' => 'T',    # Threonine

            'aac' => 'N',    # Asparagine
            'aat' => 'N',    # Asparagine
            'aaa' => 'K',    # Lysine
            'aag' => 'K',    # Lysine

            'agc' => 'S',    # Serine
            'agt' => 'S',    # Serine
            'aga' => 'R',    # Arginine
            'agg' => 'R',    # Arginine

            'gta' => 'V',    # Valine
            'gtc' => 'V',    # Valine
            'gtg' => 'V',    # Valine
            'gtt' => 'V',    # Valine

            'gca' => 'A',    # Alanine
            'gcc' => 'A',    # Alanine
            'gcg' => 'A',    # Alanine
            'gct' => 'A',    # Alanine

            'gac' => 'D',    # Aspartic Acid
            'gat' => 'D',    # Aspartic Acid
            'gaa' => 'E',    # Glutamic Acid
            'gag' => 'E',    # Glutamic Acid

            'gga' => 'G',    # Glycine
            'ggc' => 'G',    # Glycine
            'ggg' => 'G',    # Glycine
            'ggt' => 'G',    # Glycine

        },
    );

    # Make a copy of the standard codon table, with
    # Selenocysteine replacing the stop for "tga".
    $tables{'seleno_standard'} = { %{$tables{'standard'}} };
    $tables{'seleno_standard'}{'tga'} = 'U';

    sub codon_table {
        my( $self, $table_name ) = @_;
    
        if ($table_name) {
            unless ($tables{$table_name}) {
                confess "No such table '$table_name'";
            }
            $self->{'_codon_table'} = $table_name;
        }
        return $self->{'_codon_table'} || 'standard';
    }

    sub translate {
        my( $self, $seq ) = @_;
    
        my $is_seq = 0;
        eval{
            $is_seq = $seq->isa('Hum::Sequence');
        };
        unless ($is_seq) {
            confess "Expecting a 'Hum::Sequence' object, but got '$seq'";
        }
    
        my $seq_str = lc $seq->sequence_string;
        my $table_name = $self->codon_table;
        my $codon_table = $tables{$table_name}
            or confess "No codon table called '$table_name'";
        my $unknown_amino_acid = $self->unknown_amino_acid;
        my $pep_str = '';
        while ($seq_str =~ /(...)/g) {
            $pep_str .= $codon_table->{$1} || $unknown_amino_acid;
        }
        if (length($seq_str) % 3) {
            $pep_str .= $unknown_amino_acid;
        }
    
        my $pep = Hum::Sequence::Peptide->new;
        $pep->name($seq->name);
        $pep->sequence_string($pep_str);
    
        return $pep;
    }
}

1;

__END__

=head1 NAME - Hum::Translator

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

