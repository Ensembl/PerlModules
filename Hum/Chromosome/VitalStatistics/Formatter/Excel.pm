
### Hum::Chromosome::VitalStatistics::Formatter::Excel

package Hum::Chromosome::VitalStatistics::Formatter::Excel;

use strict;
use warnings;
use Carp;
use Spreadsheet::WriteExcel;
use base 'Hum::Chromosome::VitalStatistics::Formatter';

sub make_report {
    my( $self, @stats_list ) = @_;

    my $fh = $self->file;
    my $book = Spreadsheet::WriteExcel->new($fh);
    $self->setup_formats($book);

    foreach my $stats (@stats_list) {
        my $sheet_name = $stats->gene_type;
        $sheet_name =~ s/^HUMACE-//;
        $self->write_stats_sheet($stats, $book->addworksheet($sheet_name));
    }
    
    $book->close;
    close($fh);
}

sub setup_formats {
    my( $self, $book ) = @_;
    
    my $cache = $self->{'_formats_cache'} = {};
    $cache->{'thousands'} = $book->addformat(
        'num_format'    => '#,##0',
        );
    $cache->{'two_decimal'} = $book->addformat(
        'num_format'    => '0.00',
        );
    $cache->{'bold'} = $book->addformat(
        'bold'  => 1,
        );
    $cache->{'right'} = $book->addformat(
        'align' => 'right',
        );
}

sub get_format {
    my( $self, $name ) = @_;
    
    confess "Missing format name argument" unless $name;
    return $self->{'_formats_cache'}{$name}
        || confess "No format named '$name'";
}

sub current_row_col {
    my( $self, $row, $col ) = @_;
    
    if (defined $row and defined $col) {
        $self->{'_current_row_col'} = [$row, $col];
    }
    elsif (defined $row or defined $col) {
        confess "Missing argument, got: row='$row' and col='$col'";
    }
    else {
        my $rc = $self->{'_current_row_col'} or confess "row and col not set";
        return @$rc;
    }
}

sub next_row_col {
    my( $self ) = @_;
    
    my ($row, $col) = $self->current_row_col;
    $row += 2;
    return ($row, 0);
}

sub write_stats_sheet {
    my( $self, $stats, $sheet ) = @_;
    
    # Set first column to width 20
    $sheet->set_column(0, 0, 20);

    # Set third column to width 10
    $sheet->set_column(2, 2, 10);
    
    my $row = 0;
    my $col = 0;
    $sheet->write_string(  $row, $col, $self->head);
    $sheet->write_string(++$row, $col, $self->note);
    
    $row += 2;
    $sheet->write_string(  $row, $col, 'Gene type', $self->get_format('right'));
    $sheet->write_string(  $row, $col+1, $stats->gene_type, $self->get_format('bold'));
    
    $self->current_row_col($row, $col);
    
    $self->write_gene_exon_intron_counts(               $stats, $sheet);
    $self->write_transcripts_and_exons_per_gene(        $stats, $sheet);
    $self->write_single_exon_genes_and_splice_counts(   $stats, $sheet);
    $self->write_biggest_and_smallest_gene_and_exon(    $stats, $sheet);
    $self->write_largest_transcript_and_exon_count(     $stats, $sheet);
}

sub write_gene_exon_intron_counts {
    my( $self, $stats, $sheet ) = @_;

    my ($row, $col) = $self->next_row_col;
    
    $sheet->write_string($row, $col+3, 'Length', );
    $sheet->write_row(++$row, $col+1, [qw{ Count Total Mean Median }]);

    my $thousands  = $self->get_format('thousands');
    my $right      = $self->get_format('right');

    # Genes
    my $gene_lengths = $stats->gene_lengths;
    my $gene_count   = scalar @$gene_lengths;
    my $total_gene_length = 0;
    for (my $i = 0; $i < @$gene_lengths; $i++) {
        $total_gene_length += $gene_lengths->[$i];
    }
    $sheet->write_string(++$row, $col, 'Genes', $right);
    $sheet->write_number($row, $col+1, $gene_count, $thousands);
    $sheet->write_number($row, $col+2, $total_gene_length, $thousands);
    $sheet->write_number($row, $col+3, $total_gene_length / $gene_count, $thousands);
    $sheet->write_number($row, $col+4, $stats->median($gene_lengths), $thousands);

    # Exons
    my $exon_lengths = $stats->exon_lengths;
    if (my $exon_count   = scalar @$exon_lengths) {
        my $total_exon_length = 0;
        for (my $i = 0; $i < @$exon_lengths; $i++) {
            $total_exon_length += $exon_lengths->[$i];
        }
        $sheet->write_string(++$row, $col, 'Exons', $right);
        $sheet->write_number($row, $col+1, $exon_count, $thousands);
        $sheet->write_number($row, $col+2, $total_exon_length, $thousands);
        $sheet->write_number($row, $col+3, $total_exon_length / $exon_count, $thousands);
        $sheet->write_number($row, $col+4, $stats->median($exon_lengths), $thousands);
    }

    # Introns
    $row++;
    my $intron_lengths = $stats->intron_lengths;
    if (my $intron_count   = scalar @$intron_lengths) {
        my $total_intron_length = 0;
        for (my $i = 0; $i < @$intron_lengths; $i++) {
            $total_intron_length += $intron_lengths->[$i];
        }
        $sheet->write_string(++$row, $col, 'Introns', $right);
        $sheet->write_number($row, $col+1, $intron_count, $thousands);
        $sheet->write_number($row, $col+2, $total_intron_length, $thousands);
        $sheet->write_number($row, $col+3, $total_intron_length / $intron_count, $thousands);
        $sheet->write_number($row, $col+4, $stats->median($intron_lengths), $thousands);
    }
    
    $self->current_row_col($row, $col+4);
}

sub write_transcripts_and_exons_per_gene {
    my( $self, $stats, $sheet ) = @_;

    my ($row, $col) = $self->next_row_col;
    my $right = $self->get_format('right');
    my $two   = $self->get_format('two_decimal');
    
    $sheet->write_string($row, $col+1, 'Mean');
    $sheet->write_string($row, $col+2, 'Median');
    my $transcript_counts = $stats->transcript_counts;
    my $transcript_total = 0;
    foreach my $n (@$transcript_counts) {
        $transcript_total += $n;
    }
    $sheet->write_string(++$row, $col, 'Transcripts per gene', $right);
    $sheet->write_number(  $row, $col+1, $transcript_total / scalar(@$transcript_counts), $two);
    $sheet->write_number(  $row, $col+2, $stats->median($transcript_counts), $two);

    my $exon_counts = $stats->exon_counts;
    my $exon_total = 0;
    foreach my $n (@$exon_counts) {
        $exon_total += $n;
    }
    $sheet->write_string(++$row, $col, 'Exons per gene', $right);
    $sheet->write_number(  $row, $col+1, $exon_total / scalar(@$exon_counts), $two);
    $sheet->write_number(  $row, $col+2, $stats->median($exon_counts), $two);
    
    $self->current_row_col($row, $col+2);
}

sub write_single_exon_genes_and_splice_counts {
    my( $self, $stats, $sheet ) = @_;

    my ($row, $col) = $self->next_row_col;
    my $right = $self->get_format('right');
    
    $sheet->write_string($row, $col+1, 'Count');
    
    $sheet->write_string(++$row, $col, 'Single exon genes', $right);
    $sheet->write_number(  $row, $col+1, $stats->single_exon_gene_count);
    
    my $sc = $stats->splice_counts;
    foreach my $splice (sort keys %$sc) {
        $sheet->write_string(++$row, $col, "phase $splice splices", $right);
        $sheet->write_number(  $row, $col+1, $sc->{$splice});
    }
    
    $self->current_row_col($row, $col+1);
}

sub write_biggest_and_smallest_gene_and_exon {
    my( $self, $stats, $sheet ) = @_;

    my ($row, $col) = $self->next_row_col;
    my $right = $self->get_format('right');
    
    $sheet->write_string($row, $col+1, 'Length');
    $sheet->write_string($row, $col+2, 'Name');
    
    foreach my $method (qw{
        longest_gene
        shortest_gene
        longest_exon
        shortest_exon
        longest_intron
        })
    {
        $row++;
        my $nv = $stats->$method or next;
        $sheet->write_string($row, $col,   $nv->label, $right);
        $sheet->write_number($row, $col+1, $nv->value);
        $sheet->write_string($row, $col+2, $nv->name);
    }
    $self->current_row_col($row, $col+2);
}

sub write_largest_transcript_and_exon_count {
    my( $self, $stats, $sheet ) = @_;

    my ($row, $col) = $self->next_row_col;
    my $right = $self->get_format('right');
    
    $sheet->write_string($row, $col+1, 'Count');
    $sheet->write_string($row, $col+2, 'Name');
    
    foreach my $method (qw{
        most_transcripts
        most_exons
        })
    {
        $row++;
        my $nv = $stats->$method or next;
        $sheet->write_string($row, $col,   $nv->label, $right);
        $sheet->write_number($row, $col+1, $nv->value);
        $sheet->write_string($row, $col+2, $nv->name);
    }
    $self->current_row_col($row, $col+2);
}

1;

__END__

=head1 NAME - Hum::Chromosome::VitalStatistics::Formatter::Excel

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

