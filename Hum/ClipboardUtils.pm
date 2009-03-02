
### Hum::ClipboardUtils

package Hum::ClipboardUtils;

use strict;
use base 'Exporter';

our @EXPORT_OK = qw{
    text_is_zmap_clip
    integers_from_text
    evidence_type_and_name_from_text
    $magic_evi_name_matcher
    };

our $magic_evi_name_matcher = qr{
    ([A-Za-z]{2}:)?       # Optional prefix
    (
                          # Something that looks like an accession:
        [A-Z]+\d{5,}      # one or more letters followed by 5 or more digits
        |                 # or, for TrEMBL,
        [A-Z]\d[A-Z\d]{4} # a capital letter, a digit, then 4 letters or digits.
    )
    (\-\d+)?              # Optional VARSPLICE suffix
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
            @ints = grep !/\./, $text =~ /\b([\.\d]+)\b/g;
        }
    }
    return @ints;
}

{
    my %column_type = (
        EST             => 'EST',
        vertebrate_mRNA => 'cDNA',
        BLASTX          => 'Protein',
        SwissProt       => 'Protein',
        TrEMBL          => 'Protein',
        OTF_EST			=> 'EST',
        OTF_mRNA		=> 'cDNA',
        OTF_Protein		=> 'Protein',
    );

    sub evidence_type_and_name_from_text {
        my ($ace, $text) = @_;

        #warn "Trying to parse: [$text]\n";

        # Sequence:Em:BU533776.1    82637 83110 (474)  EST_Human 99.4 (3 - 478) Em:BU533776.1
        # Sequence:Em:AB042555.1    85437 88797 (3361)  vertebrate_mRNA 99.3 (709 - 4071) Em:AB042555.1
        # Protein:Tr:Q7SYC3    75996 76703 (708)  BLASTX 77.0 (409 - 641) Tr:Q7SYC3
        # Protein:"Sw:Q16635-4.1"    14669 14761 (93)  BLASTX 100.0 (124 - 154) Sw:Q16635-4.1

        if ($text =~
    /^(?:Sequence|Protein):"?(\w\w:[\-\.\w]+)"?[\d\(\)\s]+(EST|vertebrate_mRNA|BLASTX|OTF)/
          )
        {
            my $name   = $1;
            my $column = $2;
            my $type   = $column_type{$column} or die "Can't match '$column'";

            # warn "Got blue box $type:$name\n";
            return {$type => [$name]};
        }
        elsif ($text =~ /$magic_evi_name_matcher/)
        {
            my %clip_names;
            while ($text =~ /$magic_evi_name_matcher/g) {
                my $prefix = $1 || '*';
                my $acc    = $2;
                $acc      .= $3 if $3;
                my $sv     = $4 || '*';
                warn "Got name '$prefix$acc$sv'";
                $clip_names{"$prefix$acc$sv"} = 1;
            }

            my $type_name = {};
            foreach my $clip_name (keys %clip_names) {
                foreach my $class (qw{ Sequence Protein }) {
                    $ace->raw_query(qq{find $class "$clip_name"});
                    my $txt =
                      Hum::Ace::AceText->new(
                        $ace->raw_query(qq{show -a DNA_homol}));
                    print STDERR $$txt;
                    my @seq = map $_->[1], $txt->get_values($class) or next;
                    if (@seq > 1) {
                        warn "Got multiple matches:\n", map "  $_\n", @seq;
                        last;
                    }
                    my $name = $seq[0];
                    my $homol_method = ($txt->get_values('DNA_homol'))[0]->[1];
                    $homol_method =~ s/^(EST)_.+/$1/;
                    my $type = $column_type{$homol_method}
                        or die "No type for homol method '$homol_method'";
                    my $name_list = $type_name->{$type} ||= [];
                    push(@$name_list, $name);
                }
            }
            return $type_name;
        }
        else {
            #warn "Didn't match: '$text'\n";
            return {};
        }
    }
}

1;

__END__

=head1 NAME - Hum::ClipboardUtils

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

