
### Hum::Chromosome::VitalStatistics::Formatter::Excel

package Hum::Chromosome::VitalStatistics::Formatter::Excel;

use strict;
use Spreadsheet::WriteExcel;
use base 'Hum::Chromosome::VitalStatistics::Formatter';

sub make_report {
    my( $self, @stats_list ) = @_;

    my $fh = $self->file;
    
    my $book = Spreadsheet::WriteExcel->new($fh);
    $self->setup_formats($book);

    foreach my $stats (@stats_list) {
        $self->write_stats_sheet($stats, $book->addworksheet);
    }
    
    $book->close;
    close($fh);
}

sub setup_formats {
    my( $self, $book ) = @_;
    
    my $cache = $self->{'_formats_cache'} = {};
    $cache->{'nearest_int'} = $book->addformat(
        'num_format'    => '0',
        );
    $cache->{'thousands'} = $book->addformat(
        'num_format'    => '#,##0',
        );
    $cache->{'two_decimal'} = $book->addformat(
        'num_format'    => '0.00',
        );
}

sub get_format {
    my( $self, $name ) = @_;
    
    confess "Missing format name argument" unless $name;
    return $cache->{'_formats_cache'}{$name}
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
    
    my $row = 0;
    my $col = 0;
    $sheet->write_string(  $row, $col, $self->head);
    $sheet->write_string(++$row, $col, $self->note);
    $self->current_row_col($row, $col);
    
    $sheelf->write_gene_exon_intron_counts($stats, $sheet);
}

sub write_gene_exon_intron_counts {
    my( $stats, $sheet ) = @_;

    my ($row, $col) = $self->next_row_col;
    
    
}

1;

__END__

=head1 NAME - Hum::Chromosome::VitalStatistics::Formatter::Excel

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

