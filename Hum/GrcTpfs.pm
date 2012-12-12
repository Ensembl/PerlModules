
### Hum::GrcTpfs

package Hum::GrcTpfs;

use vars qw{ @ISA @EXPORT_OK };
use strict;
use warnings;
use Carp;
use Hum::TPF;
use Hum::Chromoview::Utils qw(get_all_current_TPFs);

@ISA = ('Exporter');
@EXPORT_OK = qw(
	get_grc_tpf_objects
	get_grc_tpf_names
);

sub get_grc_tpf_objects {
	my ($selected_species) = @_;
	my @tpf_objects = map {get_tpf_object_from_name($_)} get_grc_tpf_names($selected_species);
	return @tpf_objects;
}

sub get_grc_tpf_names {
	my ($selected_species) = @_;

	my %species_to_check;
	
	if(defined($selected_species)) {
		$species_to_check{$selected_species} = 1;
	}
	else {
		foreach my $grc_species ( get_grc_species() ) {
			$species_to_check{$grc_species} = 1;
		}
	}

	my %ncbi_tpf_for = %{ get_ncbi_tpfs() };

	my @tpfs_for_overlap_checking;
	my $all_tpf_names = get_all_current_TPFs();
	foreach my $tpf_name (@{$all_tpf_names}) {
		my ($species, $chr, $subregion) = @{$tpf_name};
		# We only want subregions if they correspond to those which the NCBI holds
		if(
			exists($species_to_check{$species})
			and exists( $ncbi_tpf_for{lc($species)}{$chr}{$subregion} )
		) {
			push(@tpfs_for_overlap_checking, $tpf_name);
		}
	}
	
	return @tpfs_for_overlap_checking;
}

sub get_grc_species {
	return ('Human','Mouse','Zebrafish');
}

sub get_ncbi_tpfs {
	my $tpf_root_directory = '/nfs/grcdata/NCBI/';
	
	my %ncbi_tpf_for;
	foreach my $species ( get_grc_species() ) {
		$species = lc($species);
		my $species_dir = "$tpf_root_directory/$species/MOST_RECENT_TPFS/";
		opendir(my $species_dir_handle, $species_dir) or die "Cannot open tpf directory\n";
		my @subregion_dirs = readdir($species_dir_handle);
		closedir($species_dir_handle);
		@subregion_dirs = grep {-d "$species_dir/$_"} @subregion_dirs;
		
		foreach my $subregion_dir (@subregion_dirs) {
			
			opendir(my $tpf_dir_handle, "$species_dir/$subregion_dir") or die "Cannot open tpf directory\n";
			my @tpf_files = readdir($tpf_dir_handle);
			closedir($tpf_dir_handle);
			@tpf_files = grep(/\.txt$/, @tpf_files);
			
			foreach my $tpf_file (@tpf_files) {
				my ($chromosome, $subregion) = assign_chromosome_and_subregion ($tpf_file, $species, $subregion_dir);
				$ncbi_tpf_for{$species}{$chromosome}{$subregion} = 1;
			}
		}
	}
	
	return \%ncbi_tpf_for;
}

sub assign_chromosome_and_subregion {
	my ($tpf_file, $species, $ncbi_directory) = @_;
	
	my ($chromosome, $subregion);
	
	# Reference chromosomes are treated one way
	if($ncbi_directory eq 'Reference') {
		if($tpf_file =~ /_chr(.*)\.chr\.txt$/) {
			$chromosome = $1;
			$subregion = "";
		}
		elsif($tpf_file =~ /_chr(.*)\.ctg\.txt$/) {
			$chromosome = $1;
			if($chromosome =~ /Un/i) {$chromosome = 'U'}
			$subregion = "UNPL_$chromosome";

			# Mouse regions must be prefixed MOUSE to avoid clashes with human			
			if($species =~ /^mouse$/i) {
				$subregion = "GRC__MOUSE__UNPL__$chromosome";
			}
			
			if($species eq 'zebrafish') {$subregion = ''}
		}
	}
	# Alternative regions are treated differently
	else {
		if($tpf_file =~ /_chr(.*)\.ctg\.txt$/) {
			$chromosome = $1;
			
			my $prefix = 'GRC';
			
			$subregion = join(
				'__',
				$prefix,
				uc($species),
				$ncbi_directory,
				$chromosome,
			);
			
		}
		else {
			die("Nonstandard TPF filename $tpf_file in directory $ncbi_directory");
		}
	}

	return ($chromosome, $subregion);
}

sub get_tpf_object_from_name {
	my ($tpf_name) = @_;
	
	my $species   = $tpf_name->[0];
    my $chr       = $tpf_name->[1];
    my $subregion = $tpf_name->[2];
	
    my ($tpf);
    if ($subregion) {
        $tpf = Hum::TPF->current_from_species_chromsome_subregion($species, $chr, $subregion);
    }
    else {
        $tpf = Hum::TPF->current_from_species_chromsome($species, $chr);
    }
	
	return $tpf;
}

1;

__END__

=head1 NAME - Hum::GrcTpfs

=head1 AUTHOR

James Torrance B<email> jt8@sanger.ac.uk

