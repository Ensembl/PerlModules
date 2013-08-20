#!/usr/bin/env perl

### Test Hum::Mole
### Dependent upon the existence of Mole
### and upon the details of the following clones remaining the same.

use strict;
use warnings;
use Hum::NcbiFetch qw(ncbi_embl_object_fetch wwwfetch_EMBL_object_using_NCBI_fallback);
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
	# Problematic clone
	'AC247039' => {
		sv => '2',
		htgs_phase => '3',
	},	

);

foreach my $accession (sort keys %results_for_accession) {
	my $embl_object = ncbi_embl_object_fetch($accession);
    my $fallback_embl_object = wwwfetch_EMBL_object_using_NCBI_fallback($accession);

    foreach my $object ($embl_object, $fallback_embl_object) {
        my $computed = $embl_object->ID->version;
        my $expected = $results_for_accession{$accession}{sv};
        is($computed, $expected, "$accession version should be $expected");
    } 
	
}
