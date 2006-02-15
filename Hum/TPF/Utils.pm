
### Hum::TPF::Utils

package Hum::TPF::Utils;

use strict;
use Hum::Tracking qw{
    prepare_track_statement
    };
use base 'Exporter';
our @EXPORT_OK = qw{
    species_tpf_summary
    };

sub species_tpf_summary {
    my $sth = prepare_track_statement(q {
        SELECT s.speciesname
          , s.genus
          , s.species
          , count(*)
        FROM species s
          , chromosomedict c
          , tpf_target g
          , tpf t
        WHERE s.speciesname = c.speciesname
          AND c.id_dict = g.chromosome
          AND g.id_tpftarget = t.id_tpftarget
          AND t.iscurrent = 1
        GROUP BY s.speciesname, s.genus, s.species
        ORDER BY s.speciesname ASC
        });
    $sth->execute;
    
    my @tpf_species;
    while (my ($name, $genus, $species, $count) = $sth->fetchrow) {
        push(@tpf_species, [$name, $genus, $species, $count]);
    }
    return @tpf_species;
}

1;

__END__

=head1 NAME - Hum::TPF::Utils

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

