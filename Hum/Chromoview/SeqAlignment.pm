
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

sub verbose {
  my ( $self, $verbose ) = @_;
  if (defined($verbose)) {
    $self->{'_verbose'} = $verbose;
  }
  # Default of 1
  if(!exists($self->{'_verbose'})) {
	  $self->{'_verbose'} = 1;
  }
  return $self->{'_verbose'};
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

sub store_certificate_code {
	my ($self, $db_handle, $dna_align_feature_id, $code) = @_;
	
	my $certificate_storage_sql = "INSERT INTO tpf_certificate (dna_align_feature_id, code) VALUES (?,?)";
	my $certificate_storage_handle = $db_handle->prepare($certificate_storage_sql);
	$certificate_storage_handle->execute($dna_align_feature_id, $code);
	
	return;
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
      if(defined($bf->certificate_code)) {
      	$self->store_certificate_code($daf_Ad->dbc->db_handle, $best_daf->dbID, $bf->certificate_code);
      }

      $msg = "MSG: Stored 1 best_overlap (score: $score) in dna_align_feature table ...\n";
      $self->_print_and_log_msg($msg);
    }
    else {
      my $hit_name = $best_daf->hseqname;
      if ( ! daf_is_duplicate($slice_Ad, $best_daf, $qry_seq_region_id) ){
        $daf_Ad->store($best_daf);
        if($bf->can('certificate_code') and defined($bf->certificate_code)) {
      		$self->store_certificate_code($daf_Ad->dbc->db_handle, $best_daf->dbID, $bf->certificate_code);
      	}
        

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
  if($self->verbose) {
  	warn $msg;
  }
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
  $self->_remove_old_best_alignment_both_ways($slice_Ad, $qry_seq_region_id, $hit_name);

  my $insert = $slice_Ad->dbc->prepare(qq{INSERT IGNORE INTO tpf_best_alignment VALUES (?,?,?)});
  $insert->execute($qry_seq_region_id, $daf_id, $hit_name);
  my $msg2 = "MSG: Inserted " . $insert->rows . " best_overlap (daf_id: ${daf_id}, srid: ${qry_seq_region_id}) into tpf_best_alignment table ...\n";
  $self->_print_and_log_msg($msg2);
}

sub _remove_old_best_alignment_both_ways {
	my ($self, $slice_Ad, $srId, $hit_name) = @_;
	
	$self->_remove_old_best_alignment($slice_Ad, $srId, $hit_name);
	
	my $hit_srId_arrayref = $slice_Ad->dbc->db_handle->selectcol_arrayref(qq{
		SELECT seq_region_id FROM seq_region WHERE name = '$hit_name'
	});
	
	my $slice_name_arrayref = $slice_Ad->dbc->db_handle->selectcol_arrayref(qq{
		SELECT name FROM seq_region WHERE seq_region_id = $srId
	});
	
	if(exists($hit_srId_arrayref->[0]) and exists($slice_name_arrayref->[0])) {
		$self->_remove_old_best_alignment($slice_Ad, $hit_srId_arrayref->[0], $slice_name_arrayref->[0]);
	}
	
	return;
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
            if(defined($ol->certificate_code)) {
      			$self->store_certificate_code($daf_Ad->dbc->db_handle, $other_daf->dbID, $ol->certificate_code);
      		}
            
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

sub make_hsps {
	my ($self) = @_;
	
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

  $query_align_str = uc $query_align_str;
  $hit_align_str   = uc $hit_align_str;

  my $hit_strand = $daf->hstrand;
  my $qry_strand = $daf->strand;

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
  $self->query_hsp($query_hsp);
  $self->hit_hsp($hit_hsp);
  
  return;
}

sub alignment {
  my ( $self, $alignment ) = @_;
  if ($alignment) {
    $self->{'_alignment'} = $alignment;
  }
  elsif(!defined($self->{'_alignment'})) {
	$self->_pretty_alignment();
  }
  
  return $self->{'_alignment'};
}

sub html_alignment_with_repeats {
  my ( $self, $html_alignment_with_repeats ) = @_;
  if ($html_alignment_with_repeats) {
    $self->{'_html_alignment_with_repeats'} = $html_alignment_with_repeats;
  }
  elsif(!defined($self->{'_html_alignment_with_repeats'})) {
	$self->_pretty_alignment('REPEATS');
  }
  
  return $self->{'_html_alignment_with_repeats'};
}

sub compact_alignment {
  my ( $self, $calignment ) = @_;
  if (defined($calignment)) {
    $self->{'_compact_alignment'} = $calignment;
  }
  elsif(!defined($self->{'_compact_alignment'})) {
	$self->_pretty_alignment();
  }
  
  return $self->{'_compact_alignment'};
}

sub compact_html_alignment_with_repeats {
  my ( $self, $calignment ) = @_;
  if (defined($calignment)) {
    $self->{'_compact_html_alignment_with_repeats'} = $calignment;
  }
  elsif(!defined($self->{'_compact_html_alignment_with_repeats'})) {
	$self->_pretty_alignment('REPEATS');
  }
  
  return $self->{'_compact_html_alignment_with_repeats'};
}


sub compact_alignment_length {
  my ( $self, $len ) = @_;
  if ($len) {
    $self->{'_compact_alignment_length'} = $len;
  }
  elsif(!defined($self->{'_compact_alignment_length'})) {
	$self->_pretty_alignment();
  }

  return $self->{'_compact_alignment_length'};
}

sub query_hsp {
  my ( $self, $query_hsp ) = @_;
  if ($query_hsp) {
    $self->{'_query_hsp'} = $query_hsp;
  }
  elsif(!defined($self->{'_query_hsp'})) {
	$self->make_hsps();
  }
  
  return $self->{'_query_hsp'};
}

sub hit_hsp {
  my ( $self, $hit_hsp ) = @_;
  if ($hit_hsp) {
    $self->{'_hit_hsp'} = $hit_hsp;
  }
  elsif(!defined($self->{'_hit_hsp'})) {
	$self->make_hsps();
  }
  
  return $self->{'_hit_hsp'};
}

sub _pretty_alignment {

  my ($self, $repeat_flag) = @_;

  my $block_len = 50; # hard-coded

  my @qry_frags = $self->_split_to_blocks($self->query_hsp, $block_len);
  my @hit_frags = $self->_split_to_blocks($self->hit_hsp, $block_len);

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

	# Insert repeat HTML if requested
	if($repeat_flag) {
		$qry_hsp_frag = $self->add_repeat_html('QUERY', $qry_hsp_frag, $qry_strand, $qry_s_coord);
		$hit_hsp_frag = $self->add_repeat_html('HIT', $hit_hsp_frag, $hit_strand, $hit_s_coord);
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

	if($repeat_flag) {
	  $self->compact_html_alignment_with_repeats($compact_pretty_align);
	  $self->html_alignment_with_repeats($pretty_align);
	}
	else {
	  $self->compact_alignment($compact_pretty_align);
	  $self->alignment($pretty_align);
	}

  if ( $compact_pretty_align eq '' ){
    $self->compact_alignment_length(length $self->query_hsp);
  }
  else {
    $self->compact_alignment_length($compact_alignment_length);
  }


  return $self;
}

sub repeat_termini {
	my ($self, $slice) = @_;
  		
  	my %repeat_termini;
  	
	if(defined($slice)) {  	
		my @repeats = @{ $slice->get_all_RepeatFeatures };
	  	foreach my $repeat (@repeats) {
	  		push(
	  			@{ $repeat_termini{$repeat->start}{START} },
	  			$repeat,
	  		);
	  		push(
	  			@{ $repeat_termini{$repeat->end+1}{END} },
	  			$repeat,
	  		);
	  	}
	}
  	
  	return \%repeat_termini;
}

sub add_repeat_html {
	my ($self, $type, $hsp_frag, $strand, $coord) = @_;
	
	my $hsp_frag_with_repeats;

	# Get a slice corresponding to this frag
	my $slice;
	
	if($type eq 'QUERY') {
		$slice = $self->best_feature->slice;
	}
	elsif($type eq 'HIT') {
		$slice = $self->best_feature->slice->adaptor->fetch_by_region('clone', get_accession($self->best_feature->hseqname) );
	}
	else {
		confess "Non-standard type $type\n";
	}
	
	my @bases =  $hsp_frag =~ /[^-]/g;
	my $fragment_length = scalar @bases;
	
	# Treat fragment-length as 1 to handle all-gap rows
	if($fragment_length == 0) {$fragment_length = 1}
	
	my ($fragment_start, $fragment_end);
	if($strand == 1) {
		$fragment_start = $coord;
		$fragment_end = $coord+$fragment_length-1;
	}
	else {
		$fragment_start = $coord - $fragment_length + 1;
		$fragment_end = $coord;
	}
	
	my $fragment_slice = $slice->sub_Slice($fragment_start, $fragment_end, $strand);
	
	my @fragment_list = split(//, $hsp_frag);
	
	# Go through all repeats
	my %repeat_termini = %{ $self->repeat_termini($fragment_slice) };
	
	my $next_fragment_position;

	my %repeat_names;
	my $open_tag_flag = 0;
	
	REPEAT_TERMINUS_POSITION: foreach my $repeat_terminus_position (sort {$a <=> $b} keys %repeat_termini) {

		my @previous_repeat_names = keys %repeat_names;
		
		foreach my $terminus (sort sort_start_end keys %{$repeat_termini{$repeat_terminus_position}}) {
			
			# Keep track of the present set of repeats
			foreach my $repeat (@{$repeat_termini{$repeat_terminus_position}{$terminus}}) {		
				if($terminus eq 'START') {
					$repeat_names{ $repeat->display_id } = 1;
				}
				else {
					delete($repeat_names{ $repeat->display_id });
				}
			}
		}
			
		# Is the terminus within the present alignment-fragment?
		if(
			$repeat_terminus_position > 0
		) {
			# Add start tag at beginning of string if necessary
			if(
				!defined($next_fragment_position)
			) {
				if($fragment_list[0] !~ /-/) {
					$next_fragment_position = 1;
				}
				else {
					$next_fragment_position = 0;
				}
				
				if(
					@previous_repeat_names > 0
					and $repeat_terminus_position > 1
				) {
					$hsp_frag_with_repeats .= tag_for_repeat_names(sort @previous_repeat_names);
					$open_tag_flag = 1;
				}
			}
			
			if($repeat_terminus_position <= $fragment_length) {
	
				while($next_fragment_position < $repeat_terminus_position and scalar @fragment_list > 0) {
					my $fragment_character = shift(@fragment_list);
					$hsp_frag_with_repeats .= $fragment_character;
					if(scalar @fragment_list > 0 and $fragment_list[0] !~ /-/) {
						$next_fragment_position++;
					}
				}
			
			#	my $substring_length = $repeat_terminus_position - $last_fragment_position;
			#	$hsp_frag_with_repeats .= substr($hsp_frag, $last_fragment_position, $substring_length);
			#	$last_fragment_position += $substring_length;
				
				if($open_tag_flag) {
					$hsp_frag_with_repeats .= "</SPAN>";
				}
				if(scalar keys %repeat_names > 0) {
					$hsp_frag_with_repeats .= tag_for_repeat_names(sort keys %repeat_names);
					$open_tag_flag = 1;
				}
				else {
					$open_tag_flag = 0;
				}
			}
			# If this position is higher than the end of the fragment, we can end the loop
			else {
				last REPEAT_TERMINUS_POSITION;
			}
		}
	}
	
	# Add on any remaining fragment
	$hsp_frag_with_repeats .= join('', @fragment_list);
	
	# Add a closing tag if necessary
	if($open_tag_flag) {
		$hsp_frag_with_repeats .= "</SPAN>";
	}
	
	return $hsp_frag_with_repeats;
}

sub tag_for_repeat_names {
	my (@repeat_names) = @_;
	my $repeat_name_string = join(' ', @repeat_names);
	return qq(<SPAN class="repeat" title="$repeat_name_string">);
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

# We need to sort ENDS before STARTS for a given terminus-position
sub sort_start_end {
	if($a eq 'START' and $b eq 'END') {return 1}
	elsif($a eq 'END' and $b eq 'START') {return -1}
	else {return 0}
}

1;

__END__

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>
