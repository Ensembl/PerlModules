
### Hum::AGP

package Hum::AGP;

use strict;
use Carp;
use Hum::AGP::Row::Clone;
use Hum::AGP::Row::Gap;

sub new {
    my( $pkg ) = @_;

    return bless {
        '_rows' => [],
        }, $pkg;
}

sub new_Clone {
    my( $self ) = @_;
    
    my $clone = Hum::AGP::Row::Clone->new;
    push(@{$self->{'_rows'}}, $clone);
    return $clone;
}

sub new_Gap {
    my( $self ) = @_;
    
    my $gap = Hum::AGP::Row::Gap->new;
    push(@{$self->{'_rows'}}, $gap);
    return $gap;
}

sub chr_name {
    my( $self, $chr_name ) = @_;
    
    if ($chr_name) {
        $self->{'_chr_name'} = $chr_name;
    }
    return $self->{'_chr_name'} or confess "chr_name not set";
}

sub fetch_all_Rows {
    my( $self ) = @_;

    return @{$self->{'_rows'}};
}

sub process_TPF {
    my( $self, $tpf ) = @_;

    my @rows = $tpf->fetch_all_Rows;
    my $contig = [];
    for (my $i = 0; $i < @rows; $i++) {
        my $row = $rows[$i];
        if ($row->is_gap) {
            $self->_process_contig(@$contig) if @$contig;
            $contig = [];
            my $gap = $self->new_Gap;
            $gap->gap_length($row->gap_length);
        } else {
            push(@$contig, $row);
        }
    }
    $self->_process_contig($contig) if @$contig;
}

sub _process_contig {
    my( $self, $contig ) = @_;
    
    for (my $i = 0; $i < @$contig; $i++) {
        
    }
}

sub string {
    my( $self ) = @_;
    
    my $str = '';
    foreach my $row ($self->fetch_all_Rows) {
        $str .= join("\t", $row->elements) . "\n";
    }
    return $str;
}

1;

__END__

=head1 NAME - Hum::AGP

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

