
package Hum::EmblUtils;

use strict;
use warnings;
use Carp;
use Hum::Tracking qw( ref_from_query intl_clone_name );
use Hum::Submission qw(project_name_and_suffix_from_sequence_name);
use Hum::Species;

use Exporter;
use vars qw( @EXPORT_OK @ISA );
@ISA       = qw( Exporter );
@EXPORT_OK = qw( projectAndSuffix add_source_FT add_Organism get_Organism
                 );

sub add_source_FT {
    my( $embl, $length, $binomial, $external_clone,
        $chr, $map, $libraryname, $primer_pair ) = @_;

    my $ft = $embl->newFT;
    $ft->key('source');

    my $loc = $ft->newLocation;
    $loc->exons([1, $length]);
    $loc->strand('W');

    $ft->addQualifierStrings('mol_type',   'genomic DNA');
    if ($binomial) {
        $ft->addQualifierStrings('organism',   $binomial);
        if ($binomial eq 'Solanum lycopersicum') {
            $ft->addQualifierStrings('cultivar', 'Heinz 1706');
        }
    }

    # check point for $binomial ne 'Danio rerio' is now omitted
    # as it is agreed that linkage group = chromosome;
    # But check that chromosome isn't UNKNOWN
    unless (! $chr or $chr =~ /u/i) {
        $ft->addQualifierStrings('chromosome', $chr);
    }

    $ft->addQualifierStrings('map',         $map)                if $map;
    $ft->addQualifierStrings('clone',       $external_clone)     if $external_clone;
    $ft->addQualifierStrings('clone_lib',   $libraryname)        if $libraryname;
    $ft->addQualifierStrings('PCR_primers', $primer_pair)        if $primer_pair; 

    return $ft;
}


BEGIN {

    my( %organism_cache );

    ### Should probably change this to use a Hum::Species object
    ### as its argument instead of fetching it.
    sub add_Organism {
        my( $embl, $speciesname ) = @_;

        my $og = get_Organism($speciesname);

        $embl->addLine($og);
    }

    sub get_Organism {
        my $speciesname = shift;

        my( $og );
        unless ($og = $organism_cache{$speciesname}) {
		    if (my $species = Hum::Species->fetch_Species_by_name($speciesname)) {
                $og = Hum::EMBL::Line::Organism->new;
                $og->genus($species->genus);
                $og->species($species->species);
                $og->common($species->common_name) if $species->common_name;
                $og->classification(split /\s+/, $species->lineage);
			}
		    else {
                confess "I don't know about '$speciesname'";
			}
        }

        return $og;
    }
}

sub projectAndSuffix {
    my( $ace ) = @_;
    
    my ($project, $suffix) =
        project_name_and_suffix_from_sequence_name($ace->name);
    
    unless ($project) {
        eval{ $project = $ace->at('Project.Project_name[1]')->name   };
        eval{ $suffix  = $ace->at('Project.Project_suffix[1]')->name };
    }
    
    return($project, $suffix);
}


1;

__END__

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>

