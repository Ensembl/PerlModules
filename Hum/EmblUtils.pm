
package Hum::EmblUtils;

use strict;
use Carp;
use Hum::Tracking qw( ref_from_query external_clone_name );
use Exporter;
use vars qw( @EXPORT_OK @ISA );
@ISA       = qw( Exporter );
@EXPORT_OK = qw( extCloneName projectAndSuffix
                 add_source_FT add_Organism
                 library_and_vector
                 );


sub add_source_FT {
    my( $embl, $length, $species, $external_clone,
        $chr, $map, $libraryname ) = @_;

    my $ft = $embl->newFT;
    $ft->key('source');
    
    my $loc = $ft->newLocation;
    $loc->exons([1, $length]);
    $loc->strand('W');
    
    $ft->addQualifierStrings('organism',   $species);
    $ft->addQualifierStrings('chromosome', $chr);
    $ft->addQualifierStrings('map',        $map)             if $map;
    $ft->addQualifierStrings('clone',      $external_clone);
    $ft->addQualifierStrings('clone_lib',  $libraryname)     if $libraryname;
    
    return $ft;
}

sub library_and_vector {
    my( $project ) = @_;
    
    my $ans = ref_from_query(qq(
                                select l.libraryname, l.vectorname
                                from clone_project cp, clone c, library l
                                where
                                    cp.clonename = c.clonename and
                                    c.libraryname = l.libraryname and
                                    cp.projectname = '$project' ));
    if (@$ans) {
        return(@{$ans->[0]});
    } else {
        return;
    }
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
        [qw(Homo sapiens human
            Eukaryota Metazoa Chordata Craniata Vertebrata Mammalia Eutheria
            Primates Catarrhini Hominidae Homo
            )],

        mouse =>
        [qw(Mus musculus), 'house mouse', qw(
            Eukaryota Metazoa Chordata Craniata Vertebrata Mammalia Eutheria
            Rodentia Sciurognathi Muridae Murinae Mus
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

        arabidopsis =>
        [qw(Arabidopsis thaliana), 'thale cress', qw(
            Eukaryota Viridiplantae Streptophyta Embryophyta Tracheophyta
            euphyllophytes Spermatophyta Magnoliophyta eudicotyledons
            core eudicots Rosidae eurosids II Brassicales Brassicaceae
            Arabidopsis
            )],
    );

    sub add_Organism {
        my( $embl, $speciesname ) = @_;
        $speciesname = lc $speciesname;

        confess "I don't know about '$speciesname'" unless $class{$speciesname};

        my( $genus, $species, $common, @classification ) = @{$class{$speciesname}};

        my $og = $embl->newOrganism;
        $og->genus($genus);
        $og->species($species);
        $og->common($common) if $common;
        $og->classification(@classification);
        
        return $og;
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
                die "Not an acedb object"
                        unless $_->isa('Ace::Object');
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
    
    my( $project, $suffix );
    eval{ $project = $ace->at('Project.Project_name[1]')->name   };
    eval{ $suffix  = $ace->at('Project.Project_suffix[1]')->name };
    
    return($project, $suffix);
}


1;

__END__
