
package Hum::EmblUtils;

use strict;
use Carp;
use Hum::Tracking qw( ref_from_query external_clone_name );
use Hum::Submission 'project_name_and_suffix_from_sequence_name';
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
    # as it is agreed that linkage group = chromosome
    $ft->addQualifierStrings('chromosome', $chr);

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

    my %class = (

        human =>
        [qw(Homo sapiens  human
            Eukaryota Metazoa Chordata Craniata Vertebrata Euteleostomi Mammalia
            Eutheria Primates Catarrhini Hominidae Homo
            )],

        gorilla =>
        [qw(Gorilla gorilla gorilla
            Eukaryota Metazoa Chordata Craniata Vertebrata Euteleostomi Mammalia
            Eutheria Primates Catarrhini Hominidae Gorilla
            )],

        gibbon =>
        [qw(Hylobates syndactylus  siamang
            Eukaryota Metazoa Chordata Craniata Vertebrata Euteleostomi Mammalia
            Eutheria Primates Catarrhini Hylobatidae Hylobates
            )],

        mouse =>
        [qw(Mus musculus), 'house mouse', qw(
            Eukaryota Metazoa Chordata Craniata Vertebrata Euteleostomi Mammalia
            Eutheria Rodentia Sciurognathi Muridae Murinae Mus
            )],
        
        rat =>
        [qw(Rattus norvegicus), 'Norway rat', qw(
            Eukaryota Metazoa Chordata Craniata Vertebrata Euteleostomi Mammalia
            Eutheria Rodentia Sciurognathi Muridae Murinae Rattus
            )],
        
        dog =>
        [qw(Canis familiaris), 'dog', qw(
            Eukaryota Metazoa Chordata Craniata Vertebrata Euteleostomi Mammalia
            Eutheria Carnivora Fissipedia Canidae Canis
            )],
        
        pig =>
        [qw(Sus scrofa), 'pig', qw(
            Eukaryota Metazoa Chordata Craniata Vertebrata Euteleostomi Mammalia
            Eutheria Cetartiodactyla Suina Suidae Sus
            )],
        
        sminthopsis =>
        [qw(Sminthopsis macroura), 'Australian stripe-faced dunnart', qw(
            Eukaryota Metazoa Chordata Craniata Vertebrata Euteleostomi Mammalia
            Metatheria Dasyuromorphia Dasyuridae Sminthopsis
            )],

        chicken =>
        [qw(Gallus gallus chicken
            Eukaryota Metazoa Chordata Craniata Vertebrata Archosauria Aves
            Neognathae Galliformes Phasianidae Phasianinae Gallus
            )],

        drosophila =>
        [qw(Drosophila melanogaster), 'fruit fly', qw(
            Eukaryota Metazoa Arthropoda Tracheata Hexapoda Insecta Pterygota
            Neoptera Endopterygota Diptera Brachycera Muscomorpha Ephydroidea
            Drosophilidae Drosophila
            )],

        fugu =>
        [qw(Fugu rubripes), undef, qw(
            Eukaryota Metazoa Chordata Craniata Vertebrata Actinopterygii
            Neopterygii Teleostei Euteleostei Acanthopterygii Percomorpha
            Tetraodontiformes Tetraodontoidei Tetraodontidae Fugu
            )],

        tetraodon =>
        [qw(Tetraodon nigroviridis), undef, qw(
            Eukaryota Metazoa Chordata Craniata Vertebrata Actinopterygii
            Neopterygii Teleostei Euteleostei Acanthopterygii Percomorpha
            Tetraodontiformes Tetraodontoidei Tetraodontidae Tetraodon
            )],

        arabidopsis =>
        [qw(Arabidopsis thaliana), 'thale cress', qw(
            Eukaryota Viridiplantae Streptophyta Embryophyta Tracheophyta
            Spermatophyta Magnoliophyta eudicotyledons ),
            'core eudicots', 'rosids', 'eurosids II',
            qw( Rosidae  Brassicales Brassicaceae Arabidopsis )],
        
        'm.truncatula' =>
        [qw(Medicago truncatula), 'barrel medic', qw(
            Eukaryota Viridiplantae Streptophyta Embryophyta Tracheophyta
            Spermatophyta Magnoliophyta eudicotyledons ),
            'core eudicots', 'rosids', 'eurosids I',
            qw( Fabales Fabaceae Papilionoideae Trifolieae Medicago )],
        
        'b.floridae' => 
        [qw(Branchiostoma floridae), 'forida lancelet', qw(
            Eukaryota Metazoa Chordata Cephalochordata Branchiostomida Branchiostoma 
            )],
        
        zebrafish =>
        [qw(Danio rerio), 'zebrafish', qw(
            Eukaryota Metazoa Chordata Craniata Vertebrata Euteleostomi
            Actinopterygii Neopterygii Teleostei Euteleostei Ostariophysi
            Cypriniformes Cyprinidae Rasborinae Danio
            )],
        
        'x.tropicalis' =>
        [qw(Xenopus tropicalis), 'western clawed frog', qw(
            Eukaryota Metazoa Chordata Craniata Vertebrata Euteleostomi Amphibia 
            Batrachia Anura Mesobatrachia Pipoidea Pipidae Xenopodinae Xenopus
            )],
        
        platypus =>
        [qw(Ornithorhynchus anatinus), 'platypus', qw(
            Eukaryota Metazoa Chordata Craniata Vertebrata Euteleostomi Mammalia
            Monotremata Ornithorhynchidae Ornithorhynchus
            )],
        
        wallaby =>
        [qw(Macropus eugenii), 'tammar wallaby', qw(
            Eukaryota Metazoa Chordata Craniata Vertebrata Euteleostomi Mammalia
            Metatheria Diprotodontia Macropodidae Macropus
            )],

        opossum =>
        [qw(Didelphis virginiana), 'North American opossum', qw(
            Eukaryota Metazoa Chordata Craniata Vertebrata Euteleostomi Mammalia
            Metatheria Didelphimorphia Didelphidae Didelphis
            )],

        carp =>
        [qw(Cyprinus carpio), 'carp', qw(
            Eukaryota Metazoa Chordata Craniata Vertebrata Euteleostomi Actinopterygii
            Neopterygii Teleostei Ostariophysi Cypriniformes Cyprinidae Cyprinus
            )],
        
        chimp =>
        [qw(Pan troglodytes), 'chimp', qw(
            Eukaryota Metazoa Chordata Craniata Vertebrata Euteleostomi Mammalia
            Eutheria Primates Catarrhini Hominidae Pan
            )],

        rhesus =>
        [qw(Macaca mulatta), 'rhesus monkey', qw(
            Eukaryota Metazoa Chordata Craniata Vertebrata Euteleostomi Mammalia
            Eutheria Primates Catarrhini Cercopithecidae Cercopithecinae Macaca
            )],
    );

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
            if (my $data = $class{$speciesname}) {
                my( $genus, $species, $common, @classification ) = @$data;

                $og = Hum::EMBL::Line::Organism->new;
                $og->genus($genus);
                $og->species($species);
                $og->common($common) if $common;
                $og->classification(@classification);
            } else {
                confess "I don't know about '$speciesname'";
            }
        }
        return $og;
    }
    
    sub species_binomial {
        my $species = lc shift;
        
        if (my $latin = $class{$species}) {
            return join(' ', $latin->[0], $latin->[1] );
        } else {
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
