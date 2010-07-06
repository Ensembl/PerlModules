
### Hum::Analysis::Parser::Epic

package Hum::Analysis::Parser::Epic;

use strict;
use warnings;
use Carp;
use Hum::Ace::SeqFeature::Pair::Epic;
use File::Path 'rmtree';

sub new {
    my ($pkg) = @_;

    return bless {}, $pkg;
}

sub get_all_Features {
    my ($self) = @_;

    my $all = [];
    while (my $f = $self->next_Feature) {
        push(@$all, $f);
    }
    return $all;
}

sub next_Feature {
    my ($self) = @_;

    my $fh = $self->results_filehandle or return;
    if (my $line = <$fh>) {
        return $self->new_Feature_from_epic_line($line);
    }
    else {
        $self->close_results_filehandle;
        return;
    }
}

sub new_Feature_from_epic_line {
    my ($self, $line) = @_;

    chomp $line;

    # 31337M  31337   100.00  AC171462.2      11238   42574   AC118196.12     189918  158582
    my (
        $cigar,
        $aln_length,
        $percent_identity,

        $seq_name,
        $seq_start,
        $seq_end,

        $hit_name,
        $hit_start,
        $hit_end,
    ) = split /\s+/, $line;

    my $seq_strand = 1;
    if ($seq_start > $seq_end) {
        ($seq_start, $seq_end) = ($seq_end, $seq_start);
        $seq_strand = -1;
    }

    my $hit_strand = 1;
    if ($hit_start > $hit_end) {
        ($hit_start, $hit_end) = ($hit_end, $hit_start);
        $hit_strand = -1;
    }

    my $count_D = 0;
    while ($cigar =~ /(\d*)D/g) {
        $count_D += $1 || 1;
    }
    my $percent_deletion = 100 * ($count_D / $aln_length);

    my $count_I = 0;
    while ($cigar =~ /(\d*)I/g) {
        $count_I += $1 || 1;
    }
    my $percent_insertion = 100 * ($count_I / $aln_length);

    # Substitutions are not recorded in the CIGAR line, but we know the overall
    # percent identity, so we can work it out by taking away the deletions
    # and insertions.
    my $percent_substitution = (100 - $percent_identity) - ($percent_deletion + $percent_insertion);

    my $feature = Hum::Ace::SeqFeature::Pair::Epic->new();

    $feature->cigar_string($cigar);
    $feature->alignment_length($aln_length);

    # These values are returned by cross_match, but not by blast (which underlies epic)
    # The oracle database has fields for them, so I've made an attempt to calculate
    # them.  Not sure if this is correct!
    $feature->percent_substitution($percent_substitution);
    $feature->percent_insertion($percent_insertion);
    $feature->percent_deletion($percent_deletion);

    $feature->percent_identity($percent_identity);

    $feature->seq_name($seq_name);
    $feature->seq_start($seq_start);
    $feature->seq_end($seq_end);
    $feature->seq_strand($seq_strand);

    $feature->hit_name($hit_name);
    $feature->hit_start($hit_start);
    $feature->hit_end($hit_end);
    $feature->hit_strand($hit_strand);

    return $feature;
}

sub results_filehandle {
    my ($self, $results_filehandle) = @_;

    if ($results_filehandle) {
        $self->{'_results_filehandle'} = $results_filehandle;
    }
    return $self->{'_results_filehandle'};
}

sub close_results_filehandle {
    my ($self) = @_;

    if (my $fh = $self->{'_results_filehandle'}) {
        close($fh) or confess "Error from epic filehandle exit($?)";
    }

    $self->{'_results_filehandle'} = undef;
}

sub temporary_directory {
    my ($self, $temporary_directory) = @_;

    if ($temporary_directory) {
        $self->{'_temporary_directory'} = $temporary_directory;
    }
    return $self->{'_temporary_directory'};
}

sub DESTROY {
    my ($self) = @_;

    if (my $dir = $self->temporary_directory) {

        # warn "Not removing '$dir'"; return;
        rmtree($dir);
    }
}

1;

__END__

=head1 NAME - Hum::Analysis::Parser::CrossMatch

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

