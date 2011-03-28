
### Hum::AGP::Parser

package Hum::AGP::Parser;

use strict;
use warnings;
use Carp;
use Hum::AGP;
use Symbol 'gensym';

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub file {
    my( $self, $file ) = @_;
    
    if ($file) {
        my $type = ref($file);
        unless ($type and $type eq 'GLOB') {
            my $fh = gensym();
            open $fh, $file or confess "Can't read '$file' : $!";
            $file = $fh;
        }
        $self->{'_file'} = $file;
    }
    return $self->{'_file'};
}

my %type_phase = (
    'W' => 1,
    'D' => 1,

    'U' => 1,
    'A' => 2,
    'P' => 2,
    'F' => 3,
	'O' => 3,
    );

sub parse {
    my( $self ) = @_;

    local $/ = "\n";
    my $fh = $self->file or confess "file not set";
    my $agp = Hum::AGP->new;
    my( $chr_name );
    while (<$fh>) {
        chomp;
        next if /^\s*#/;
        next if /^\s*$/;
        my( $name,
            $chr_start, $chr_end,
            $row_num, $type,
            $rest ) = split /\s+/, $_, 6;
        $chr_name ||= $name;
        
        my( $row );
        if ($type eq 'N') {
            my( $length, $remark ) = split /\s+/, $rest, 2;
            $row = $agp->new_Gap;
            $row->chr_length($length);
            $row->remark($remark);
        } else {
            my( $acc_sv,
                $seq_start, $seq_end,
                $strand, $remark ) = split /\s+/, $rest, 5;
            $row = $agp->new_Clone;
            $row->accession_sv($acc_sv);
            $row->seq_start($seq_start);
            $row->seq_end($seq_end);
            $row->strand($strand eq '+' ? 1 : -1);
            my $phase = $type_phase{$type}
                or confess "No phase number for type '$type'";
            $row->htgs_phase($phase);
            $row->remark($remark);
        }
        $row->chr_start($chr_start);
        $row->chr_end($chr_end);
    }
    $self->{'_file'} = undef;
    
    confess "Got zero rows" unless $agp->fetch_all_Rows;
    $agp->chr_name($chr_name);
    return $agp;
}


1;

__END__

=head1 NAME - Hum::AGP::Parser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

