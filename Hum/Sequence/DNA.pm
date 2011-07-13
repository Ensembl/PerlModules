
### Hum::Sequence::DNA

package Hum::Sequence::DNA;

use strict;
use warnings;
use vars '@ISA';
use Carp;
use Hum::Sequence;

@ISA = 'Hum::Sequence';

sub quality_string {
    my( $seq_obj, $quality_string ) = @_;
    
    if ($quality_string) {
        my $seq_length = $seq_obj->sequence_length;
        my $quality_length = length($quality_string);
        unless ($seq_length == $quality_length) {
            confess("quality string length '$quality_length' doesn't match sequence length '$seq_length'");
        }
        $seq_obj->{'_quality_string'} = $quality_string;
    }
    return $seq_obj->{'_quality_string'};
}

{
    my $N = 30; # Number of quality values per line
    my $pat = 'A3' x $N;

    sub fasta_quality_string {
        my( $seq_obj ) = @_;

        my $name = $seq_obj->name
            or confess "No name";
        my $desc = $seq_obj->description;
        my $qual = $seq_obj->quality_string
            or confess "No quality";
        my $quality_string = ">$name";
        $quality_string .= "  $desc" if $desc;
        $quality_string .= "\n";
        
        my $qual_length = length($qual);
        
        my $whole_lines = int( $qual_length / $N );
        for (my $l = 0; $l < $whole_lines; $l++) {
            my $offset = $l * $N;
            $quality_string .= pack($pat, unpack('C*', substr($qual, $offset, $N))). "\n";
        }
        
        if (my $r = $qual_length % $N) {
            my $pat = 'A3' x $r;
            my $offset = $whole_lines * $N;
            $quality_string .= pack($pat, unpack('C*', substr($qual, $offset))). "\n";
        }

        return $quality_string;
    }
}

sub fastq_string {
    my( $seq_obj ) = @_;
    
    my $name = $seq_obj->name
        or confess "No name";
    my $desc = $seq_obj->description;
    my $seq  = $seq_obj->sequence_string
        or confess "No sequence in '$name'";
    my $qual = $seq_obj->quality_string
        or confess "No quality in '$name'";

    my $fastq_string = "\@$name";
    $fastq_string .= "  $desc" if $desc;
    $fastq_string .= "\n";
    while ($seq =~ /(.{1,60})/g) {
        $fastq_string .= $1 . "\n";
    }

    my $count = $qual =~ tr/\000-\135/\041-\176/;
    if ($count != $seq_obj->sequence_length) {
        confess sprintf("Sequence '%s' has %d values in quality string outside range 0-93", $name, $count);
    }
    $fastq_string .= "+\n";
    while ($qual =~ /(.{1,60})/g) {
        $fastq_string .= $1 . "\n";
    }
    
    return $fastq_string;
}

sub reverse_complement {
    my( $seq_obj ) = @_;
    
    my $class = ref($seq_obj);
    my $rev_obj = $class->new();
    
    # Copy across the name and description to the new object
    $rev_obj->name($seq_obj->name);
    $rev_obj->description($seq_obj->description);
    
    # Reverse complement the DNA sequence
    my $seq = $seq_obj->sequence_string;
    $seq = reverse($seq);
    $seq =~ tr{acgtrymkswhbvdnACGTRYMKSWHBVDN}
              {tgcayrkmswdvbhnTGCAYRKMSWDVBHN};
    $rev_obj->sequence_string($seq);
    
    # Reverse the quality string if present
    if (my $qual = $seq_obj->quality_string) {
        $qual = reverse $qual;
        $rev_obj->quality_string($qual);
    }
    
    return $rev_obj;
}

sub ace_string {
    my( $seq_obj ) = @_;
    
    my $name = $seq_obj->name
        or confess "No name";
    my $seq  = $seq_obj->sequence_string
        or confess "No sequence";
    
    my $ace_string =
        qq{\nSequence "$name"\n}
           . qq{\nDNA "$name"\n};
    
    while ($seq =~ /(.{1,60})/g) {
        $ace_string .= $1 . "\n";
    }
    $ace_string .= "\n";
    
    return $ace_string;
}

1;

__END__

=head1 NAME - Hum::Sequence::DNA

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

