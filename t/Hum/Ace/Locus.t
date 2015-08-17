#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

my $module;
BEGIN {
    $module = 'Hum::Ace::Locus';
    use_ok($module);
}

my $hal = new_ok($module);
can_ok($hal, 'ensembl_dbID');

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
