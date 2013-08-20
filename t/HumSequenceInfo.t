#!/usr/bin/env perl

### Test Hum::SequenceInfo
### Dependent upon the existence of CASP
### and upon the details of the following clones remaining the same.

use strict;
use warnings;
use Hum::SequenceInfo;
use Test::More qw( no_plan );

my %results_for_accession = (
	# Mouse unfinished clone from EMBL
	"AC192092" => {
		accession_sv => 'AC192092.1',
		htgs_phase => '1',
		sequence_length => '70007',
		embl_checksum => '1135107303',
	},
	# Zebrafish finished clone from Sanger
	"FP067451" => {
		accession_sv => 'FP067451.6',
		htgs_phase => '3',
		sequence_length => '10873',
		embl_checksum => '2315319615',
	},
	# Mouse finished clone from EMBL
	'AC012526' => {
		accession_sv => 'AC012526.35',
		htgs_phase => '3',
		sequence_length => '186272',
		embl_checksum => '1929818599',
	},
	# Recently updated clone
	'AC246785' => {
		accession_sv => 'AC246785.2',
		htgs_phase => '3',
		sequence_length => '215868',
		embl_checksum => '2015691170',
	},
	# Clone in tracking DB but not in Mole
	'AC247039' => {
		accession_sv => 'AC247039.2',
		htgs_phase => '3',
		sequence_length => '198298',
		embl_checksum => '294876821',
	},
	
);

foreach my $accession (sort keys %results_for_accession) {
	my $seq_info = Hum::SequenceInfo->fetch_latest_with_Sequence($accession);

	foreach my $function (sort keys %{$results_for_accession{$accession}}) {
		my $computed = $seq_info->$function;
		my $expected = $results_for_accession{$accession}{$function};
		is($computed, $expected, "$accession $function should be $expected");
		
	}
	
	my $computed_sequence_length = length($seq_info->Sequence->sequence_string);
	my $expected_sequence_length = $results_for_accession{$accession}{sequence_length};
	is($computed_sequence_length, $expected_sequence_length, "$accession length(sequence) should be $expected_sequence_length");

}
