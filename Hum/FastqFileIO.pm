
### Hum::FastqFileIO

package Hum::FastqFileIO;

use strict;
use warnings;

use strict;
use warnings;
use Carp;

use Hum::Sequence::DNA;
use Hum::FastaFileIO;

sub new {
    my ($pkg, $file) = @_;

    my $self = bless {}, $pkg;
    $self->file_handle($file) if $file;
    return $self;
}

sub file_handle {
    my ($self, $file) = @_;

    if ($file) {
        $self->{'_file_handle'} = Hum::FastaFileIO::process_file_argument(undef, $file);
    }
    return $self->{'_file_handle'};
}

sub read_all_sequences {
    my ($self) = @_;

    my (@all_seq);
    while (my $seq = $self->read_one_sequence) {
        push(@all_seq, $seq);
    }
    return @all_seq;
}

sub read_one_sequence {
    my ($self) = @_;

    local $/ = "\n";

    my $seq_str = '';
    my ($seq_obj);
    my $dna_line_count = 0;
    my $fh             = $self->file_handle;
  FASTQ: while (<$fh>) {
        chomp;
        if ($dna_line_count) {
            if (/^\+/) {

                # We've hit the start of the quality data
                my $qual_str;
                while ($dna_line_count) {
                    if (eof $fh) {
                        # Need to test for this or parser can hang trying to read from a closed filehandle
                        die "Error: reached end of fastq file with fewer quality lines than expected";
                    }
                    chomp($qual_str .= <$fh>);
                    $dna_line_count--;
                }
                $seq_obj->sequence_string($seq_str);

                # Translate the range 33..126 to 0..93  (ie: reduce the value of each character by 33)
                my $count = $qual_str =~ tr/\041-\176/\000-\135/;

                # Check that the quality string didn't have any values outside the range 33..126
                if ($count != length($qual_str)) {
                    confess sprintf "%d invalid values outside the range 33..126 in fastq quality string for sequence '%s'",
                      length($qual_str) - $count, $seq_obj->name;
                }

                $seq_obj->quality_string($qual_str);
                last FASTQ;
            }
            else {
                $dna_line_count++;
                $seq_str .= $_;
            }
        }
        elsif (my ($name, $desc) = /^\@\s*(\S+)\s*(.*)/) {
            $seq_obj = Hum::Sequence::DNA->new();
            $seq_obj->name($name);
            $seq_obj->description($desc) if $desc;
        }
        elsif ($seq_obj) {
            $seq_str = $_;
            $dna_line_count = 1;
        }
        else {
            confess "Error parsing fastq file. Line is: $_";
        }
    }
    return $seq_obj;
}

sub write_sequences {
    my ($self, @all_seq) = @_;

    my $fh = $self->file_handle;
    foreach my $seq_obj (@all_seq) {
        print $fh $seq_obj->fastq_string
          or confess "Error printing fastq : $!";
    }
}

1;

__END__

=head1 NAME - Hum::FastqFileIO

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

