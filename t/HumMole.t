#!/usr/bin/env perl
# Copyright [2018-2020] EMBL-European Bioinformatics Institute
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


### Test Hum::Mole
### Dependent upon the existence of Mole
### and upon the details of the following clones remaining the same.

use strict;
use warnings;

use Test::More qw( no_plan );

use_ok('Hum::Mole');

my %results_for_accession = (
	# Mouse unfinished clone from EMBL
	"AC192092" => {
		sv => '1',
		htgs_phase => '1',
	},
	# Zebrafish finished clone from Sanger
	"FP067451" => {
		sv => '6',
		htgs_phase => '3',
	},
	# Mouse finished clone from EMBL
	'AC012526' => {
		sv => '35',
		htgs_phase => '3',
	},
	# Recently updated clone
	'AC087063' => {
		sv => '21',
		htgs_phase => '3',
	},	
	# Problematic clone
	'AC247039' => {
		sv => '2',
		htgs_phase => '3',
	},	

);

foreach my $accession (sort keys %results_for_accession) {
	my $seq_info = Hum::Mole->new($accession);

	foreach my $function (sort keys %{$results_for_accession{$accession}}) {
		my $computed = $seq_info->$function;
		my $expected = $results_for_accession{$accession}{$function};
		is($computed, $expected, "$accession $function should be $expected");
	}
	
}
