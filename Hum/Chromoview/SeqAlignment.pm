package Hum::Chromoview::SeqAlignment;

#author: ck1@sanger.ac.uk

use strict;
use warnings;
use Bio::Search::HSP::GenericHSP;
use Bio::EnsEMBL::Utils::CigarString;
use Hum::Pfetch 'get_Sequences';
use Hum::Chromoview::Utils qw(get_id_tpftargets_by_acc_sv
                              get_id_tpftargets_by_seq_region_id
                             );
use Bio::EnsEMBL::Analysis;
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

sub parse_align_string {

  # parse formats of specified algorithm
  # currently only deals with crossmatch

  my ( $self ) = @_;
  my $algorithm = $self->algorithm;
  my $feature = $self->best_feature;

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
  my $feature = $self->best_feature;

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
                # so that we will not get
                # MSG: Did not defined the number of conserved matches in the HSP assuming conserved == identical (0)
                # assign 0 to both identical and conserved for DNA comparison
                -identical    => 0,
                -conserved    => 0
               );

  my $cigar_str = Bio::EnsEMBL::Utils::CigarString->generate_cigar_string_by_hsp($hsp);
  #warn $feature->seq_name, " --- ", $feature->hit_name;
  #warn "CIGAR: $cigar_str";
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

  my ($self, $slice_Ad, $otherFeat) = @_;

  my ($cigar_str, $seqAlignFeat) = $otherFeat ? ($otherFeat->cigar_string, $otherFeat->best_feature)
                                              : ($self->cigar_string, $self->best_feature);

  my $analysis = Bio::EnsEMBL::Analysis->new
    (
     -id         => 1,
     -logic_name => $self->algorithm,
     -program    => $self->algorithm,
    );

  my $qry_slice = $slice_Ad->fetch_by_region('clone', get_accession($self->best_feature->seq_name) );

  my $daf = Bio::EnsEMBL::DnaDnaAlignFeature
    ->new(
          -slice        => $qry_slice,
          -start        => $seqAlignFeat->seq_start,
          -end          => $seqAlignFeat->seq_end,
          -strand       => $seqAlignFeat->seq_strand,
          -hseqname     => $seqAlignFeat->hit_name,
          -hstart       => $seqAlignFeat->hit_start,
          -hend         => $seqAlignFeat->hit_end,
          -hstrand      => $seqAlignFeat->hit_strand,
          -score        => $seqAlignFeat->score,
          -percent_id   => $seqAlignFeat->percent_identity,
          -analysis     => $analysis,
          -cigar_string => $cigar_str,
         );

  return $daf;
}

sub store_crossmatch_features {

  my ($self, $slice_Ad, $daf_Ad) = @_;
  my $best_daf;

  if ( $self->best_feature ){
    my $qry_slice         = $slice_Ad->fetch_by_region('clone', get_accession($self->best_feature->seq_name) );

    my $qry_seq_region_id = $qry_slice->get_seq_region_id;
    my $best_daf = $self->_make_daf_object($slice_Ad);


    # if new end_match alignment is available, it means new seq. version is available,
    # we need to remove any previous dna_align_feature and best_alignment
    # ie, remove daf which hitname is not of seq_region_id = $qry_seq_region_id

    my $feats;

    eval {
      $feats = $daf_Ad->fetch_all_by_hit_name($best_daf->hseqname, $best_daf->analysis->logic_name);
    };

    if ( $@ ){
      my $msg = "MSG: No existing best feature found ...\n";
      warn $msg;
      $self->log_message($msg);
      $daf_Ad->store($best_daf);

      $msg = "MSG: Stored 1 best_overlap in dna_align_feature table ...\n";
      warn $msg;
      $self->log_message($msg);
    }
    else {
      # check if feature exists before store to avoid duplicates
      if ( ! daf_is_duplicate($slice_Ad, $best_daf, $qry_seq_region_id) ){

        $daf_Ad->store($best_daf);
        my $msg = "MSG: Stored 1 best_overlap in dna_align_feature table ...\n";
        warn $msg;
        $self->log_message($msg);
      }
      else {
        my $msg = "MSG: Already has best_overlap, checking entry in tpf_best_alignment table ...\n";
        warn $msg;
        $self->log_message($msg);
      }
    }

    $self->_store_best_alignment($slice_Ad, $daf_Ad, $feats, $best_daf, $qry_seq_region_id);
  }

  # also store other less optimal alignments
  my $other_features = $self->other_features;
  if ( $other_features->[0] ){
    my $msg = "MSG: About to store other_overlap(s) ...\n";
    warn $msg;
    $self->log_message($msg);
    $self->_store_other_overlaps($slice_Ad, $daf_Ad, $best_daf);
  }
  else {
    my $msg = "MSG: No other_overlap(s) to store ...\n";
    warn $msg;
    $self->log_message($msg);
  }
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
  $check->fetchrow == 0 ? return 0 : 1;
}

sub _store_best_alignment {

  my ( $self, $slice_Ad, $daf_Ad, $feats, $best_daf, $qry_seq_region_id ) = @_;

  # make sure old alignments are removed
  my $hit_name = $best_daf->hseqname;
  $self->_remove_old_features($daf_Ad, $slice_Ad, $qry_seq_region_id, $feats, $hit_name);

  my $dafs = $daf_Ad->fetch_all_by_hit_name($hit_name, $best_daf->analysis->logic_name);
  my $daf_id = $dafs->[0]->dbID;

  # record best feature in tpf_best_alignment table
  #+---------------+---------------------+------+-----+---------+-------+
  #| Field         | Type                | Null | Key | Default | Extra |
  #+---------------+---------------------+------+-----+---------+-------+
  #| seq_region_id | int(10) unsigned    |      |     | 0       |       |
  #| daf_id        | int(10)             |      |     |         |       |
  #| hit_name      | varchar(40)         |      | PRI |         |       |
  #+---------------+---------------------+------+-----+---------+-------+

  my $insert = $slice_Ad->dbc->prepare(qq{INSERT IGNORE INTO tpf_best_alignment VALUES (?,?,?)});
  $insert->execute($qry_seq_region_id, $daf_id, $hit_name);
  my $msg2 = "MSG: Inserted " . $insert->rows . " best_overlap into tpf_best_alignment table ...\n";
  warn $msg2;
  $self->log_message($msg2);
}

sub _remove_old_features {

  # When sequence version is changed
  # remove old feature(s) in dna_align_feature table
  # which belong to the same TPF as the hit_name
  # because a hit_name may belong to multiple TPFs (ref. chr. and subregion)

  my ( $self, $daf_Ad, $slice_Ad, $qry_seq_region_id, $old_feats, $hit_name ) = @_;

  my $id_tpftargets = get_id_tpftargets_by_acc_sv(split(/\./, $hit_name));
  my %tpfs = map {($_, 1)} @{$id_tpftargets};

  my $old_dafs = $slice_Ad->dbc->prepare(qq{
                                            SELECT distinct seq_region_id FROM dna_align_feature
                                            WHERE hit_name = ?
                                            AND seq_region_id != ?
                                          });
  my $del_daf = $slice_Ad->dbc->prepare(qq{
                                           DELETE FROM dna_align_feature
                                           WHERE hit_name = ?
                                           AND seq_region_id = ?}
                                       );

  $old_dafs->execute($hit_name, $qry_seq_region_id);

  my @srId_to_del;

  while( my $srId = $old_dafs->fetchrow ){
    my $msg;
    my $idtpftargets = get_id_tpftargets_by_seq_region_id($srId);

    if ( $idtpftargets != 0 ){
      my $itt = $idtpftargets->[0];
      if ( $tpfs{$itt} ){
        $msg .= "Found old overlap feature(s) with seq_region_id $srId\n";
        warn $msg;
        $self->log_message($msg);
        push(@srId_to_del, $srId);
      }
    }
    else {
      $msg .= "Found old overlap feature(s) with seq_region_id $srId\n";
      warn $msg;
      $self->log_message($msg);
      push(@srId_to_del, $srId);
    }
  }

  foreach my $srId ( @srId_to_del ){
    $del_daf->execute($hit_name, $srId);
    if (  $del_daf->rows != 0 ){
      my $msg = "MSG: Removed seq_region_id $srId from dna_align_feature table ...\n";
      warn $msg;
      $self->log_message($msg);

      # also remove best_alignment with same seq_region_id
      $self->_remove_old_best_alignment($slice_Ad, $srId, $hit_name);
    }
  }

  # also check daf where seq_region_id = $qry_seq_region_id, but hit_name is not $hit_name
  # should not happen
  my $chk = $slice_Ad->dbc->prepare(qq{DELETE FROM dna_align_feature WHERE seq_region_id = ? and hit_name != ?});
  $chk->execute($qry_seq_region_id, $hit_name);
  if ( my $rows = $chk->rows >1 ){
    my $msg = "MSG: Removed $rows old dafs (hit_name != $hit_name, seq_region_id = $qry_seq_region_id) from dna_align_feature table ...\n"; 
    warn $msg;
    $self->log_message($msg);
  }
}

sub _remove_old_best_alignment {

  my ($self, $slice_Ad, $srId, $hit_name) = @_;

  my $qry = $slice_Ad->dbc->prepare(qq{DELETE FROM tpf_best_alignment WHERE seq_region_id = ? and hit_name = ?});
  $qry->execute($srId, $hit_name);
  my $killed = $qry->rows;
  if ( $killed != 0 ){
    my $msg = "MSG: Removed $killed best_alignment (hit_name = $hit_name, seq_region_id = $srId) from tpf_best_alignment table ...\n";
    warn $msg;
    $self->log_message($msg);
  }
  else {
    my $msg = "MSG: No best_alignment to remove...\n";
    warn $msg;
    $self->log_message($msg);
  }
}

sub _store_other_overlaps {

  my ($self, $slice_Ad, $daf_Ad, $best_daf) = @_;

  my $other_overlaps = $self->other_features;

  my $hit_name;

  my $qry_slice = $slice_Ad->fetch_by_region('clone', get_accession($other_overlaps->[0]->seq_name));
  my $qry_seq   = $qry_slice->seq;

  my $hit_slice = $slice_Ad->fetch_by_region('clone', get_accession($other_overlaps->[0]->hit_name));
  my $hit_seq   = $hit_slice->seq;

  my $qry_seq_region_id = $qry_slice->get_seq_region_id;

  my $count = 0;

  foreach my $ol ( @$other_overlaps ) {

    my $seqAlignFeat = Hum::Chromoview::SeqAlignment->
      new(
          algorithm      => 'crossmatch',
          best_feature   => $ol,
          query_seq      => $qry_seq,
          hit_seq        => $hit_seq,
         );

    $seqAlignFeat->parse_align_string();
    $seqAlignFeat->make_cigar_string_from_align_strings();

    #test
    #warn "QAS: ", substr($seqAlignFeat->query_align_string, 0, 50);
    #warn "HAS: ", substr($seqAlignFeat->hit_align_string, 0, 50);

    $hit_name = $ol->hit_name unless $hit_name;
    my $other_daf = $self->_make_daf_object($slice_Ad, $seqAlignFeat);

    if ( !daf_is_duplicate($slice_Ad, $other_daf, $qry_seq_region_id) ){
      $count++;
      $daf_Ad->store($other_daf);
    }
  }

  my $msg = "MSG: Stored $count other_overlap(s) in dna_align_feature table (seq_region_id: $qry_seq_region_id, hit_name: " . $hit_name . ")\n";
  warn $msg;
  $self->log_message($msg);
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

sub compact_alignment_verbose {
  my ( $self, $calignment ) = @_;
  if ($calignment) {
    $self->{'_compact_alignment_verbose'} = $calignment;
  }
  return $self->{'_compact_alignment_verbose'};
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
  my $compact_pretty_aligns = [];
  my $compact_alignment_length = 0;

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
      $align = sprintf("%s\t%d\t%s\t%d\n\t\t\t%s\n%s\t%d\t%s\t%d\n\n\n",
                               $qry_name, $qry_s_coord, $qry_hsp_frag, $qry_e_coord,
                               $matches->[$i],
                               $hit_name, $hit_s_coord, $hit_hsp_frag, $hit_e_coord);
      $pretty_align .= $align;
    }
    else {
      $align = sprintf("%-20s\t%d\t%s\t%d\n\t\t\t\t%s\n%-20s\t%d\t%s\t%d\n\n\n",
                               $qry_name, $qry_s_coord, $qry_hsp_frag, $qry_e_coord,
                               $matches->[$i],
                               $hit_name, $hit_s_coord, $hit_hsp_frag, $hit_e_coord);
      $pretty_align .= $align;
    }

    if ( $matches->[$i] =~ /\s/ ){
      push(@$compact_pretty_aligns, $align);
      $compact_alignment_length += length $matches->[$i];
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

  $self->compact_alignment(join("",@$compact_pretty_aligns));
  $self->compact_alignment_verbose(join("<<skip 100% identity>>\n\n", @$compact_pretty_aligns));
  $self->alignment($pretty_align);
  $self->compact_alignment_length($compact_alignment_length);

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
