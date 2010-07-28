
### Hum::TPF::Utils

package Hum::TPF::Utils;

use strict;
use warnings;
use Carp;
use Hum::Sort qw{ ace_sort };
use Hum::Tracking qw{
    prepare_track_statement
    };
use base 'Exporter';
our @EXPORT_OK = qw{
    species_tpf_summary
    species_tpf_list
    current_tpf_id
	fetch_all_id_tpfs_from_id_tpftarget
	fetch_entry_date_from_id_tpf
    };

sub species_tpf_summary {
    my $sth = prepare_track_statement(q{
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
    
    my $tpf_species = [];
    while (my ($name, $genus, $species, $count) = $sth->fetchrow) {
        push(@$tpf_species, [$name, $genus, $species, $count]);
    }
    return $tpf_species;
}

sub species_tpf_list {
    my ($species) = @_;
    
    my $sth = prepare_track_statement(q{
        SELECT c.chromosome
          , g.subregion
          , TO_CHAR(t.entry_date, 'YYYY-MM-DD HH24:MI:SS') entry_date
          , t.operator
          , t.id_tpf
        FROM chromosomedict c
          , tpf_target g
          , tpf t
        WHERE c.id_dict = g.chromosome
          AND g.id_tpftarget = t.id_tpftarget
          AND t.iscurrent = 1
          AND c.speciesname = ?
        });
    $sth->execute($species);
    
    my $tpf_list = [];
    while (my ($chr, $subregion, $entry_date, $operator, $tpf_id) = $sth->fetchrow) {
        push(@$tpf_list, [$chr, $subregion || '', $entry_date, $operator, $tpf_id]);
    }
    
    @$tpf_list = sort {
        ace_sort($a->[0], $b->[0]) ||
        ace_sort($a->[1], $b->[1])
        } @$tpf_list;
    
    return $tpf_list;
}

sub current_tpf_id {
    my ($tpf_id) = @_;
    
    confess "Missing TPF ID argument" unless $tpf_id;
    
    my $sth = prepare_track_statement(q{
        SELECT new.id_tpf
        FROM tpf old
          , tpf new
        WHERE old.id_tpftarget = new.id_tpftarget
          AND old.id_tpf = ?
          AND new.iscurrent = 1
        });
    $sth->execute($tpf_id);
    
    my ($current) = $sth->fetchrow;
    return $current;
}

sub fetch_all_id_tpfs_from_id_tpftarget {

  my ( $id_tpftarget ) = @_;

  my $qry = prepare_track_statement(qq{
                             SELECT id_tpf
                             FROM tpf
                             WHERE id_tpftarget = ?
                             ORDER BY entry_date
                             DESC
                           });

  $qry->execute($id_tpftarget);
  my $id_tpf = [];
  while ( my ($id) = $qry->fetchrow ){
    push(@$id_tpf, $id);
  }

  return $id_tpf;
}

{
    my $qry;

    sub fetch_entry_date_from_id_tpf {

        my ($id_tpf) = @_;

        $qry ||= prepare_track_statement(qq{
             SELECT TO_CHAR(entry_date, 'yyyy-mm-dd hh:mm:ss')
             FROM tpf
             WHERE id_tpf = ?
        });

        $qry->execute($id_tpf);
        return $qry->fetchrow;
    }
}

1;

__END__

=head1 NAME - Hum::TPF::Utils

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

