
### Hum::Analysis::Parser::CrossMatch

package Hum::Analysis::Parser::CrossMatch;

use strict;
use warnings;
use Carp;
use Hum::Ace::SeqFeature::Pair::CrossMatch;

use base 'Hum::Analysis::Parser';

sub next_Feature {
    my ($self) = @_;

    my $feature = $self->_current_feature;
    my $aln_str = '';
    my $fh      = $self->results_filehandle or return ($feature);
    while (<$fh>) {
        if (/\(\d+\)/) {
            my $new_feature = $self->new_Feature_from_coordinate_line($_)
              or confess "No new feature returned";
            if ($feature) {
                $self->_current_feature($new_feature);
                return $feature;
            }
            else {
                $feature = $new_feature;
            }
        }
        elsif (/^Transitions/) {

            # This line appears at the end of alignment blocks
            $feature->alignment_string($aln_str);
        }
        elsif ($feature) {
            $aln_str .= $_;
        }
    }

    $self->close_results_filehandle;

    return $feature;
}

sub _current_feature {
    my ($self, $feature) = @_;

    if ($feature) {
        $self->{'_current_feature'} = $feature;
    }
    elsif ($feature = $self->{'_current_feature'}) {
        $self->{'_current_feature'} = undef;
        return $feature;
    }
}

sub new_Feature_from_coordinate_line {
    my ($self, $line) = @_;

    my $feature = Hum::Ace::SeqFeature::Pair::CrossMatch->new();
    $feature->seq_strand(1);

    # Strip parentheses, asterisks and leading space from the line
    $line =~ s/[\(\)\*]//g;
    $line =~ s/^\s+//;

    # Split into fields on white space
    my @data = split /\s+/, $line;

    $feature->score($data[0]);
    $feature->percent_substitution($data[1]);
    $feature->percent_insertion($data[2]);
    $feature->percent_deletion($data[3]);
    $feature->seq_name($data[4]);
    $feature->seq_start($data[5]);
    $feature->seq_end($data[6]);

    if (@data == 12) {
        $feature->hit_strand(1);

        #    0     1    2    3         4        5     6        7           8        9    10  11
        # 1964  0.05 0.00 0.20  AL603831        1  2004 (177751)    AL589988    72574 74573 (0)
        $feature->hit_name($data[8]);
        $feature->hit_start($data[9]);
        $feature->hit_end($data[10]);
    }
    elsif (@data == 13) {
        $feature->hit_strand(-1);

        #    0     1    2    3         4        5     6        7  8        9        10    11    12
        #  130 13.67 0.67 2.67  AL603831     4244  4543 (175212)  C AL589988   (72333)  2240  1947
        $feature->hit_name($data[9]);
        $feature->hit_start($data[12]);
        $feature->hit_end($data[11]);
    }
    else {
        confess "Unexpected match line format '$_' (", scalar(@data), " elements)";
    }

    return $feature;
}

sub crossmatch_log_file {
    my ($self, $crossmatch_log_file) = @_;

    if ($crossmatch_log_file) {
        $self->{'_crossmatch_log_file'} = $crossmatch_log_file;
    }
    return $self->{'_crossmatch_log_file'};
}

sub DESTROY {
    my ($self) = @_;

    if (my $log = $self->crossmatch_log_file) {
        unlink($log);
    }
    $self->SUPER::DESTROY();
}

1;

__END__

=head1 NAME - Hum::Analysis::Parser::CrossMatch

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

