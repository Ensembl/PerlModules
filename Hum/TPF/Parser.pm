
### Hum::TPF::Parser

package Hum::TPF::Parser;

use strict;
use Carp;
use Hum::TPF;
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
    my $tpf = Hum::TPF->new;
    while (<$fh>) {
        next if /^$/;
        my @line = split /\s+/, $_;
        confess "Bad line in TPF: $_" unless @line == 3;
        if ('GAP' eq uc $line[0]) {
            my( $type_str, $length_str ) = @line[1,2];
            my $gap = Hum::TPF::Row::Gap->new;
            if ($type_str eq 'CENTROMERE') {
                $gap->type(5);
            }
            elsif ($type_str =~ /type-([1234])/i) {
                $gap->type($1);
            }
            else {
                confess "Can't parse gap type from '$type_str'";
            }
            if ($length_str =~ /(\d+)/) {
                $gap->gap_length($1);
            }
            $tpf->add_Row($gap);
        } else {
            my( $acc, $intl, $contig_name ) = @line;
            my $row = Hum::TPF::Row::Clone->new;
            $row->accession($acc);
            $row->intl_clone_name($intl);
            $row->contig_name($contig_name);
            $tpf->add_Row($row);
        }
    }
    $self->{'_file'} = undef;
    return $tpf;
}

1;

__END__

=head1 NAME - Hum::TPF::Parser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

