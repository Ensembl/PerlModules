package Hum::Chromoview::ChromoSQL;

### Author: ck1@sanger.ac.uk


use vars qw{ @ISA @EXPORT_OK };
use strict;
use warnings;
use Hum::Tracking qw{prepare_track_statement};

@ISA = ('Exporter');
@EXPORT_OK = qw(
                fetch_species_chrsTpf
                fetch_subregionsTpf
                get_species_subregions
                get_tpf_from_clonename
                get_tpf_from_accession
               );

sub new {
    my ($class) = @_;
    my $self = {};
    return bless ($self, $class);
}

sub fetch_species_chrsTpf {
  my ($self, $species) = @_;

  my $condition = $species ? qq{tg.subregion is null and c.speciesname = '$species'} : qq{tg.subregion is null};

  my $species_chr = prepare_track_statement(qq{
                                               SELECT c.speciesname, c.chromosome, tg.id_tpftarget
                                               FROM chromosomedict c, tpf_target tg, tpf t
                                               WHERE $condition
                                               AND t.id_tpftarget=tg.id_tpftarget
                                               AND tg.chromosome=c.id_dict and t.ISCURRENT=1
                                               ORDER BY c.speciesname, c.chromosome
                                             });

  $species_chr->execute;
  my $species2chrTpf;
  while ( my ($species, $chr, $id_tpftarget) = $species_chr->fetchrow ){
    # warn "$species, $chr";
    $species2chrTpf->{$species}->{$chr} = $id_tpftarget;
  }

  return $species2chrTpf;
}

sub fetch_subregionsTpf {
  my ($self, $species) = @_;
  my $condition = $species ? qq{t.iscurrent = 1 and cd.speciesname = '$species'} : qq{t.iscurrent = 1};
  my $subr = prepare_track_statement(qq{
                                        SELECT s.subregion, s.speciesname, cd.chromosome, tg.id_tpftarget
                                        FROM chromosomedict cd, subregion s, tpf_target tg, tpf t
                                        WHERE $condition
                                        AND t.id_tpftarget=tg.id_tpftarget
                                        AND tg.subregion=s.subregion
                                        AND s.chromosome=cd.id_dict
                                      });

  $subr->execute();
  my $species_subregions_chrTpf;
  while ( my ($subregion, $species, $chr, $id_tpftarget) = $subr->fetchrow ){

    # Kerstin H. info
    next if $species eq 'Zebrafish' and $subregion =~ /ZFISH_HS_/;

    $species_subregions_chrTpf->{$species}->{$subregion . "__chr" . $chr} = $id_tpftarget;
  }
  return $species_subregions_chrTpf;
}

sub get_species_subregions {
  my $species_subregion = prepare_track_statement(q{
                                                     SELECT distinct tpft.subregion, cd.speciesname, tpf.id_tpf, tpft.id_tpftarget
                                                     FROM   tpf, tpf_target tpft, chromosomedict cd
                                                     WHERE  tpft.chromosome   = cd.id_dict
                                                     AND    tpft.id_tpftarget = tpf.id_tpftarget
                                                     AND    tpf.iscurrent =1
                                                     AND    tpft.subregion is not null
                                                   });
  $species_subregion->execute();

  my $spec_subrg_idTpf_ttrgt = {};

  while ( my ($subregion, $species, $idtpf, $tpftarget) = $species_subregion->fetchrow ){
    $spec_subrg_idTpf_ttrgt->{$species}->{$subregion};
  }
}

sub get_tpf_from_clonename {
  my ($self, $clonename) = @_;
  my $sql = qq{SELECT tr.rank,
                      t.id_tpftarget,
                      cd.chromosome,
                      cd.speciesname,
                      tt.subregion
               FROM   tpf_row tr, tpf t,
                      tpf_target tt,
                      chromosomedict cd
               WHERE  tr.clonename = ?
               AND    tr.id_tpf = t.id_tpf
               AND    t.iscurrent  = 1
               AND    t.id_tpftarget = tt.id_tpftarget
               AND    tt.chromosome=cd.id_dict
            };
  prepare_track_statement($sql);
  my $qry = prepare_track_statement($sql);
  $qry->execute($clonename);

  my $rows = [];

  while ( my ($rank, $id_tpftarget, $chr, $species, $subregion) = $qry->fetchrow ){
    my $obj = Hum::Chromoview::ChromoSQL->new;
    $subregion = '' unless $subregion;
    warn "$rank, $id_tpftarget, $chr, $species, $subregion";
    $obj->seqname($clonename);
    $obj->rank($rank);
    $obj->id_tpftarget($id_tpftarget);
    $obj->chromosome($chr);
    $obj->species($species);
    $obj->subregion($subregion);
    push( @$rows, $obj);
  }
  return $rows;
}

sub get_tpf_from_accession {
  my ($self, $accession) = @_;
  my $sql = qq{SELECT tr.rank,
                      t.id_tpftarget,
                      cd.chromosome,
                      cd.speciesname,
                      tt.subregion
               FROM   tpf_row tr,
                      tpf t,
                      clone_sequence cs,
                      sequence se,
                      tpf_target tt,
                      chromosomedict cd
               WHERE  se.accession = ?
               AND    t.iscurrent  = 1
               AND    tr.id_tpf = t.id_tpf
               AND    tr.clonename = cs.clonename
               AND    cs.is_current = 1
               AND    cs.id_sequence = se.id_sequence
               AND    t.id_tpftarget = tt.id_tpftarget
               AND    tt.chromosome=cd.id_dict
             };

  my $qry = prepare_track_statement($sql);
  $qry->execute($accession);

  $self->seqname($accession);

  my $rows = [];

  while ( my ($rank, $id_tpftarget, $chr, $species, $subregion) = $qry->fetchrow ){
    my $obj = Hum::Chromoview::ChromoSQL->new;
    $subregion = '' unless $subregion;
    warn "$rank, $id_tpftarget, $chr, $species, $subregion";
    $obj->seqname($accession);
    $obj->rank($rank);
    $obj->id_tpftarget($id_tpftarget);
    $obj->chromosome($chr);
    $obj->species($species);
    $obj->subregion($subregion);
    push( @$rows, $obj);
  }
  return $rows;
}

sub seqname {
  # accession or projectname
  my ( $self, $seqname ) = @_;
  if ($seqname) {
    $self->{'_seqname'} = $seqname;
  }
  return $self->{'_seqname'};
}
sub rank {
  my ( $self, $rank ) = @_;
  if ($rank) {
    $self->{'_rank'} = $rank;
  }
  return $self->{'_rank'};
}

sub subregion {
  my ( $self, $subregion ) = @_;
  if ($subregion) {
    $self->{'_subregion'} = $subregion;
  }
  return $self->{'_subregion'};
}

sub species {
  my ( $self, $species ) = @_;
  if ($species) {
    $self->{'_species'} = $species;
  }
  return $self->{'_species'};
}

sub chromosome {
  # $chr: 1, 2, or X
  my ( $self, $chr ) = @_;
  if ($chr) {
    $self->{'_chromosome'} = $chr;
  }
  return $self->{'_chromosome'};
}

sub id_tpftarget {
  my ( $self, $id ) = @_;
  if ($id) {
    $self->{'_id_tpftarget'} = $id;
  }
  return $self->{'_id_tpftarget'};
}


#               SELECT tr.id_tpfrow, tr.rank, tr.id_tpf, t.id_tpftarget
#               FROM tpf_row tr, tpf t, clone_sequence cs, sequence s
#               WHERE  s.accession = ?
#               AND    tr.id_tpf = t.id_tpf
#               AND    tr.clonename = cs.clonename
#               AND    cs.is_current = 1
#               AND    cs.id_sequence = s.id_sequence
#               AND    t.iscurrent  = 1
#             };
#sub get_contig_info {
#  my ($pkg, $id_tpftarget) = @_;
#  my $ctginfo = prepare_track_statement(q{
#                                           SELECT sum(se.length), tpr.contigname, min(tpr.rank), max(tpr.rank)
#                                           FROM   tpf_row tpr, tpf, clone_sequence cs, sequence se
#                                           where  tpf.id_tpftarget = ?
#                                           and    tpf.iscurrent    = 1
#                                           and    tpf.id_tpf       = tpr.id_tpf
#                                           and    tpr.contigname is not null
#                                           and    tpr.clonename   = cs.clonename
#                                           and    cs.is_current = 1
#                                           and    cs.id_sequence   = se.id_sequence
#                                           group  by tpr.contigname
#                                           order  by min(tpr.rank)
#                                         });
#  $ctginfo->execute($id_tpftarget);
#  my $ctgSrErlen;
#  while ( my ($len, $ctgname, $sr, $er) = $ctginfo->fetchrow){
#    push(@{$ctgSrErlen}, [$len, $ctgname, $sr, $er]);
#    my $self = $pkg->new;
#    $self->{'length'}    = $len;
#    $self->{'ctgname'}   = $ctgname;
#    $self->{'startRank'} = $sr;
#    $self->{'endRank'}   = $er;
#    push(@$ctgSrErlen, $self);
#  }
#  return $ctgSrErlen;
#}

1;
