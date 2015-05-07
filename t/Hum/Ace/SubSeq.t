#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

my $module;
BEGIN {
    $module = 'Hum::Ace::SubSeq';
    use_ok($module);
}

my $hass = new_ok($module);

# new_from_ace_subseq_tag - not used
# new_from_subseq_list (e-o)
# new_from_clipboard_text (e-o)
# new_from_name_start_end_transcript_seq (PM)

can_ok($hass, 'ensembl_dbID');

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
