#!/usr/bin/env perl
# Copyright [2018-2024] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;

use Test::More;
use Hum::Ace::Locus;
use Hum::Ace::Method;
use Hum::Ace::SubSeq;
use Hum::Ace::Zmap_Style;

my $module;
BEGIN {
    $module = 'Hum::Ace::Assembly';
    use_ok($module);
}

my $haa = new_ok($module);

foreach my $n ( qw( A B C D ) ) {
    my $l = Hum::Ace::Locus->new;
    $l->name("L:${n}");
    if ($n eq 'B' or $n eq 'D') {
        $l->set_remarks('annotation in progress');
    }

    my $z = Hum::Ace::Zmap_Style->new;
    if ($n eq 'B' or $n eq 'C') {
        $z->name("curated_Z:$n");
    } else {
        $z->name("Z:$n");
    }

    my $m = Hum::Ace::Method->new;
    $m->ZMapStyle($z);

    my $s = Hum::Ace::SubSeq->new;
    $s->name("S:${n}");
    $s->Locus($l);
    $s->GeneMethod($m);

    $haa->add_SubSeq($s);
}
pass('add_SubSeq');

my @ss = $haa->get_all_SubSeqs;
is(scalar(@ss), 4, 'get_all_SubSeqs (n)');
is_deeply([ sort { $a cmp $b } map { $_->name } @ss ],
          [ qw( S:A S:B S:C S:D ) ],
          'get_all_SubSeqs (names)');

my @ls = $haa->get_all_Loci;
is(scalar(@ls), 4, 'get_all_Loci (n)');
is_deeply([ sort { $a cmp $b } map { $_->name } @ls ],
          [ qw( L:A L:B L:C L:D ) ],
          'get_all_Loci (names)');

my @aip_ls = $haa->get_all_annotation_in_progress_Loci;
is(scalar(@aip_ls), 1, 'get_all_annotation_in_progress_Loci');
is_deeply([ sort { $a cmp $b } map { $_->name } @aip_ls ],
          [ qw( L:B ) ],
          'get_all_annotation_in_progress_Loci (names)');

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
