
### Hum::Chromosome::VitalStatistics::Formatter::HTML

package Hum::Chromosome::VitalStatistics::Formatter::HTML;

use strict;
use warnings;
use base 'Hum::Chromosome::VitalStatistics::Formatter';

sub make_report {
    my( $self, @stats_list ) = @_;

    my $fh = $self->file;
    
    my $head = $self->head;
    print $fh "<head><title>$head</title></head><body><html>\n",
        "<center>\n",
        "<h2>$head</h2>\n",
        "<p>Note: Exon and Intron statistics are derived from the longest transcript</p>";

    foreach my $stats (@stats_list) {
        print $fh $self->html_tables($stats);
    }
    
    print $fh "</center></html></body>";
}

sub html_tables {
    my( $self, $stats ) = @_;
    
    my $html = sprintf '<p>&nbsp;</p>
<table bgcolor="#cccccc" border="0" cellpadding="4" cellspacing="4">
    <tr>
        <th bgcolor="white">Gene type</th>  <td bgcolor="white">%s</td>
    </tr>
',
    $stats->gene_type;

    foreach my $table (
        $self->html_table_gene_exon_intron_counts($stats),
        $self->html_table_transcripts_and_exons_per_gene($stats),
        $self->html_table_single_exon_genes_and_splice_counts($stats),
        $self->html_table_biggest_and_smallest_gene_and_exon($stats),
        $self->html_table_largest_transcript_and_exon_count($stats),
        )
    {
        # Indent table
        $table =~ s/^/            /mg;
        $html .= sprintf '
    <tr>
        <td align="center" colspan="2">
        %s
        </td>
    </tr>
',
        $table;
    }
    $html .= qq{</table>\n};
    return $html;
}


sub html_table_gene_exon_intron_counts {
    my( $self, $stats ) = @_;


    my $html = '
<table bgcolor="#cccccc" border="0" cellpadding="4" cellspacing="4">
    <tr>
        <td></td>
        <th bgcolor="white" rowspan="2">
            Count
        </th>
        <th bgcolor="white" colspan="3">
            Length
        </th>
    </tr>
    <tr>
        <td></td>
        <th bgcolor="white">
            Total
        </th>
        <th bgcolor="white">
            Mean
        </th>
        <th bgcolor="white">
            Median
        </th>
    </tr>
';

    my $number_cell = '<td bgcolor="white" align="right">%.0f</td>';
    my $row_pattern = qq{
    <tr>
        <th bgcolor="white">%s</th>
        $number_cell
        $number_cell
        $number_cell
        $number_cell
    </tr>
};

    # Genes
    my $gene_lengths = $stats->gene_lengths;
    my $gene_count   = scalar @$gene_lengths;
    my $total_gene_length = 0;
    for (my $i = 0; $i < @$gene_lengths; $i++) {
        $total_gene_length += $gene_lengths->[$i];
    }
    $html .= sprintf $row_pattern,
        'Genes',
        $gene_count,
        $total_gene_length,
        $total_gene_length / $gene_count,
        $stats->median($gene_lengths);

    # Exons
    my $exon_lengths = $stats->exon_lengths;
    if (my $exon_count   = scalar @$exon_lengths) {
        my $total_exon_length = 0;
        for (my $i = 0; $i < @$exon_lengths; $i++) {
            $total_exon_length += $exon_lengths->[$i];
        }
        $html .= sprintf $row_pattern,
            'Exons',
            $exon_count,
            $total_exon_length,
            $total_exon_length / $exon_count,
            $stats->median($exon_lengths);
    }

    # Introns
    my $intron_lengths = $stats->intron_lengths;
    if (my $intron_count = scalar @$intron_lengths) {
        my $total_intron_length = 0;
        for (my $i = 0; $i < @$intron_lengths; $i++) {
            $total_intron_length += $intron_lengths->[$i];
        }
        $html .= sprintf $row_pattern,
            'Introns',
            $intron_count,
            $total_intron_length,
            $total_intron_length / $intron_count,
            $stats->median($intron_lengths);
    }

    $html .= '
</table>
';
    return $html;
}

sub html_table_transcripts_and_exons_per_gene {
    my( $self, $stats ) = @_;

    my $html = '
<table bgcolor="#cccccc" border="0" cellpadding="4" cellspacing="4">
    <tr>
        <td></td>
        <th bgcolor="white">Mean</th>
        <th bgcolor="white">Median</th>
    </tr>
';
    my $pattern = '
    <tr>
        <th bgcolor="white">%s</th>
        <td bgcolor="white" align="right">%.2f</td>
        <td bgcolor="white" align="right">%.2f</td>
    </tr>
';
    my $transcript_counts = $stats->transcript_counts;
    my $transcript_total = 0;
    foreach my $n (@$transcript_counts) {
        $transcript_total += $n;
    }
    $html .= sprintf $pattern,
        'Transcripts per gene',
        $transcript_total / scalar(@$transcript_counts),
        $stats->median($transcript_counts);

    my $exon_counts = $stats->exon_counts;
    my $exon_total = 0;
    foreach my $n (@$exon_counts) {
        $exon_total += $n;
    }
    $html .= sprintf $pattern,
        'Exons per gene',
        $exon_total / scalar(@$exon_counts),
        $stats->median($exon_counts);


    $html .= "</table>\n";
    return $html;
}

sub html_table_single_exon_genes_and_splice_counts {
    my( $self, $stats ) = @_;

    my $html = '
<table bgcolor="#cccccc" border="0" cellpadding="4" cellspacing="4">
    <tr>
        <td></td><th bgcolor="white">Count</th>
    </tr>
';

    my $row = '
    <tr>
    <th bgcolor="white">%s</th>
    <td bgcolor="white" align="right">%d</td>
    </tr>
';
    
    $html .= sprintf $row,
        'Single exon genes',
        $stats->single_exon_gene_count;
    
    my $sc = $stats->splice_counts;
    foreach my $splice (sort keys %$sc) {
        $html .= sprintf $row,
            "phase $splice splices",
            $sc->{$splice};
    }
    
    $html .= "</table>\n";
}

sub html_table_biggest_and_smallest_gene_and_exon {
    my( $self, $stats ) = @_;

    my $html = '
<table bgcolor="#cccccc" border="0" cellpadding="4" cellspacing="4">
    <tr>
        <td></td>
        <th bgcolor="white">Length</th>
        <th bgcolor="white">Name</th>
    </tr>
';

    my $row = '
    <tr>
        <th bgcolor="white">%s</th>
        <td bgcolor="white" align="right">%d</td>
        <td bgcolor="white">%s</td>
    </tr>
';
    
    foreach my $method (qw{
        longest_gene
        shortest_gene
        longest_exon
        shortest_exon
        longest_intron
        })
    {
        my $nv = $stats->$method or next;
        $html .= sprintf $row,
            $nv->label, $nv->value, $nv->name;
    }

    $html .= "</table>\n";
}

sub html_table_largest_transcript_and_exon_count {
    my( $self, $stats ) = @_;

    my $html = '
<table bgcolor="#cccccc" border="0" cellpadding="4" cellspacing="4">
    <tr>
        <td></td>
        <th bgcolor="white">Count</th><th bgcolor="white">Name</th>
    </tr>
';
    
    my $row = '
    <tr>
        <th bgcolor="white">%s</th>
        <td bgcolor="white" align="right">%d</td>
        <td bgcolor="white">%s</td>
    </tr>
';
    
    foreach my $method (qw{
        most_transcripts
        most_exons
        })
    {
        my $nv = $stats->$method or next;
        $html .= sprintf $row,
            $nv->label, $nv->value, $nv->name;
    }
    
    $html .= "</table>\n";
    
    return $html;
}


1;

__END__

=head1 NAME - Hum::Chromosome::VitalStatistics::Formatter::HTML

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

