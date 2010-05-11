
package Hum::Chromoview::SeqAlignment;

#author: ck1@sanger.ac.uk

use strict;
use warnings;
use Carp;
use Hum::Pfetch 'get_Sequences';
use Hum::Chromoview::Utils qw(
  get_id_tpftargets_by_acc_sv
  get_id_tpftargets_by_seq_region_id
);

sub new {
    my ($pkg, @args) = @_;
    
    my $self = bless {}, $pkg;
    for (my $i = 0; $i < @args; $i += 2) {
        my ($method, $value) = @args[$i, $i+1];
        $self->$method($value);
    }
    
    return $self;
}

sub algorithm {
  my ( $self, $name ) = @_;
  if ($name) {
    $self->{'_algorithm'} = $name;
  }
  return $self->{'_algorithm'};
}

sub fetch_Analysis_object {
    my ($self, $dba) = @_;
    
    my $ana_aptr = $dba->get_AnalysisAdaptor;
    $self->{'_Analysis_object'} = $ana_aptr->fetch_by_logic_name($self->algorithm)
        or confess(sprintf "No analysis '%s' in database", $self->algorithm);
}

sub Analysis_object {
    my ($self) = @_;
    
    return $self->{'_Analysis_object'};
}

sub best_feature {
  my ( $self, $align_feat ) = @_;
  if ($align_feat ){
    $self->{'_best_feature'} = $align_feat;
  }

  return $self->{'_best_feature'};
}
sub other_features {
  #$align_feat: a list ref of other overlap features which are not the best

  my ( $self, $other_align_feats ) = @_;
  if ($other_align_feats ){
    $self->{'_other_features'} = $other_align_feats;
  }

  return $self->{'_other_features'};
}


sub query_seq {
  my ( $self, $seq ) = @_;
  if ($seq) {
    $self->{'_query_seq'} = $seq;
  }
  return $self->{'_query_seq'};
}

sub hit_seq {
  my ( $self, $seq ) =@_;
  if ($seq) {
    $self->{'_hit_seq'} = $seq;
  }
  return $self->{'_hit_seq'};
}

sub name_padding {
  my ( $self, $padding ) =@_;
  if ($padding) {
    $self->{'_name_padding'} = $padding;
  }
  return $self->{'_name_padding'};
}


sub cigar_string {
  my ( $self, $cigar_str ) = @_;
  if ($cigar_str) {
    $self->{'_cigar_string'} = $cigar_str;
  }
  return $self->{'_cigar_string'};
}

sub log_message {

  my ( $self, $msg ) = @_;
  if ($msg) {
    push(@{$self->{'_log_message'}}, $msg);
  }
  return $self->{'_log_message'};

}

sub get_accession {
  my($acc_sv) = @_;
  $acc_sv =~ s/\.\d+$//;
  return $acc_sv;
}

sub _make_daf_object {
    my ($self, $slice_Ad, $feat) = @_;

    my $qry_slice = $slice_Ad->fetch_by_region('clone', get_accession($feat->seq_name));

    return Bio::EnsEMBL::DnaDnaAlignFeature->new(
        -slice        => $qry_slice,
        -start        => $feat->seq_start,
        -end          => $feat->seq_end,
        -strand       => $feat->seq_strand,
        -hseqname     => $feat->hit_name,
        -hstart       => $feat->hit_start,
        -hend         => $feat->hit_end,
        -hstrand      => $feat->hit_strand,
        -score        => $feat->score,
        -percent_id   => $feat->percent_identity,
        -cigar_string => $feat->cigar_string,
        -analysis     => $self->Analysis_object,
    );
}


sub store_alignment_features {
  my ($self, $slice_Ad, $daf_Ad) = @_;
  my $best_daf;

  $self->fetch_Analysis_object($slice_Ad->db);

  if (my $bf = $self->best_feature) {
    my $qry_slice = $slice_Ad->fetch_by_region('clone', get_accession($self->best_feature->seq_name) );
    my $qry_seq_region_id = $qry_slice->get_seq_region_id;
    my $best_daf = $self->_make_daf_object($slice_Ad, $bf);

    # if new end_match alignment is available, it means new seq. version is available,
    # we need to remove previous best_alignment
    # ie, remove daf which hitname is not of seq_region_id = $qry_seq_region_id

    my $feats;

    eval {
      $feats = $daf_Ad->fetch_all_by_hit_name($best_daf->hseqname, $best_daf->analysis->logic_name);
    };

    my $score = $best_daf->score;

    if ( $@ ){
      my $msg = "MSG: No existing best feature found ...\n";
      $self->_print_and_log_msg($msg);

      $daf_Ad->store($best_daf);

      $msg = "MSG: Stored 1 best_overlap (score: $score) in dna_align_feature table ...\n";
      $self->_print_and_log_msg($msg);
    }
    else {
      my $hit_name = $best_daf->hseqname;
      if ( ! daf_is_duplicate($slice_Ad, $best_daf, $qry_seq_region_id) ){
        $daf_Ad->store($best_daf);

        my $msg = "MSG: Stored 1 best_overlap (score $score) in dna_align_feature table ...\n";
        $self->_print_and_log_msg($msg);
      }
      else {
        my $msg = "MSG: identical best overlap already exists ... skip\n";
        $self->_print_and_log_msg($msg);
      }
    }

    $self->_store_best_alignment($slice_Ad, $daf_Ad, $best_daf, $qry_seq_region_id);
  }

  if ($self->other_features) {
    $self->_print_and_log_msg("MSG: About to store other_overlap(s) ...\n");
    $self->_store_other_overlaps($slice_Ad, $daf_Ad, $best_daf);
  }
  else {
    $self->_print_and_log_msg("MSG: No other_overlap(s) to store ...\n");
  }
}

sub _print_and_log_msg {
  my ($self, $msg) = @_;
  warn $msg;
  $self->log_message($msg);
}

sub daf_is_duplicate {
  my ($slice_Ad, $daf, $qry_seq_region_id) = @_;
  my $check = $slice_Ad->dbc->prepare(qq{SELECT count(*)
                                         FROM dna_align_feature
                                         WHERE seq_region_id = ?
                                         AND score = ?
                                         AND hit_start = ?
                                         AND hit_end = ?
                                         AND hit_name = ?
                                         AND seq_region_start = ?
                                         AND seq_region_end = ?
                                     });
  $check->execute($qry_seq_region_id, $daf->score, $daf->hstart, $daf->hend, $daf->hseqname, $daf->start, $daf->end);

  return $check->fetchrow == 0 ? 0 : 1;
}

sub _store_best_alignment {

  my ( $self, $slice_Ad, $daf_Ad, $best_daf, $qry_seq_region_id ) = @_;

  my $hit_name = $best_daf->hseqname;

  my $dafs = $daf_Ad->fetch_all_by_hit_name($hit_name, $best_daf->analysis->logic_name);

  my $daf_id;
  foreach my $daf ( @$dafs ){
    my $qry_slice = $daf->slice;
    my $qry_srid  = $slice_Ad->get_seq_region_id($qry_slice);
    if ( $qry_srid == $qry_seq_region_id ){
      $daf_id = $daf->dbID;
      last;
    }
  }

  # record best feature in tpf_best_alignment table
  #+---------------+---------------------+------+-----+---------+-------+
  #| Field         | Type                | Null | Key | Default | Extra |
  #+---------------+---------------------+------+-----+---------+-------+
  #| seq_region_id | int(10) unsigned    |      |     | 0       |       |
  #| daf_id        | int(10)             |      |     |         |       |
  #| hit_name      | varchar(40)         |      | PRI |         |       |
  #+---------------+---------------------+------+-----+---------+-------+

  # remove best_alignment with same seq_region_id but diff. daf_id
  # as the same sequence can be in another TPF, which will have another seq_region_id
  $self->_remove_old_best_alignment($slice_Ad, $qry_seq_region_id, $hit_name);

  my $insert = $slice_Ad->dbc->prepare(qq{INSERT IGNORE INTO tpf_best_alignment VALUES (?,?,?)});
  $insert->execute($qry_seq_region_id, $daf_id, $hit_name);
  my $msg2 = "MSG: Inserted " . $insert->rows . " best_overlap (daf_id: ${daf_id}, srid: ${qry_seq_region_id}) into tpf_best_alignment table ...\n";
  $self->_print_and_log_msg($msg2);
}

sub _remove_old_best_alignment {

  my ($self, $slice_Ad, $srId, $hit_name) = @_;

  my $qry = $slice_Ad->dbc->prepare(qq{DELETE FROM tpf_best_alignment
                                       WHERE hit_name = ?
                                       AND seq_region_id = ?
                                     });
  $qry->execute($hit_name, $srId);
  my $killed = $qry->rows;

  my $msg = "MSG: Removed $killed best_alignment (hit_name = $hit_name, srid = ${srId}) from tpf_best_alignment table ...\n";
  $self->_print_and_log_msg($msg);
}

sub _store_other_overlaps {
    my ($self, $slice_Ad, $daf_Ad) = @_;

    my $other_overlaps = $self->other_features;
    return unless @$other_overlaps;

    my $qry_slice = $slice_Ad->fetch_by_region('clone', get_accession($other_overlaps->[0]->seq_name));
    my $qry_seq_region_id = $qry_slice->get_seq_region_id;

    my $count = 0;

    foreach my $ol (@$other_overlaps) {

        my $hit_name = $ol->hit_name;
        my $other_daf = $self->_make_daf_object($slice_Ad, $ol);

        if (daf_is_duplicate($slice_Ad, $other_daf, $qry_seq_region_id)) {
            my $msg = "MSG: an identical other_overlap already exists ... skip\n";
            $self->_print_and_log_msg($msg);
        }
        else {
            $count++;
            $daf_Ad->store($other_daf);
        }
    }

    $self->_print_and_log_msg("MSG: Stored $count other_overlap(s) in dna_align_feature table\n");
}

sub _get_daf_id_by_hit_name_analysis_name {
  my ( $self, $daf_Ad, $hit_name, $analysis_name ) = @_;

  my $stored_feat = $daf_Ad->fetch_all_by_hit_name($hit_name, $analysis_name);
  die "Multiple best overlap features found" if scalar @$stored_feat > 1;
  return $stored_feat->dbID;
}

sub make_alignment_from_cigar_string {

  my ( $self ) = @_;

  my $daf = $self->best_feature;
  my $qry_slice = $daf->slice;
  my $qry_seq = $qry_slice->seq;

  my $hit_seq;
  eval {
    my $hit_slice = $qry_slice->adaptor->fetch_by_region('clone', get_accession($daf->hseqname) );
    $hit_seq = $hit_slice->seq;
  };

  if ($@ ){
    my ($seq) = get_Sequences($daf->hseqname);
    $hit_seq = $seq->sequence_string;
  }

  my ($hit_align_str, $query_align_str);

  if ( $daf->strand == 1 and $daf->hstrand == -1 ) {
    $hit_seq = $self->_complement($hit_seq);
    $hit_align_str = scalar reverse substr($hit_seq, $daf->hstart-1, $daf->hend - $daf->hstart + 1);
    $query_align_str = substr($qry_seq, $daf->start-1, $daf->end - $daf->start + 1);
  }
  elsif ($daf->strand == -1 and $daf->hstrand == 1 ) {
    $qry_seq = $self->_complement($qry_seq);
    $query_align_str = scalar reverse substr($qry_seq, $daf->start-1, $daf->end - $daf->start + 1);
    $hit_align_str = substr($hit_seq, $daf->hstart-1, $daf->hend - $daf->hstart + 1);
  }
  elsif ( $daf->strand == -1 and $daf->hstrand == -1) {
    $hit_seq = $self->_complement($hit_seq);
    $hit_align_str = scalar reverse substr($hit_seq, $daf->hstart-1, $daf->hend - $daf->hstart + 1);
    $qry_seq = $self->_complement($qry_seq);
    $query_align_str = scalar reverse substr($qry_seq, $daf->start-1, $daf->end - $daf->start + 1);
  }
  else {
     $hit_align_str = substr($hit_seq, $daf->hstart-1, $daf->hend - $daf->hstart + 1);
     $query_align_str = substr($qry_seq, $daf->start-1, $daf->end - $daf->start + 1);
  }

  $self->query_align_string($query_align_str);
  $self->hit_align_string($hit_align_str);

  $query_align_str = uc $query_align_str;
  $hit_align_str   = uc $hit_align_str;

  my $hit_strand = $daf->hstrand;
  my $qry_strand = $daf->strand;

  #test
#  #warn $daf->analysis->parameters, "\n";
#  warn "Q: ", $daf->slice->seq_region_name, "\n";
#  warn "QS-E: ", $daf->start, " ", $daf->end, "\n";
#  warn "QSTR: $qry_strand\n", "\n";
#  #warn $query_align_str;
#  warn length $query_align_str;
#  warn "H: ", $daf->hseqname, "\n";
#  warn "HS-E: ", $daf->hstart, " ", $daf->hend, "\n";
#  warn "HSTR: $hit_strand\n", "\n";
#  #warn $hit_align_str;
#  warn length $hit_align_str;

  my $query_hsp = '';
  my $hit_hsp   = '';

  my @parts = ( $self->cigar_string =~ /(\d*[MDI])/g );
  unless (@parts) {
    die "Error parsing cigar_string\n";
  }

  foreach my $piece (@parts) {
    my ($length) = ( $piece =~ /^(\d*)/ );
    $length = 1 if $length eq '';

    if ($piece =~ /M$/) {
      $query_hsp .= substr($query_align_str, 0, $length);
      $hit_hsp .= substr($hit_align_str, 0, $length);
      $query_align_str = substr($query_align_str, $length);
      $hit_align_str = substr($hit_align_str, $length);
    }
    elsif ($piece =~ /I$/) {
      $hit_hsp .= '-' x $length;
      $query_hsp .= substr($query_align_str, 0, $length);
      $query_align_str = substr($query_align_str, $length);
      #print "IQ: $query\n";
      #print "IH: $hit\n";
    }
    elsif ($piece =~ /D$/) {
      $query_hsp .= '-' x $length;
      $hit_hsp .= substr($hit_align_str, 0, $length);
      $hit_align_str = substr($hit_align_str, $length);
      #print "DQ: $query\n";
      #print "DH: $hit\n";
    }
  }
  if (length($query_hsp) != length($hit_hsp) ) {
    die "Sequence length of reconstructed HSP is different!\n";
    return;
  }

  $self->_pretty_alignment($query_hsp, $hit_hsp);

  return $self;
}

sub alignment {
  my ( $self, $alignment ) = @_;
  if ($alignment) {
    $self->{'_alignment'} = $alignment;
  }
  return $self->{'_alignment'};
}

sub compact_alignment {
  my ( $self, $calignment ) = @_;
  if ($calignment) {
    $self->{'_compact_alignment'} = $calignment;
  }
  return $self->{'_compact_alignment'};
}

sub compact_alignment_length {
  my ( $self, $len ) = @_;
  if ($len) {
    $self->{'_compact_alignment_length'} = $len;
  }

  return $self->{'_compact_alignment_length'};
}

sub _pretty_alignment {

  my ($self, $query_hsp, $hit_hsp) = @_;

  my $block_len = 50; # hard-coded

  my @qry_frags = $self->_split_to_blocks($query_hsp, $block_len);
  my @hit_frags = $self->_split_to_blocks($hit_hsp, $block_len);

  my $matches = [];
  for ( my $i=0; $i < @qry_frags; $i++){

    my @qry_pieces = split('', $qry_frags[$i]);
    my @hit_pieces = split('', $hit_frags[$i]);
    my $ms = '';
    for ( my $j=0; $j < @qry_pieces ; $j++){
      my $q = $qry_pieces[$j];
      my $h = $hit_pieces[$j];
      my $m = $q eq $h ? '|' : ' ';  # matches
      $ms .= $m;
    }
    push(@$matches, $ms);
  }

  my $daf = $self->best_feature;
  my $qry_strand = $daf->strand;
  my $hit_strand = $daf->hstrand;

  # need to swap start/end for coords displayed next to alignment
  my $qry_s_coord = $daf->start;
  my $hit_s_coord = $daf->hstart;

  if ( $qry_strand == -1 ) {
    $qry_s_coord = $daf->end;
  }
  if ( $hit_strand == -1 ){
    $hit_s_coord = $daf->hend;
  }

  my $pretty_align = '';
  my $compact_pretty_align = '';
  my $compact_alignment_length = 0;
  my $last_qry_e_coord;
  my $first_qry_s_coord;
  my $cpcount; # compact align counter

  #my $padding = $self->name_padding ? '%s' : '%-20s';

  my $j = 0;
  for ( my $i=0; $i< scalar @qry_frags; $i++) {

    my $qry_hsp_frag = $qry_frags[$i];
    my $hit_hsp_frag = $hit_frags[$i];

    my ($qry_e_coord, $hit_e_coord);
    my $num_qry_indels = $qry_hsp_frag =~ tr/-/-/;
    my $num_hit_indels = $hit_hsp_frag =~ tr/-/-/;
    my $hsp_piece_len  = length $matches->[$i];
    my $qry_name = $daf->slice->seq_region_name;
    my $hit_name = $daf->hseqname;
    my $align;

    if ( $hit_strand == -1 and $qry_strand == 1 ) {
      $qry_name = "  $qry_name";
      $hit_name = "C  $hit_name";
      $hit_e_coord = $hit_s_coord - ($hsp_piece_len - $num_hit_indels) + 1;
      $qry_e_coord = $qry_s_coord + ($hsp_piece_len - $num_qry_indels) - 1;
    }
    elsif ( $hit_strand == 1 and $qry_strand == -1 ) {
      $qry_name = "C  $qry_name";
      $hit_name = "  $hit_name";
      $hit_e_coord = $hit_s_coord + ($hsp_piece_len - $num_hit_indels) - 1;
      $qry_e_coord = $qry_s_coord - ($hsp_piece_len - $num_qry_indels) + 1;
    }
    elsif ( $hit_strand == -1 and $qry_strand == -1 ){
      $qry_name = "C  $qry_name";
      $hit_name = "C  $hit_name";
      $hit_e_coord = $hit_s_coord + ($hsp_piece_len - $num_hit_indels) - 1;
      $qry_e_coord = $qry_s_coord - ($hsp_piece_len - $num_qry_indels) - 1;
    }
    else {
      $qry_e_coord = $qry_s_coord + ($hsp_piece_len - $num_qry_indels) - 1;
      $hit_e_coord = $hit_s_coord + ($hsp_piece_len - $num_hit_indels) - 1;
    }

    # should be more clever by taking padding param from constructor
    if ( $self->name_padding ){
      $align = sprintf("%s\t%d\t%s\t%d\n\t\t\t%s\n%s\t%d\t%s\t%d\n\n",
                               $qry_name, $qry_s_coord, $qry_hsp_frag, $qry_e_coord,
                               $matches->[$i],
                               $hit_name, $hit_s_coord, $hit_hsp_frag, $hit_e_coord);
      $pretty_align .= $align;
    }
    else {
      $align = sprintf("%-20s\t%d\t%s\t%d\n\t\t\t\t%s\n%-20s\t%d\t%s\t%d\n\n",
                               $qry_name, $qry_s_coord, $qry_hsp_frag, $qry_e_coord,
                               $matches->[$i],
                               $hit_name, $hit_s_coord, $hit_hsp_frag, $hit_e_coord);
      $pretty_align .= $align;
    }

    $first_qry_s_coord = $qry_s_coord if $i == 0;

    # specify the skipped part of the alignment if identical
    if ( $matches->[$i] =~ /\s/ ){
      $cpcount++;

      if ( $i == 0 ) {
        $compact_pretty_align .= $align;
      }
      elsif ( $cpcount == 1 ){
        my $skip_bps = abs($first_qry_s_coord - $qry_s_coord);
        $compact_pretty_align .= "skip $skip_bps bps 100% identity alignment\n\n" . $align;
      }
      elsif ( abs($last_qry_e_coord - $qry_s_coord) != 1 ){
        my $skip_bps = abs($last_qry_e_coord - $qry_s_coord) -1;
        $compact_pretty_align .= "skip $skip_bps bps 100% identity alignment\n\n" . $align;
      }
      else {
        $compact_pretty_align .= $align;
      }

      $compact_alignment_length += length $matches->[$i];
      $last_qry_e_coord = $qry_e_coord;
    }

    if ( $compact_pretty_align ne '' ){
      if ( $i == $#qry_frags and $last_qry_e_coord != $qry_e_coord ){
        my $skip_bps = abs($qry_e_coord - $last_qry_e_coord);
        $compact_pretty_align .= "skip $skip_bps bps 100% identity alignment\n";
      }
    }

    $j= $j+2;

    if ( $hit_strand == -1 and $qry_strand == 1 ) {
      $hit_s_coord = $hit_e_coord-1;
      $qry_s_coord = $qry_e_coord+1;
    }
    elsif ( $hit_strand == 1 and $qry_strand == -1 ) {
      $hit_s_coord = $hit_e_coord+1;
      $qry_s_coord = $qry_e_coord-1;
    }
    else {
      $qry_s_coord = $qry_e_coord+1;
      $hit_s_coord = $hit_e_coord+1;
    }
  }

  $self->compact_alignment($compact_pretty_align);
  $self->alignment($pretty_align);

  if ( $compact_pretty_align eq '' ){
    $self->compact_alignment_length(length $query_hsp);
  }
  else {
    $self->compact_alignment_length($compact_alignment_length);
  }

  return $self;
}

sub _split_to_blocks {
  my ($self, $seq, $block_len)  = @_;
  my @frags;
  while ($seq =~ /(.{1,$block_len})/g) {
    push(@frags, $1);
  }
  return @frags;
}

sub _complement {
  my ($self, $seq) = @_;
  $seq =~ tr/ACGTacgt/TGCAtgca/;
  return $seq;
}


1;

__END__

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>
