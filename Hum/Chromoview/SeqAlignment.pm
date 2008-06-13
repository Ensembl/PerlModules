
package Hum::Chromoview::SeqAlignment;

#author: ck1@sanger.ac.uk

use strict;
use warnings;
use Bio::Search::HSP::GenericHSP;
use Bio::EnsEMBL::Utils::CigarString;
use Hum::Pfetch 'get_Sequences';

use DBI;

sub new {
  my( $pkg, @data ) = @_;

  my $self = {};
  for (my $i=0; $i<scalar @data; $i=$i+2) {
    my $method = "_$data[$i]";
    $self->{$method} = $data[$i+1];
  }

  return bless $self, $pkg;
}

sub algorithm {
  my ( $self, $name ) = @_;
  if ($name) {
    $self->{'_algorithm'} = $name;
  }
  return $self->{'_algorithm'};
}

sub feature {
  my ( $self, $align_feat ) = @_;
  if ($align_feat ){
    $self->{'_feature'} = $align_feat;
  }

  return $self->{'_feature'};
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

sub parse_align_string {

  # parse formats of specified algorithm
  # currently only deals with crossmatch

  my ( $self ) = @_;
  my $algorithm = $self->algorithm;
  my $feature = $self->feature;

  if ( $algorithm eq 'crossmatch' ){

    my $qry_aln = '';
    my $hit_aln = '';
    my $count = 0;

    foreach ( split(/\n/, $feature->alignment_string) ){

      #  AP003795.2           1 AAGCTTCCTGTGATGCTGGGGTGGAAGCTGTACTCCTCCCAGCCCTTCTC 50
      # there is one field before ACC which is used for revcomp, if applied

      my @fields = split(/\s+/, $_);
      next if $_ !~ /.*\.\d+.*[ATCG-]*/;

      $count++;

      if ( $count % 2 == 0){
        $hit_aln .= $fields[3];
        #print "S: ", length $fields[3], "\n";
        #print "S: ", $fields[3], "\n";
      }
      else {
        $qry_aln .= $fields[3];
        #print "Q: ", length $fields[3], "\n";
        #print "Q: ", $fields[3], "\n";
      }
    }

    #-----------------------------------------------------------------------------------
    # crossmatch hack
    # NOTE: crossmatch displays the alignment differently as the match coords line
    # eg
    # identity  query        start    end    subject     start    end    strand
    #--------  ----------------------------- -------------------------------------
    # 98.88%    AP003796.2   1        90648  BX640404.2  1        90774  -

    #C AP003796.2       90648 AAGCTTGTACAGAGGGGAAAAATAATTGAGGATGGTGTTATTAGTGGAAT 90599
    #  BX640404.2           1 AAGCTTGTACAGAGGGGAAAAATAATTGAGGATGGTGTTATTAGTGGAAT 50
    #-----------------------------------------------------------------------------------

    if ( $feature->seq_strand != $feature->hit_strand ){
      # revcomp both query_alignment and hit_alignment
      $qry_aln = $self->_revcomp($qry_aln);
      $hit_aln = $self->_revcomp($hit_aln);
    }

    $self->query_align_string($qry_aln);
    $self->hit_align_string($hit_aln);
    #warn "Q_len: ", length $qry_aln;
    #warn "H_len: ", length $hit_aln;

    return $self;
  }
  else {
    die "Don't know how to parse $algorithm alignment format";
  }
}

sub name_padding {
  my ( $self, $padding ) =@_;
  if ($padding) {
    $self->{'_name_padding'} = $padding;
  }
  return $self->{'_name_padding'};
}

sub query_align_string {
  my ( $self, $align_str ) =@_;
  if ($align_str) {
    $self->{'_query_align_string'} = $align_str;
  }
  return $self->{'_query_align_string'};
}

sub hit_align_string {
  my ( $self, $align_str ) =@_;
  if ($align_str) {
    $self->{'_hit_align_string'} = $align_str;
  }
  return $self->{'_hit_align_string'};
}

sub make_cigar_string_from_align_strings {

  my ( $self ) = @_;
  my $feature = $self->feature;

  my $hsp = new Bio::Search::HSP::GenericHSP
               (
                -score        => $feature->score,
                -hsp_length   => length $self->query_align_string,
                -query_name   => $feature->seq_name,
                -query_start  => $feature->seq_start,
                -query_end    => $feature->seq_end,
                -hit_name     => $feature->hit_name,
                -hit_start    => $feature->hit_start,
                -hit_end      => $feature->hit_end,
                -hit_length   => length $self->hit_seq,
                -query_length => length $self->query_seq,
                # query gapped sequence portion of the HSP
                -query_seq    => $self->query_align_string,
                # hit   gapped sequence portion of the HSP
                -hit_seq      => $self->hit_align_string,
               );

  my $cigar_str = Bio::EnsEMBL::Utils::CigarString->generate_cigar_string_by_hsp($hsp);
  warn $feature->seq_name, " --- ", $feature->hit_name;
  warn "CIGAR: $cigar_str";
  $self->cigar_string($cigar_str);

  return $self;
}

sub cigar_string {
  my ( $self, $cigar_str ) = @_;
  if ($cigar_str) {
    $self->{'_cigar_string'} = $cigar_str;
  }
  return $self->{'_cigar_string'};
}

sub _make_daf_object {

  my ($self, $crossMatch_feat, $slice_Ad) = @_;

  my $analysis = Bio::EnsEMBL::Analysis->new
    (
     -id         => 1,
     -logic_name => $self->algorithm,
     -program    => $self->algorithm,
    );

  my $slice = $slice_Ad->fetch_by_region('clone', $crossMatch_feat->seq_name);
  #warn %$slice;

  my $daf = Bio::EnsEMBL::DnaDnaAlignFeature
    ->new(
          -slice        => $slice,
          -start        => $crossMatch_feat->seq_start,
          -end          => $crossMatch_feat->seq_end,
          -strand       => $crossMatch_feat->seq_strand,
          -hseqname     => $crossMatch_feat->hit_name,
          -hstart       => $crossMatch_feat->hit_start,
          -hend         => $crossMatch_feat->hit_end,
          -hstrand      => $crossMatch_feat->hit_strand,
          -score        => $crossMatch_feat->score,
          -percent_id   => $crossMatch_feat->percent_identity,
          -analysis     => $analysis,
          -cigar_string => $self->cigar_string,
         );

  return $daf;
}

sub store_crossmatch_feature_if_new {
  # daf: dna_align_feature
  my ($self, $slice_Ad, $daf_Ad, $matched_end_feats) = @_;

  my $daf = $self->_make_daf_object($self->feature, $slice_Ad);

  # check existence of best overlap with same hit_name, remove if found
  if (my $feats = $daf_Ad->fetch_all_by_hit_name($daf->hseqname, $daf->analysis->logic_name) ) {
     $self->_remove_old_features($daf_Ad, $feats);
  }

  $daf_Ad->store($daf);
  warn "MSG: Stored 1 best_overlap in dna_align_feature table ...\n";

  my $seq_region_id = $slice_Ad->get_seq_region_id($daf->slice);
  my $dafs = $daf_Ad->fetch_all_by_hit_name($daf->hseqname, $daf->analysis->logic_name);
  my $daf_id = $dafs->[0]->dbID;

  # record best feature in best_alignment table
  #+---------------+---------------------+------+-----+---------+-------+
  #| Field         | Type                | Null | Key | Default | Extra |
  #+---------------+---------------------+------+-----+---------+-------+
  #| seq_region_id | int(10) unsigned    |      |     | 0       |       |
  #| daf_id        | int(10)             |      |     |         |       |
  #+---------------+---------------------+------+-----+---------+-------+

  my $insert = $daf_Ad->dbc->prepare(qq{INSERT INTO best_alignment VALUES (?,?)});
  my $row = $insert->execute($seq_region_id, $daf_id);
  warn "MSG: Inserted $row best_overlap into best_alignment table ...\n";

  # also store other less optimal alignments
  if ( scalar @$matched_end_feats > 2 ) {
    $self->_record_other_overlaps($slice_Ad, $daf_Ad, $matched_end_feats, $daf);
  }
}

sub _remove_old_features {

  # remove old feature in dna_align_feature table and other_overlaps tables
  my ( $self, $daf_Ad, $old_feats ) = @_;

  warn "MSG: Found ", scalar @$old_feats, " old dafs to remove...\n";
  return unless $old_feats->[0];

  my $del = 0;
  my $seq_region_id;
  foreach my $feat ( @$old_feats ){
    $seq_region_id = $feat->slice->adaptor->get_seq_region_id($feat->slice);
    $daf_Ad->remove($feat);
    $del++;
  }
  warn "MSG: Removed $del old dafs (seq_region_id: $seq_region_id) from dna_align_feature table ...\n";

  my $row = $daf_Ad->dbc->do(qq{DELETE FROM best_alignment WHERE seq_region_id = $seq_region_id});
  $row = 0 if $row < 1;
  warn "MSG: Removed $row old best_alignment from best_alignment table ...\n";
}

sub _record_other_overlaps {

  my ($self, $slice_Ad, $daf_Ad, $other_overlaps, $best_daf) = @_;

  my $qry_slice = $best_daf->slice;
  my $qry_seq   = $qry_slice->seq;

  my $hit_slice = $qry_slice->adaptor->fetch_by_region('clone', $best_daf->hseqname);
  my $hit_seq   = $hit_slice->seq;

  #do not want to store $best_feat again
  #my $best_str = $self->_stringified($best_feat, qw(start end strand hstart hend hstrand));

  my $seq_region_id = $slice_Ad->get_seq_region_id($qry_slice);

  my $count = 0;
  foreach my $ol ( @$other_overlaps ) {

    #my $ol_str = $self->_stringified($ol, qw(seq_start seq_end seq_strand hit_start hit_end hit_strand) );
    #next if $ol_str eq $best_str;

    my $alignment = Hum::Chromoview::SeqAlignment->
      new(
          algorithm => 'crossmatch',
          feature   => $ol,
          query_seq => $qry_seq,
          hit_seq   => $hit_seq,
         );

    $alignment->parse_align_string();
    $alignment->make_cigar_string_from_align_strings();

    my $other_daf = $self->_make_daf_object($ol, $slice_Ad);
    $daf_Ad->store($other_daf);

    $count++;
  }
  warn "MSG: Stored $count other_overlap(s) in dna_align_feature table (seq_region_id: $seq_region_id) . . .\n";
}

sub _stringified {
  my ($self, $feat, @methods) = @_;

  my $str = '';
  foreach ( @methods ) {
    $str .= $feat->$_;
  }
  return $str;
}

sub _get_daf_id_by_hit_name_analysis_name {
  my ( $self, $daf_Ad, $hit_name, $analysis_name ) = @_;

  my $stored_feat = $daf_Ad->fetch_all_by_hit_name($hit_name, $analysis_name);
  die "Multiple best overlap features found" if scalar @$stored_feat > 1;
  return $stored_feat->dbID;
}

sub make_alignment_from_cigar_string {

  my ( $self ) = @_;

  my $daf = $self->feature;
  my $qry_slice = $daf->slice;
  my $qry_seq = $qry_slice->seq;

  my $hit_seq;
  eval {
    my $hit_slice = $qry_slice->adaptor->fetch_by_region('clone', $daf->hseqname);
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

  $query_align_str = uc $query_align_str;
  $hit_align_str   = uc $hit_align_str;

  my $hit_strand = $daf->hstrand;
  my $qry_strand = $daf->strand;

#  #warn $daf->analysis->parameters, "\n";
#  warn "Q: ", $daf->slice->seq_region_name, "\n";
#  warn "QS-E: ", $daf->start, " ", $daf->end, "\n";
#  warn "QSTR: $qry_strand\n", "\n";
##  warn $query_align_str;
#  warn "H: ", $daf->hseqname, "\n";
#  warn "HS-E: ", $daf->hstart, " ", $daf->hend, "\n";
#  warn "HSTR: $hit_strand\n", "\n";
##  warn $hit_align_str;

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

  my $daf = $self->feature;
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
      my $align = sprintf("%s\t%d\t%s\t%d\n\t\t\t%s\n%s\t%d\t%s\t%d\n\n\n",
                               $qry_name, $qry_s_coord, $qry_hsp_frag, $qry_e_coord,
                               $matches->[$i],
                               $hit_name, $hit_s_coord, $hit_hsp_frag, $hit_e_coord);
      $pretty_align .= $align;
      $compact_pretty_align .= $align if $matches->[$i] =~ /\s/;
    }
    else {
      my $align = sprintf("%-20s\t%d\t%s\t%d\n\t\t\t\t%s\n%-20s\t%d\t%s\t%d\n\n\n",
                               $qry_name, $qry_s_coord, $qry_hsp_frag, $qry_e_coord,
                               $matches->[$i],
                               $hit_name, $hit_s_coord, $hit_hsp_frag, $hit_e_coord);
      $pretty_align .= $align;
      $compact_pretty_align .= $align if $matches->[$i] =~ /\s/;
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

sub _revcomp {
  my ($self, $seq) = @_;
  my $revcomp = reverse $seq;
  $revcomp =~ tr/ACGTacgt/TGCAtgca/;
  return $revcomp;
}

sub _complement {
  my ($self, $seq) = @_;
  $seq =~ tr/ACGTacgt/TGCAtgca/;
  return $seq;
}


1;
