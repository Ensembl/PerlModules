
### Hum::AGP::Parser

package Hum::AGP::Parser;

use strict;
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

sub parse {
    my( $self ) = @_;

    local $/ = "\n";
    my $fh = $self->file or confess "file not set";
    my $agp = Hum::AGP->new;
    while (<$fh>) {
        chomp;
        next if /^\s*#/;
        next if /^\s*$/;
        my( $name,
            $chr_start, $chr_end,
            $row_num, $row_type,
            $acc_sv, $rest ) = split /\s+/, $_, 7;
        unless ($agp->name) {
            $agp->name($name);
        }
        
        my( $row );
        if ($type eq 'N') {
            my( $length, $remark ) = split /\s+/, $rest, 2;
            $row = $agp->new_Gap;
            $row->chr_length($length);
            $row->remark($remark);
        } else {
            my( $acc_sv,
                $seq_start, $seq_end,
                $strand ) = split /\s+/, $rest, 4;
            $row = $agp->new_Clone;
            $row->seq_start($seq_start);
            $row->seq_end($seq_end);
            $row->strand($strand eq '+' ? 1 : -1);
            $row->is_finished($row_type eq 'F' ? 1 : 0);
        }
    }
    $self->{'_file'} = undef;
    
    confess "Got zero rows" unless $agp->fetch_all_Rows;
    
    return $agp;
}


1;

__END__

=head1 NAME - Hum::AGP::Parser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

