
### Hum::Analysis::Parser::AXT

package Hum::Analysis::Parser::AXT;

use strict;
use warnings;
use Carp;

use Hum::Ace::SeqFeature::Pair;

use base 'Hum::Analysis::Parser';

=pod

Example AXT fromat output from lastz:

    # lastz.v1.01.25 --identity=95 --step=20 --match=1,5 --format=axt 
    #
    # hsp_threshold      = 30
    # gapped_threshold   = 30
    # x_drop             = 23
    # y_drop             = 46
    # gap_open_penalty   = 17
    # gap_extend_penalty = 2
    #        A    C    G    T
    #   A    1   -5   -5   -5
    #   C   -5    1   -5   -5
    #   G   -5   -5    1   -5
    #   T   -5   -5   -5    1
    0 CR788236.6 3500 3583 CR788236.7 75457 75540 + 60
    CACATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATA
    CACATATATATATATATATATATACATACATATATATATATATATATATACATATACATATATATATATATATATATATATATA

    1 CR788236.6 3500 3578 CR788236.7 75713 75791 + 67
    CACATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATATAT
    CACATATATATATATAAACATATATATATATATATATATATATATATATATATATATATATATATATATATATATATAT

    2 CR788236.6 3501 3557 CR788236.7 75306 75362 + 57
    ACATATATATATATATATATATATATATATATATATATATATATATATATATATATA
    ACATATATATATATATATATATATATATATATATATATATATATATATATATATATA

=cut

sub next_Feature {
    my ($self) = @_;

    my $fh = $self->results_filehandle or return;
    while (<$fh>) {
        next if /^#/;
        next if /^$/;
        if (/^\d/) {
            my $feature = $self->new_Feature_from_fh($_, $fh)
              or confess "No new feature returned";
            return $feature;
        }
    }

    $self->close_results_filehandle;

    return;
}

sub new_Feature_from_fh {
    my ($self, $line, $fh) = @_;

    my ($feature_i, $seq_name, $seq_start, $seq_end, $hit_name, $hit_start, $hit_end, $hit_strand, $score) = split /\s+/, $line;
    chomp( my $seq_align_str = lc <$fh> );
    chomp( my $hit_align_str = lc <$fh> );

    my $feature = Hum::Ace::SeqFeature::Pair->new;

    $feature->seq_name($seq_name);
    $feature->seq_start($seq_start);
    $feature->seq_end($seq_end);
    $feature->seq_strand(1);

    $feature->hit_name($hit_name);
    $feature->hit_start($hit_start);
    $feature->hit_end($hit_end);
    $feature->hit_strand($hit_strand eq '+' ? 1 : -1);

    my $align_length = length($seq_align_str);
    my $indel_count = 0;
    my $subst_count = 0;
    for (my $i = 0; $i < $align_length; $i++) {
        my $s = substr($seq_align_str, $i, 1);
        my $h = substr($hit_align_str, $i, 1);
        if ($s eq '-' or $h eq '-') {
            $indel_count++;
        }
        elsif ($s ne $h) {
            $subst_count++;
        }
    }
    my $exact_matches = $align_length - $indel_count - $subst_count;
    $feature->percent_identity(100 * $exact_matches / $align_length);

    return $feature;
}


1;

__END__

=head1 NAME - Hum::Analysis::Parser::AXT

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

