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
