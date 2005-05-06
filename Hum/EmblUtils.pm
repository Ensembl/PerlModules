
package Hum::EmblUtils;

use strict;
use Carp;
use Hum::Tracking qw( ref_from_query external_clone_name );
use Hum::Submission qw(project_name_and_suffix_from_sequence_name);
use Hum::Species;

use Exporter;
use vars qw( @EXPORT_OK @ISA );
@ISA       = qw( Exporter );
@EXPORT_OK = qw( extCloneName projectAndSuffix
                 add_source_FT add_Organism get_Organism
                 species_binomial
                 );

sub add_source_FT {
    my( $embl, $length, $binomial, $external_clone,
        $chr, $map, $libraryname ) = @_;

    my $ft = $embl->newFT;
    $ft->key('source');

    my $loc = $ft->newLocation;
    $loc->exons([1, $length]);
    $loc->strand('W');

    $ft->addQualifierStrings('mol_type',   'genomic DNA');
    $ft->addQualifierStrings('organism',   $binomial)           if $binomial;

    # check point for $binomial ne 'Danio rerio' is now omitted
    # as it is agreed that linkage group = chromosome;
    # but enforce checking if chromosome info is available
    $ft->addQualifierStrings('chromosome', $chr) if $chr =~ /\d+/;

    $ft->addQualifierStrings('map',        $map)                if $map;
    $ft->addQualifierStrings('clone',      $external_clone)     if $external_clone;
    $ft->addQualifierStrings('clone_lib',  $libraryname)        if $libraryname;

    return $ft;
}

=pod

  Human        Homo         sapiens
  Mouse        Mus          musculus
  Chicken      Gallus       gallus
  Drosophila   Drosophila   melanogaster
  Fugu         Fugu         rubripes
  Arabidopsis  Arabidopsis  thaliana

  Zebrafish    Danio        rerio
  Gibbon       Hylobates    syndactylus

=cut

BEGIN {

    my( %organism_cache );

    sub add_Organism {
        my( $embl, $speciesname ) = @_;

        my $og = get_Organism($speciesname);

        $embl->addLine($og);
    }

    sub get_Organism {
        my $speciesname = lc shift;

        my( $og );
        unless ($og = $organism_cache{$speciesname}) {

            #if (my $data = $class->{$speciesname}) {
#                my( $genus, $species, $common, @classification ) = @$data;

#                $og = Hum::EMBL::Line::Organism->new;
#                $og->genus($genus);
#                $og->species($species);
#                $og->common($common) if $common;
#                $og->classification(@classification);
#            } else {
#                confess "I don't know about '$speciesname'";
#            }

		
		    if ( my $data = Hum::Species->fetch_Species_by_name($speciesname) ) {
                $og = Hum::EMBL::Line::Organism->new;
                $og->genus($data->genus);
                $og->species($data->species);
                $og->common($data->common_name) if $data->common_name;
                $og->classification($data->lineage);
			}
		    else {
                confess "I don't know about '$speciesname'";
			}
        }

        return $og;
    }

    sub species_binomial {
        my $species = lc shift;

       # if (my $latin = $class->{$species}) {
#            return join(' ', $latin->[0], $latin->[1] );
#        } else {
#            confess "I don't know about '$species'";
#        }

		if ( my $spec = Hum::Species->fetch_Species_by_name($species) ){
		    return $spec->genus . " " . $spec->species;
		}
		else {
		    confess "I don't know about '$species'";
		}
    }
}

{
    # For caching external clone names
    my( %ext_clone_name );

    sub extCloneName {
        my( @list ) = @_;
                
        # Convert all the sequence names to projects
        foreach (@list) {
            if (ref($_)) {
                die "Not an acedb object" unless $_->isa('Ace::Object');
                ($_) = projectAndSuffix($_) || $_;
            }
        }
        
        # Fetch any names we don't have already
        my @missing = grep ! $ext_clone_name{$_}, @list;
        my $ext = external_clone_name(@missing);
        foreach my $p (keys %$ext) {
            $ext_clone_name{$p} = $ext->{$p};
        }
        
        # Fill in the names in the return array
        foreach (@list) {
            $_ = $ext_clone_name{$_};
        }
        
        return wantarray ? @list : $list[0];
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
