#!/usr/bin/env perl

### Test Hum::Mole
### Dependent upon the existence of Mole
### and upon the details of the following clones remaining the same.

use strict;
use warnings;
use Hum::SequenceInfo;
use Test::More qw( no_plan );

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
);

foreach my $accession (sort keys %results_for_accession) {
	my $seq_info = Hum::Mole->new($accession);

	foreach my $function (sort keys %{$results_for_accession{$accession}}) {
		my $computed = $seq_info->$function;
		my $expected = $results_for_accession{$accession}{$function};
		is($computed, $expected, "$accession $function should be $expected");
	}
	
}
