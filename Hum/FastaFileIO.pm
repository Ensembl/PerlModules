
### Hum::FastaFileIO

package Hum::FastaFileIO;

use strict;
use warnings;
use Carp;

use Hum::Sequence;
use Hum::Sequence::DNA;
use Hum::Sequence::Peptide;
use Hum::StringHandle;

sub new {
    my ($pkg, $file) = @_;

    my $self = bless {}, $pkg;
    $self->file_handle($file) if $file;
    return $self;
}

sub new_DNA_IO {
    my ($pkg, $file) = @_;

    my $self = $pkg->new($file);
    $self->sequence_class('Hum::Sequence::DNA');
    return $self;
}

sub new_DNA_Quality_IO {
    my ($pkg, $file, $quality_file) = @_;

    unless ($quality_file) {
        if (ref($file)) {
            confess "Can't auto generate quality file name from '$file'";
        }
        else {
            $quality_file = "$file.qual";
        }
    }

    my $self = $pkg->new_DNA_IO($file);
    $self->sequence_class('Hum::Sequence::DNA');

    $self->quality_file_handle($quality_file);

    return $self;
}

sub new_Peptide_IO {
    my ($pkg, $file) = @_;

    my $self = $pkg->new($file);
    $self->sequence_class('Hum::Sequence::Peptide');
    return $self;
}

sub sequence_class {
    my ($self, $sequence_class) = @_;

    if ($sequence_class) {
        $self->{'_sequence_class'} = $sequence_class;
    }
    return $self->{'_sequence_class'} || 'Hum::Sequence';
}

sub _next_line {
    my ($self) = @_;

    if (my $line = $self->{'_last_line'}) {
        $self->{'_last_line'} = undef;
        return $line;
    }
    else {
        my $fh = $self->{'_file_handle'} || return;
        if ($line = <$fh>) {
            return $line;
        }
        else {
            $self->{'_file_handle'} = undef;
            return;
        }
    }
}

sub _push_back {
    my ($self, $line) = @_;

    $self->{'_last_line'} = $line;
}

sub _last_quality_line {
    my ($self, $_last_quality_line) = @_;

    if ($_last_quality_line) {
        $self->{'__last_quality_line'} = $_last_quality_line;
    }
    else {
        my $last = $self->{'__last_quality_line'};
        $self->{'__last_quality_line'} = undef;
        return $last;
    }
}

sub process_file_argument {
    my ($self, $file) = @_;

    my $type = ref($file);
    if ($type eq 'GLOB') {
        return $file;
    }
    elsif ($type eq 'SCALAR') {
        return Hum::StringHandle->new($file);
    }
    else {
        open my $fh, $file or confess "Can't open file '$file' : $!";
        return $fh;
    }
}

sub file_handle {
    my ($self, $file) = @_;

    if ($file) {
        $self->{'_file_handle'} = $self->process_file_argument($file);
    }
    return $self->{'_file_handle'};
}

sub quality_file_handle {
    my ($self, $file) = @_;

    if ($file) {
        $self->{'_quality_file_handle'} = $self->process_file_argument($file);
    }
    return $self->{'_quality_file_handle'};
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

    my $class = $self->sequence_class;

    my $seq_string = '';
    my ($seq_obj);
    while ($_ = $self->_next_line) {
        if (my ($name, $desc) = /^>\s*(\S+)\s*(.*)/) {

            #warn "Got '$name'\n";
            if ($seq_obj) {
                $self->_push_back($_);
                last;
            }
            else {
                $seq_obj = $class->new();
                $seq_obj->name($name);
                $seq_obj->description($desc) if $desc;
            }
        }
        else {
            chomp;
            $seq_string .= $_;
        }
    }
    return unless $seq_obj;
    $seq_obj->sequence_string($seq_string);

    # Read quality values if we've got a handle to a quality file
    if ($self->quality_file_handle) {
        $self->_add_quality_string($seq_obj);
    }

    return $seq_obj;
}

sub _add_quality_string {
    my ($self, $seq_obj) = @_;

    my $name = $seq_obj->name;
    my $qfh  = $self->quality_file_handle
      or confess "No quality file handle";

    my $first_line = $self->_last_quality_line || <$qfh>;
    my ($q_name) = $first_line =~ /^>(\S+)/
      or die "Invalid first line '$first_line'";
    confess "Name in quality file '$q_name' doesn't match name in fasta file '$name'"
      unless $q_name eq $name;

    my $qual_string = '';
    while (<$qfh>) {
        if (/^>/) {
            $self->_last_quality_line($_);
            last;
        }
        else {
            $qual_string .= pack 'C*', split;
        }
    }
    $seq_obj->quality_string($qual_string);
}

sub write_sequences {
    my ($self, @all_seq) = @_;

    my $fh  = $self->file_handle;
    my $qfh = $self->quality_file_handle;
    foreach my $seq_obj (@all_seq) {
        print $fh $seq_obj->fasta_string
          or confess "Error printing fasta : $!";

        if ($qfh) {
            print $qfh $seq_obj->fasta_quality_string
              or confess "Error printing fasta : $!";
        }
    }
}

1;

__END__

=head1 NAME - Hum::FastaFileIO

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

