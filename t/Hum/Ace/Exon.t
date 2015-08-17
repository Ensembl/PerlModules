#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

my $module;
BEGIN {
    $module = 'Hum::Ace::Exon';
    use_ok($module);
}

my $hae = new_ok($module);
can_ok($hae, 'ensembl_dbID');

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
