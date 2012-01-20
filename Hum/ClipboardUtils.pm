
### Hum::ClipboardUtils

package Hum::ClipboardUtils;

use strict;
use warnings;
use base 'Exporter';

our @EXPORT_OK = qw{
    text_is_zmap_clip
    accessions_from_text
    integers_from_text
    $magic_evi_name_matcher
    magic_evi_name_match
    };

our $magic_evi_name_matcher = qr{
    ([A-Za-z]{2}:)?       # Optional prefix
    (
                          # Something that looks like an accession:
        [A-Z]+\d{5,}      # one or more letters followed by 5 or more digits
        |                 # or, for TrEMBL,
        [A-Z]\d[A-Z\d]{4} # a capital letter, a digit, then 4 letters or digits.
    )
    (\-\d+)?              # Optional VARSPLICE suffix found on Uniprot isoforms
    (\.\d+)?              # Optional .SV
}x;

my $posn_int = qr{-?(\d+)};

sub text_is_zmap_clip {
    my ($text) = @_;

    if ($text =~ /^"$magic_evi_name_matcher"\s+$posn_int\s+$posn_int\s+\(\d+\)/m) {
        return 1;
    } else {
        return 0;
    }
}

sub accessions_from_text {
    my ($text) = @_;

    my (%seen, @acc);
    while ($text =~ /$magic_evi_name_matcher/g) {
        # Strip out the prefix
        my ($acc, $isoform, $sv) = ($2, $3, $4);
        my $name = join('', $acc, $isoform || '', $sv || '');
        unless ($seen{$name}) {
            $seen{$name} = 1;
            push @acc, $name;
        }
    }
    return @acc;
}

sub integers_from_text {
    my ($text) = @_;

    #warn "Trying to parse: [$text]\n";

    my (@ints);

    # Zmap DNA selection examples:
    #
    # >88325-88411 DNA  87 bp
    # cagctcatttcttgcaaatcacttcttttctctctcgtgctctgtccctt
    # tgtagatttgaataaatgtccctccttcaccattggt
    #
    # >-88323--88222 DNA  102 bp
    # ttactttacctcacattcaggcatgcctataaaatgacagccttggtagg
    # cagcaaccgcttgtgttaacgcagacgggtctgccagacctgccacacac
    # ag
    if (@ints = $text =~ />$posn_int-$posn_int DNA/) {
        if ($ints[0] == $ints[1]) {
            # user clicked on single base pair
            @ints = ($ints[0]);
        }
    }
    else {
        # Zmap clipboard examples:
        #
        # "Em:AB056152.1"    72602 72793 (192)
        # "Em:AB056152.1"    87317 87472 (156)
        # "Em:CR600548.1"    -145886 -145723 (164)
        # "Em:CR600548.1"    -144505 -144330 (176)

        unless (@ints = $text =~ /^\S+\s+$posn_int\s+$posn_int\s+\(\d+\)/mg) {
            # or just get all the integers
            @ints = grep { !/\./ } $text =~ /\b([\.\d]+)\b/g;
        }
    }
    return @ints;
}

# Returns (prefix, accession, sv, accession-without-splice-variant, splice-variant)
# NB prefix, sv and splice-variant are numeric, NOT decorated with ':', '.' or '-' respectively
#
# Used by mg13's vega evidence script (not checked in as of 14/03/2011).
# Tested by PerlModules/t/HumClipboardUtils.t
#
sub magic_evi_name_match {
    my $text = shift;

    my ($prefix, $acc_only, $splv, $sv) = ($text =~ /
                                                     ^\s*                      # Optional leading whitespace
                                                     ${magic_evi_name_matcher} # see above
                                                     \s*$                      # Optional trailing whitespace
                                                    /ox);

    $prefix =~ s/:$//  if $prefix; # trim trailing :
    $splv   =~ s/^-//  if $splv;   # trim leading -
    $sv     =~ s/^\.// if $sv;     # trim leading .

    my $acc = $acc_only;
    $acc .= "-$splv" if $splv;

    return ($prefix, $acc, $sv, $acc_only, $splv);
}

1;

__END__

=head1 NAME - Hum::ClipboardUtils

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

