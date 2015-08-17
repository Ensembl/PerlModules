#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

my $module;
BEGIN {
    $module = 'Hum::Ace::SeqFeature::Simple';
    use_ok($module);
}

my $hasfs = new_ok($module);
can_ok($hasfs, 'ensembl_dbID');

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
