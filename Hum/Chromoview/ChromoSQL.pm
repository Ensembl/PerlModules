package Hum::Chromoview::ChromoSQL;

### Author: ck1@sanger.ac.uk


use vars qw{ @ISA @EXPORT_OK };
use strict;
use warnings;
use Hum::Tracking qw{prepare_track_statement};
#use CGI::Carp qw(warningsToBrowser fatalsToBrowser);

@ISA = ('Exporter');
@EXPORT_OK = qw(
                fetch_species_chrsTpf
                fetch_subregionsTpf
                get_species_subregions
                get_tpf_row_from_clonename
                get_tpf_row_from_accession
                get_tpf_row_from_international_name
                fetch_all_speceis_chr_subregions_names
               );

sub new {
    my ($class) = @_;
    my $self = {};
    return bless ($self, $class);
}

sub fetch_all_speceis_chr_subregions_names {
  my ($self) = @_;
  my $species_chr_subr =
    prepare_track_statement(qq{
                               SELECT c.speciesname, c.chromosome, tg.subregion
                               FROM chromosomedict c, tpf_target tg, tpf t
                               WHERE t.id_tpftarget=tg.id_tpftarget
                               AND tg.chromosome=c.id_dict and t.ISCURRENT=1
                               ORDER BY c.speciesname, c.chromosome
                             });
  $species_chr_subr->execute;
  my $all_species_chr_subregion;

  while( my ($species, $chr, $subregion) = $species_chr_subr->fetchrow ) {
    push(@{$all_species_chr_subregion->{$species}->{$chr}}, $subregion);
  }

  return $all_species_chr_subregion;
}


sub fetch_all_species_chr_Tpf {
  my ($self) = @_;
  my $species_chr = 
    prepare_track_statement(qq{
                               SELECT c.speciesname, c.chromosome, tg.id_tpftarget
                               FROM chromosomedict c, tpf_target tg, tpf t
                               WHERE tg.subregion is null
                               AND t.id_tpftarget=tg.id_tpftarget
                               AND tg.chromosome=c.id_dict and t.ISCURRENT=1
                               ORDER BY c.speciesname, c.chromosome
                             });
  $species_chr->execute;
  my $all_species_chr;

  while( my $h = $species_chr->fetchrow_hashref ) {
    my $species = Hum::Chromoview::ChromoSQL->new();
    $species->species($h->{SPECIESNAME});
    $species->chromosome($h->{CHROMOSOME});
    $species->id_tpftarget($h->{ID_TPFTARGET});
    push(@$all_species_chr, $species);
  }

  return $all_species_chr;
}

sub fetch_all_species_subregions_Tpf {
  my $species_subregions =
    prepare_track_statement(qq{
                               SELECT distinct tpft.subregion, cd.speciesname, tpf.id_tpf, tpft.id_tpftarget
                               FROM   tpf, tpf_target tpft, chromosomedict cd
                               WHERE  tpft.chromosome   = cd.id_dict
                               AND    tpft.id_tpftarget = tpf.id_tpftarget
                               AND    tpf.iscurrent =1
                               AND    tpft.subregion is not null
                             });

  $species_subregions->execute();
  my $all_species_subregions;

  while( my $h = $species_subregions->fetchrow_hashref ) {
    my $species = Hum::Chromoview::ChromoSQL->new();
    $species->species($h->{SPECIESNAME});
    $species->chromosome($h->{CHROMOSOME});
    $species->subregion($h->{SUBREGION});
    $species->id_tpftarget($h->{ID_TPFTARGET});
    push(@$all_species_subregions, $species);
  }

  return $all_species_subregions;
}

sub fetch_species_chrsTpf {
  my ($self, $species) = @_;

  my $condition = $species ? qq{AND c.speciesname = '$species'} : '';

  my $species_chr = prepare_track_statement(qq{
                                               SELECT c.speciesname, c.chromosome, tg.id_tpftarget
                                               FROM chromosomedict c, tpf_target tg, tpf t
                                               WHERE tg.subregion is null
                                               $condition
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

sub get_tpf_row_from_international_name {
  my ($self, $name) = @_;
  my ($prefix, $suffix) = split(/-/, $name);

  my $sql = qq{SELECT c.clonename
               FROM library l, clone c
               WHERE c.libraryname=l.libraryname
               AND l.external_prefix= ?
               AND c.clonename like ?
             };

  my $qry = prepare_track_statement($sql);
  $qry->execute($prefix, "%$suffix");
  my $clonename = $qry->fetchrow;
  #confess $clonename;
  return $self->get_tpf_row_from_clonename($clonename);
}

sub get_tpf_row_from_clonename {
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
               AND    t.iscurrent  = 1
               AND    tr.id_tpf = t.id_tpf
               AND    t.id_tpftarget = tt.id_tpftarget
               AND    tt.chromosome=cd.id_dict
            };
  prepare_track_statement($sql);
  my $qry = prepare_track_statement($sql);
  $qry->execute($clonename);

  my $rows = [];

  while ( my ($rank, $id_tpftarget, $chr, $species, $subregion) = $qry->fetchrow ){

    next if $subregion =~ /ZFISH_HS/; # this is deprecated

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

sub get_tpf_row_from_accession {
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

    next if defined $subregion and $subregion =~ /ZFISH_HS/; # this is deprecated

    my $obj = Hum::Chromoview::ChromoSQL->new;
    $subregion = '' unless $subregion;
    #warn "$rank, $id_tpftarget, $chr, $species, $subregion";
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

__END__

=head1 AUTHOR

Chao-Kung Chen email B<ck1@sanger.ac.uk>
