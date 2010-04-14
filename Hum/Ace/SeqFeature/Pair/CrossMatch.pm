
### Hum::Ace::SeqFeature::Pair::CrossMatch

package Hum::Ace::SeqFeature::Pair::CrossMatch;

use strict;
use warnings;
use Hum::Ace::SeqFeature::Pair;
use vars '@ISA';

@ISA = ('Hum::Ace::SeqFeature::Pair');

sub algorithm {
    return 'CrossMatch';
}

sub percent_substitution {
    my ($self, $percent_substitution) = @_;

    if (defined $percent_substitution) {
        $self->{'_percent_substitution'} = $percent_substitution;
    }
    return $self->{'_percent_substitution'};
}

sub percent_insertion {
    my ($self, $percent_insertion) = @_;

    if (defined $percent_insertion) {
        $self->{'_percent_insertion'} = $percent_insertion;
    }
    return $self->{'_percent_insertion'};
}

sub percent_deletion {
    my ($self, $percent_deletion) = @_;

    if (defined $percent_deletion) {
        $self->{'_percent_deletion'} = $percent_deletion;
    }
    return $self->{'_percent_deletion'};
}

sub percent_identity {
    my ($self) = @_;

    return 100 - $self->percent_substitution - $self->percent_insertion - $self->percent_deletion;
}

sub alignment_string {
    my ($self, $string) = @_;

    if ($string) {
        $self->{'_alignment_string'} = $string;
    }
    return $self->{'_alignment_string'};
}

sub pretty_alignment_string {
    my ($self) = @_;

    my $str = $self->alignment_string
      or return;

    my $new = '';
    my (@block);
    while ($str =~ /(.*\n)/mg) {
        $_ = $1;
        if (/^[C ] \S+\s+\d+ \S+ \d+/) {
            push(@block, $_);
            if (@block == 3) {

                # Change the order of the lines in
                # the alignment block.
                $new .= join('', @block[ 0, 2, 1 ]);
                @block = ();
            }
        }
        elsif (@block) {
            push(@block, $_);
        }
        else {
            $new .= $_;
        }
    }

    return $new;
}

sub cigar_string {
    my ($self, $cigar) = @_;

    if ($cigar) {
        $self->{'_cigar_string'} = $cigar;
    }
    elsif (!$self->{'_cigar_string'}) {
        if ($self->alignment_string) {

            # Automatically generate cigar string if we have the data
            require Bio::Search::HSP::GenericHSP;
            require Bio::EnsEMBL::Utils::CigarString;
            my ($qry_aln, $hit_aln) = $self->parse_align_string;
            # warn "Got align strings:\n$qry_aln\n$hit_aln\n";
            $self->{'_cigar_string'} = $self->make_cigar_string_from_align_strings($qry_aln, $hit_aln);
        }
    }
    return $self->{'_cigar_string'};
}

sub parse_align_string {
    my ($self) = @_;

    my $qry_aln = '';
    my $hit_aln = '';
    my $count   = 0;

    foreach (split(/\n/, $self->alignment_string)) {

        #  AP003795.2           1 AAGCTTCCTGTGATGCTGGGGTGGAAGCTGTACTCCTCCCAGCCCTTCTC 50
        # there is one field before ACC which is used for revcomp, if applied

        my @fields = split(/\s+/, $_);
        next if $_ !~ /.*\.\d+.*[ATCG-]*/;

        $count++;

        if ($count % 2 == 0) {
            $hit_aln .= $fields[3];

            #print "S: ", length $fields[3], "\n";
            #print "S: ", $fields[3], "\n";
        }
        else {
            $qry_aln .= $fields[3];

            #print "Q: ", length $fields[3], "\n";
            #print "Q: ", $fields[3], "\n";
        }
    }

    #-----------------------------------------------------------------------------------
    # crossmatch hack
    # NOTE: crossmatch displays the alignment differently as the match coords line
    # eg
    # identity  query        start    end    subject     start    end    strand
    #--------  ----------------------------- -------------------------------------
    # 98.88%    AP003796.2   1        90648  BX640404.2  1        90774  -

    #C AP003796.2       90648 AAGCTTGTACAGAGGGGAAAAATAATTGAGGATGGTGTTATTAGTGGAAT 90599
    #  BX640404.2           1 AAGCTTGTACAGAGGGGAAAAATAATTGAGGATGGTGTTATTAGTGGAAT 50
    #-----------------------------------------------------------------------------------

    if ($self->seq_strand != $self->hit_strand) {

        # revcomp both query_alignment and hit_alignment
        $qry_aln = $self->_revcomp($qry_aln);
        $hit_aln = $self->_revcomp($hit_aln);
    }

    return ($qry_aln, $hit_aln);
}

sub _revcomp {
    my ($self, $str) = @_;

    my $seq = Hum::Sequence::DNA->new;
    $seq->sequence_string($str);
    return $seq->reverse_complement->sequence_string;
}

sub make_cigar_string_from_align_strings {
    my ($self, $qry_aln, $hit_aln) = @_;

    my $hsp = Bio::Search::HSP::GenericHSP->new(
        -score      => $self->score,
        -hsp_length => length $qry_aln,

        # query gapped sequence portion of the HSP
        -query_seq    => $qry_aln,
        -query_name   => $self->seq_name,
        -query_start  => $self->seq_start,
        -query_end    => $self->seq_end,
        -query_length => $self->seq_Sequence->sequence_length,

        # hit   gapped sequence portion of the HSP
        -hit_seq    => $hit_aln,
        -hit_name   => $self->hit_name,
        -hit_start  => $self->hit_start,
        -hit_end    => $self->hit_end,
        -hit_length => $self->hit_Sequence->sequence_length,

        # so that we will not get
        # MSG: Did not defined the number of conserved matches in the HSP assuming conserved == identical (0)
        # assign 0 to both identical and conserved for DNA comparison
        -identical => 0,
        -conserved => 0
    );

    return Bio::EnsEMBL::Utils::CigarString->generate_cigar_string_by_hsp($hsp);
}

1;

__END__

=head1 NAME - Hum::Ace::SeqFeature::Pair::CrossMatch

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

