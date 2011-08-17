
### Hum::ProjectDump::EMBL::Unfinished::Multiplexed

package Hum::ProjectDump::EMBL::Unfinished::Multiplexed;

use strict;
use warnings;
use Carp;
use Hum::Conf 'HUMPUB_BLAST';
use Hum::FastqFileIO;

use base 'Hum::ProjectDump::EMBL::Unfinished';

sub process_repository_data {
    my ($self) = @_;

    my $fastq_file = $self->dump_gap5_data;
    my $fasta_file = $self->strip_zero_quality_data($fastq_file);
    $self->find_contaminants_with_exonerate($fasta_file);
    $self->decontaminate_contigs;
}

sub temp_file {
    my ($self, $file) = @_;

    if ($file) {
        $self->{'_temp_file'}{$file} = 1;
        return $file;
    }
    return $self->{'_temp_file'};
}

sub DESTROY {
    my ($self) = @_;

    if (my $tmp = $self->temp_file) {
        foreach my $file (keys %$tmp) {
            if (unlink($file)) {
                delete $tmp->{$file};
            }
            else {
                warn "Error deleting '$file'; $!\n";
            }
        }
    }
}

sub dump_gap5_data {
    my ($self) = @_;

    my $db_dir              = $self->online_path || confess "No online path";
    my $project_name        = $self->project_name;
    my $gap_5_db            = "$db_dir/$project_name.0";
    my $user                = (getpwuid($<))[0];
    my $out_fastq           = "/tmp/$user-$$-gap5-dump.fastq";
    my @gap_5_consensus_cmd = (qw{ gap5_consensus -format fastq -strip_pads -out }, $out_fastq, $gap_5_db,);
    system(@gap_5_consensus_cmd) == 0
      or die "Error running '@gap_5_consensus_cmd'; exit($?)";
    return $self->temp_file($out_fastq);
}

sub strip_zero_quality_data {
    my ($self, $fastq_file) = @_;

    my $fasta_file = $fastq_file;
    $fasta_file =~ s/\.fastq$/.seq/
      or confess "Unexepected file name format '$fastq_file'";
    my $in         = Hum::FastqFileIO->new($fastq_file);
    my $out        = Hum::FastaFileIO->new("> $fasta_file");
    my $min_length = $self->contig_length_cutoff;
    my $n          = 1;
    while (my $seq = $in->read_one_sequence) {
        my $dna  = $seq->sequence_string;
        my $qual = $seq->quality_string;
        if ($qual =~ s/^\0+//) {
            my $clip_length = length($dna) - length($qual);
            substr($dna, 0, $clip_length, '');
        }
        if ($qual =~ s/\0+$//) {
            my $dna_length  = length($dna);
            my $clip_length = $dna_length - length($qual);
            substr($dna, $dna_length - $clip_length, $clip_length, '');
        }

        # Output the sequence if there is any left
        if (length($dna) >= $min_length) {
            my $old_name = $seq->name;
            my $desc     = $seq->description;
            my $name     = sprintf 'contig_%05d', $n++;
            $seq->name($name);
            $seq->description("($old_name) $desc");
            $seq->sequence_string($dna);
            $seq->quality_string($qual);

            $out->write_sequences($seq);

            # Could have populated DNA data by re-parsing fasta file.
            # More efficient to do just save it here.
            $self->DNA($name, \$dna);

            # We don't submit quality data from gap5, because it doesn't look useful.
            # Scores tend to be either 93 (max) or 0.
            # $self->BaseQuality($name, \$qual);
        }
    }
    return $self->temp_file($fastq_file);
}

sub find_contaminants_with_exonerate {
    my ($self, $fasta_file) = @_;

    my @exonerate = (
        'exonerate',
        qw{
          --querytype        dna
          --targettype       dna
          --model            ungapped
          --dnawordlen       14
          --dnahspthreshold  140
          --ryo              CONTAMINANT\t%pi\t%qi\t%qab\t%qae\t%qS\t%ti\n
          --showalignment    FALSE
          --showvulgar       FALSE
          --softmasktarget   TRUE
          },
        '--query'  => $fasta_file,
        '--target' => "$HUMPUB_BLAST/contamdb_dustmasked",
    );
    open(my $find_contaminants, '-|', @exonerate)
      or confess "Error starting '@exonerate |'; $!";
    my %contig_contamination;
    while (<$find_contaminants>) {
        my ($type, $percent_identity, $contig, $start, $end, $strand, $contaminant) = split /\t/;
        unless ($type and $type eq 'CONTAMINANT') {
            next;
        }
        warn $_;
        if ($percent_identity < 80) {
            next;
        }
        unless ($strand eq '+') {
            confess "Only expect '+' strand hits from exonerate with ungapped model, but got '$strand'";
        }
        if ($start > $end) {
            confess "Do not expect start ($start) > end ($end)";
        }
        $start++;    # exonerate coordinates are "between bases"
        printf STDERR "Marking %d bp of %s contamination in %s at %d\n", $end - $start + 1, $contaminant, $contig,
          $start;
        my $cont_array = $contig_contamination{$contig} ||= [];
        push(@$cont_array, [ $start, $end ]);
    }
    close $find_contaminants or confess "Error running '@exonerate |'; exit $?";

    foreach my $contig (keys %contig_contamination) {
        $self->contamination($contig, $contig_contamination{$contig});
    }
}

1;

__END__

=head1 NAME - Hum::ProjectDump::EMBL::Unfinished::Multiplexed

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

