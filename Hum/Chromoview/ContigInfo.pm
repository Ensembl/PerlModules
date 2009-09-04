package Hum::Chromoview::ContigInfo;

#author: ck1@sanger.ac.uk

use strict;
use warnings;
use Hum::Tracking qw{
                     prepare_track_statement
                   };

sub new {
   my( $pkg ) = @_;
   return bless {}, $pkg;
}
sub ctg_length {
  my( $self, $len ) = @_;

  if ($len) {
    $self->{'_length'} = $len;
  }
  return $self->{'_length'};
}
sub ctg_name {
  my( $self, $name ) = @_;

  if ($name) {
    $self->{'_name'} = $name;
  }
  return $self->{'_name'};
}
sub start_rank {
  my( $self, $rank ) = @_;

  if ($rank) {
    $self->{'_start_rank'} = $rank;
  }
  return $self->{'_start_rank'};
}
sub end_rank {
  my( $self, $rank ) = @_;

  if ($rank) {
    $self->{'_end_rank'} = $rank;
  }
  return $self->{'_end_rank'};
}

sub fetch_contig_info_by_Idtpftarget {
  my ($pkg, $id_tpftarget) = @_;
  my $qry = prepare_track_statement(q{
                                           SELECT sum(se.length), tpr.contigname, min(tpr.rank), max(tpr.rank)
                                           FROM   tpf_row tpr, tpf, clone_sequence cs, sequence se
                                           where  tpf.id_tpftarget = ?
                                           and    tpf.iscurrent    = 1
                                           and    tpf.id_tpf       = tpr.id_tpf
                                           and    tpr.contigname is not null
                                           and    tpr.clonename   = cs.clonename
                                           and    cs.is_current = 1
                                           and    cs.id_sequence   = se.id_sequence
                                           group  by tpr.contigname
                                           order  by min(tpr.rank)
                                         });
  $qry->execute($id_tpftarget);
  my $ctgSrErlen;

  while ( my ($len, $ctgname, $sr, $er) = $qry->fetchrow){
    my $self = Hum::Chromoview::ContigInfo->new();
    $self->ctg_length($len);
    $self->ctg_name($ctgname);
    $self->start_rank($sr);
    $self->end_rank($er);
    push(@$ctgSrErlen, $self);
  }
  return $ctgSrErlen;
}

sub fetch_total_fin_unfin_length_by_Idtpftarget {
  my ($self, $id_tpftarget) = @_;
  my $qry = prepare_track_statement(q{
                                       SELECT sum(se.length)
                                       FROM   tpf_row tpr, tpf, clone_sequence cs, sequence se
                                       where  tpf.id_tpftarget = ?
                                       and    tpf.iscurrent    = 1
                                       and    tpf.id_tpf       = tpr.id_tpf
                                       and    tpr.contigname is not null
                                       and    tpr.clonename   = cs.clonename
                                       and    cs.is_current = 1
                                       and    cs.id_sequence   = se.id_sequence
                                       group  by tpr.contigname
                                       order  by min(tpr.rank)}
                                   );
  $qry->execute($id_tpftarget);

  my $total_len = 0;
  while (my $len = $qry->fetchrow){
    $total_len += $len;
  }

  return $total_len;
}

sub fetch_total_fin_length_by_Idtpftarget {
  my ($self, $id_tpftarget) = @_;
  my $qry = prepare_track_statement(q{
                                       SELECT sum(se.length)
                                       FROM   tpf_row tpr, tpf, clone_sequence cs, sequence se,
                                              htgsphasedict h
                                       where  tpf.id_tpftarget = ?
                                       and    tpf.iscurrent    = 1
                                       and    tpf.id_tpf       = tpr.id_tpf
                                       and    tpr.contigname is not null
                                       and    tpr.clonename   = cs.clonename
                                       and    cs.is_current = 1
                                       and    cs.id_sequence   = se.id_sequence
                                       and    se.ID_HTGSPHASE = h.ID_HTGSPHASE
                                       and    h.name = 'Finished'
                                       group  by tpr.contigname
                                       order  by min(tpr.rank)}
                                   );
  $qry->execute($id_tpftarget);

  my $total_len = 0;
  while (my $len = $qry->fetchrow){
    $total_len += $len;
  }

  return $total_len;
}

sub fetch_id_tpftarget_by_id_tpf {
  my ($self, $tpf) = @_;
  my $id_tpf = $tpf->db_id;
  my $qry = prepare_track_statement("SELECT ID_TPFTARGET FROM tpf WHERE id_tpf = $id_tpf");
  $qry->execute();
  return $qry->fetchrow;
}

1;
__END__

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>
