
### Hum::Sequence

package Hum::Sequence;

use strict;
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
    
    my $seq_string = $seq_obj->sequence_string;
    my $sub_seq_string = substr($seq_string, ($x - 1), ($y - $x + 1));
    
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
        or confess "No sequence";
    my $fasta_string = ">$name";
    $fasta_string .= "  $desc" if $desc;
    $fasta_string .= "\n";
    while ($seq =~ /(.{1,60})/g) {
        $fasta_string .= $1 . "\n";
    }
    return $fasta_string;
}

1;

__END__

=head1 NAME - Hum::Sequence

=head1 DESCRIPTION

Baseclass for Hum::Sequence lightweight sequence
modules.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

