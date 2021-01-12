#!/usr/bin/env perl
# Copyright [2018-2021] EMBL-European Bioinformatics Institute
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

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule (-severity => 4);

use Test::More tests => 82;

my $module;

BEGIN {
    $module = 'Hum::ClipboardUtils';
    use_ok($module, 'magic_evi_name_match'); 
}

critic_module_ok($module);

test_match('P04435',   'bare protein',            undef, 'P04435', undef, 'P04435', undef);
test_match('P04435.1', 'protein with sv',         undef, 'P04435', 1,     'P04435', undef);

test_match('Tr:Q8WRH8', 'protein with pr',        'Tr',  'Q8WRH8', undef, 'Q8WRH8', undef);
test_match('Tr:Q8WRH8.2', 'protein with pr & sv', 'Tr',  'Q8WRH8', 2,     'Q8WRH8', undef);

test_match('Q8NAS9-2',      'protein with splv',          undef, 'Q8NAS9-2', undef, 'Q8NAS9', 2);
test_match('Q8NAS9-2.3',    'protein with sv & splv',     undef, 'Q8NAS9-2', 3,     'Q8NAS9', 2);
test_match('Sw:Q8NAS9-2',   'protein with pr & splv',     'Sw',  'Q8NAS9-2', undef, 'Q8NAS9', 2);
test_match('Sw:Q8NAS9-2.3', 'protein with pr, sv & splv', 'Sw',  'Q8NAS9-2', 3,     'Q8NAS9', 2);

test_match('Em:AA781974.5', 'EMBL with pr & sv', 'Em', 'AA781974', 5, 'AA781974', undef);

test_match('NP_005922.1',          'Bad 1', undef, undef, undef, undef, undef);
test_match('Em:CNSLT06MR',         'Bad 2', undef, undef, undef, undef, undef);
test_match('Em:bA164I17.2.15',     'Bad 3', undef, undef, undef, undef, undef);
test_match('Em:AA402089,AA401938', 'Bad 4', undef, undef, undef, undef, undef);

test_match(' Sw:Q8NAS9-2.3',   'Leading space',      'Sw',  'Q8NAS9-2', 3,     'Q8NAS9', 2);
test_match('Sw:Q8NAS9-2.3  ',  'Trailing space',     'Sw',  'Q8NAS9-2', 3,     'Q8NAS9', 2);
test_match(' Sw:Q8NAS9-2.3  ', 'Leading & trailing', 'Sw',  'Q8NAS9-2', 3,     'Q8NAS9', 2);

1;

sub test_match {
    my ($name, $desc, $e_pf, $e_ac, $e_sv, $e_ac_only, $e_splv) = @_;
    my ($pf, $ac, $sv, $ac_only, $splv) = magic_evi_name_match($name);
    is ($pf,      $e_pf,      "$desc - prefix");
    is ($ac,      $e_ac,      "$desc - accession");
    is ($sv,      $e_sv,      "$desc - sequence version");
    is ($ac_only, $e_ac_only, "$desc - accession_only");
    is ($splv,    $e_splv,    "$desc - splice variant");
}

# Local Variables:
# mode: perl
# End:

# EOF
