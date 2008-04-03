
### Hum::Ace::SubSeq

package Hum::Ace::SubSeq;

use strict;
use Carp;

use Hum::Sequence::DNA;
use Hum::Ace::Exon;
use Hum::XmlWriter;

sub new {
    my( $pkg ) = @_;
    
    return bless {
        '_Exon_list'    => [],
        '_is_sorted'    => 0,
        }, $pkg;
}

sub new_from_ace_subseq_tag {
    my( $pkg, $ace_trans ) = @_;
    
    # Make a SubSeq object
    my $sub = $pkg->new;
    
    $sub->process_ace_transcript($ace_trans);
    
    return $sub;
}

# This is used by realignGenes
sub new_from_start_end_fox_subseq {
    my( $pkg, $start, $end, $sub ) = @_;
    
    my $self = $pkg->new;
    my $name = $sub->name;
    $self->name($name);
    my $txt = $sub->mutable_data;

    # Sort out the strand
    my( $strand );
    if ($start < $end) {
        $strand = 1;
    } else {
        ($start, $end) = ($end, $start);
        $strand = -1;
    }
    $self->strand($strand);

    # Make the exons
    foreach my $ints ($txt->get_values('Source_exons')) {
        
        # Make an Exon object
        my $exon = Hum::Ace::Exon->new;
        
        my ($x, $y) = @$ints;
        die "Missing coordinate in '$name' : start='$x' end='$y'\n"
            unless $x and $y;
        if ($strand == 1) {
            foreach ($x, $y) {
                $_ = $start + $_ - 1;
            }
        } else {
            foreach ($x, $y) {
                $_ = $end - $_ + 1;
            }
            ($x, $y) = ($y, $x);
        }
        $exon->start($x);
        $exon->end($y);
        $self->add_Exon($exon);
    }
    
    # Parse Contines_from and Continues_as
    if (my ($from) = $txt->get_values('Continued_from')) {
        $self->upstream_subseq_name($from->[0]);
    }
    if (my ($as) = $txt->get_values('Continues_as')) {
        $self->downstream_subseq_name($as->[0]);
    }

    ## Parse Supporting evidence tags
    #foreach my $type (qw{ Protein_match EST_match cDNA_match }) {
    #    foreach my $evidence ($txt->get_values($type)) {
    #    $self->add_SupportingEvidence_accession($type, @$evidence);
    #    }
    #}
    
    my @exons = $self->get_all_Exons
        or confess "No exons in '", $self->name, "'";

    # Add CDS coordinates
    if (my ($cds) = $txt->get_values('CDS')) {
        if (@$cds == 2) {
            $self->set_translation_region_from_cds_coords(@$cds);
        }
        elsif (@$cds != 0) {
            warn "ERROR: Got ", scalar(@$cds), " coordinates from CDS tag";
        }
    }

    # Is this a partial CDS?
    my $s_n_f = $txt->count_tag('Start_not_found');
    my ($snf_val) = $txt->get_values('Start_not_found');
    my $codon_start = $snf_val->[0] if $snf_val;
    if ($s_n_f) {
        # Store phase in AceDB convention (not EnsEMBL)
        $codon_start ||= 1;
        if ($codon_start and $txt->count_tag('CDS')) {
            if ($codon_start =~ /^[123]$/) {
                $self->start_not_found($codon_start);
            } else {
                confess("Bad codon start ('$codon_start') in '$name'");
            }
        }
    }

    # Are we missing the 3' end?
    if ($txt->count_tag('End_not_found')) {
        $self->end_not_found(1);
    }

    $self->validate;
    
    return $self;
}

sub new_from_name_start_end_transcript_seq {
    my( $pkg, $name, $start, $end, $t_seq ) = @_;
    
    my $self = $pkg->new;
    $self->name($name);
    $self->process_ace_start_end_transcript_seq($start, $end, $t_seq);
    return $self;
}

sub process_ace_transcript {
    my( $self, $t ) = @_;
    
    $self->name($t->name);
    # Get coordinates of Subsequence in parent
    my ($start, $end) = map $_->name, $t->row(1);
    die "Missing coordinate for '$t'\n"
        unless $start and $end;
        
    # Fetch the Subsequence object
    my $t_seq = $t->fetch;
    
    $self->process_ace_start_end_transcript_seq($start, $end, $t_seq);
}

sub process_ace_start_end_transcript_seq {
    my( $self, $start, $end, $t_seq ) = @_;

    # Sort out the strand
    my( $strand );
    if ($start < $end) {
        $strand = 1;
    } else {
        ($start, $end) = ($end, $start);
        $strand = -1;
    }
    $self->strand($strand);
    
    if (my $otter_id = $t_seq->at('Otter.Transcript_id[1]')) {
        $self->otter_id($otter_id->name);
    }
    
    # Make the exons
    foreach ($t_seq->at('Structure.From.Source_exons[1]')) {
        
        # Make an Exon object
        my $exon = Hum::Ace::Exon->new;
        
        my ($x, $y, $ott) = map $_->name, $_->row;
        die "Missing coordinate in '$t_seq' : start='$x' end='$y'\n"
            unless $x and $y;
        if ($strand == 1) {
            foreach ($x, $y) {
                $_ = $start + $_ - 1;
            }
        } else {
            foreach ($x, $y) {
                $_ = $end - $_ + 1;
            }
            ($x, $y) = ($y, $x);
        }
        $exon->start($x);
        $exon->end($y);
        $exon->otter_id($ott);
        
        $self->add_Exon($exon);
    }
    
    # Parse Contined_from and Continues_as
    if (my ($from) = $t_seq->at('Structure.Continued_from[1]')) {
        $self->upstream_subseq_name($self->strip_Em($from));
    }
    if (my ($as) = $t_seq->at('Structure.Continues_as[1]')) {
        $self->downstream_subseq_name($self->strip_Em($as));
    }

    # Remarks
    my( @remarks );
    foreach my $rem ($t_seq->at('Visible.Remark[1]')) {
        push(@remarks, $rem->name);
    }
    foreach my $title ($t_seq->at('Visible.Title[1]')) {
        push(@remarks, $title->name);
    }
    $self->set_remarks(@remarks);
    
    my( @annotation_remarks );
    foreach my $rem ($t_seq->at('Annotation.Annotation_remark[1]')) {
        push(@annotation_remarks, $rem->name);
    }
    $self->set_annotation_remarks(@annotation_remarks);

    # Parse Supporting evidence tags
    foreach my $type (qw{ Protein EST cDNA Genomic }) {
        my $tag = "${type}_match";
        my $list = [];
        foreach my $evidence ($t_seq->at('Annotation.Sequence_matches.' . $tag . '[1]')) {
            my $id = $evidence->name;
            #print STDERR qq{Got Evidence: $type "$id"\n};
            push(@$list, $id) if $id;
        }
        $self->add_evidence_list($type, $list) if @$list;
    }
    
    my @exons = $self->get_all_Exons
        or confess "No exons in '", $self->name, "'";

    # Add CDS coordinates
    if (my $cds = $t_seq->at('Properties.Coding.CDS[1]')) {
        my @cds_coords = map $_->name, $cds->row;
        if (@cds_coords == 2) {
            $self->set_translation_region_from_cds_coords(@cds_coords);
        } else {
            warn "ERROR: Got ", scalar(@cds_coords), " coordinates from Properties.Coding.CDS";
        }
    }

    # Is this a partial CDS?
    my( $s_n_f, $codon_start );
    eval{ ($s_n_f, $codon_start) = map "$_", $t_seq->at('Properties.Start_not_found')->row() };
    if ($s_n_f) {
        # Store phase in AceDB convention (not EnsEMBL)
        $codon_start ||= 1;
        if ($t_seq->at('Properties.Coding.CDS')) {
            if ($codon_start =~ /^[123]$/) {
                $self->start_not_found($codon_start);
            } else {
                confess("Bad codon start ('$codon_start') in '$t_seq'");
            }
        }
    }

    # Are we missing the 3' end?
    if ($t_seq->at('Properties.End_not_found')) {
        $self->end_not_found(1);
    }
 
    $self->validate;
}

sub strip_Em {
    my( $self, $ace_obj ) = @_;
    
    my $name = $ace_obj->name;
    $name =~ s/^em://i;
    return $name;
}

sub take_otter_ids {
    my( $self, $old ) = @_;
    
    $self->otter_id($old->otter_id);

    my @new_exons = $self->get_all_Exons;
    my @old_exons =  $old->get_all_Exons;
    # Loop through all the new exons
    for (my $i = 0; $i < @new_exons; $i++) {
        my $n_ex = $new_exons[$i];
        for (my $j = 0; $j < @old_exons; ) {
            my $o_ex = $old_exons[$j];
            if ($n_ex->overlaps($o_ex)) {
                # Remove old exons from the list as
                # they are matched with a new exon
                $n_ex->otter_id($o_ex->otter_id);
                splice(@old_exons, $j, 1);
            } else {
                $j++;
            }
        }
    }
    if (@old_exons) {
        warn "Failed to remap ", scalar(@old_exons), " Otter IDs to new exons\n";
    }
}

sub clone {
    my( $old ) = @_;
    
    # Make new SubSeq object
    my $new = ref($old)->new;
    
    # Copy scalar fields (But not is_archival!)
    foreach my $meth (qw{
        name
        otter_id
        clone_Sequence
        GeneMethod
        Locus
        strand
        start_not_found
          end_not_found
        upstream_subseq_name
        downstream_subseq_name
        })
    {
        $new->$meth($old->$meth());
    }
    
    if ($old->translation_region_is_set) {
        $new->translation_region($old->translation_region);
    }

    $new->set_remarks($old->list_remarks);
    $new->set_annotation_remarks($old->list_annotation_remarks);

    # Clone each exon, and add to new SubSeq
    foreach my $old_ex ($old->get_all_Exons) {
        my $new_ex = $old_ex->clone;
        $new->add_Exon($new_ex);
    }
 
    $new->evidence_hash($old->clone_evidence_hash);
    
    return $new;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'} || confess "name not set";
}

sub start_phase {
    my( $self, $phase ) = @_;
    
    if (defined $phase) {
        confess "start_phase is read_only method - use start_not_found";
    }
    return $self->{'_start_phase'} || 1;
}

sub start_not_found {
    my( $self, $phase ) = @_;
    
    if (defined $phase) {
        confess "Bad phase '$phase'"
            unless $phase =~ /^[0123]$/;
        $self->{'_start_phase'} = $phase;
    }
    return $self->{'_start_phase'} || 0;
}

sub end_not_found {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_end_not_found'} = $flag ? 1 : 0;
    }
    return $self->{'_end_not_found'} || 0;
}

sub upstream_subseq_name {
    my( $self, $name ) = @_;
    
    if (defined $name) {
        $self->{'_upstream_subseq_name'} = $name;
    }
    return $self->{'_upstream_subseq_name'};
}

sub downstream_subseq_name {
    my( $self, $name ) = @_;
    
    if (defined $name) {
        $self->{'_downstream_subseq_name'} = $name;
    }
    return $self->{'_downstream_subseq_name'};
}

sub otter_id {
    my( $self, $otter_id ) = @_;
    
    if ($otter_id) {
        $self->{'_otter_id'} = $otter_id;
    }
    return $self->{'_otter_id'};
}

sub set_remarks {
    my( $self, @remarks ) = @_;
    
    # The grep ensures that empty remarks are ingored
    $self->{'_remark_list'} = [grep $_, @remarks];
}

sub list_remarks {
    my( $self ) = @_;
    
    if (my $rl = $self->{'_remark_list'}) {
        return @$rl;
    } else {
        return;
    }
}

sub empty_remarks {
    my( $self ) = @_;
    
    $self->{'_remark_list'} = undef;
}

sub set_annotation_remarks {
    my( $self, @annotation_remarks ) = @_;
    
    $self->{'_annotation_remark_list'} = [@annotation_remarks];
}

sub list_annotation_remarks {
    my( $self ) = @_;
    
    if (my $rl = $self->{'_annotation_remark_list'}) {
        return @$rl;
    } else {
        return;
    }
}

sub empty_annotation_remarks {
    my( $self ) = @_;
    
    $self->{'_annotation_remark_list'} = undef;
}

sub add_evidence_list {
    my($self, $type, $list) = @_;
    
    $self->{'_evidence_hash'}{$type} = $list;
}

sub evidence_hash {
    my( $self, $evidence_hash ) = @_;
    
    if ($evidence_hash) {
        $self->{'_evidence_hash'} = $evidence_hash;
    } else {
        $self->{'_evidence_hash'} ||= {};
    }
    return $self->{'_evidence_hash'};
}

sub clone_evidence_hash {
    my( $self ) = @_;
    
    my $ev = $self->evidence_hash;
    
    my $new_hash = {};
    foreach my $type (keys %$ev) {
        my $ev_list = $ev->{$type};
        $new_hash->{$type} = [@$ev_list];
    }
    return $new_hash
}

sub count_evidence {
    my ($self) = @_;
    
    my $ev = $self->evidence_hash;
    my $count = 0;
    foreach my $type (keys %$ev) {
        my $ev_list = $ev->{$type};
        $count += @$ev_list;
    }
    return $count;
}

sub empty_evidence_hash {
    my( $self ) = @_;
    
    $self->{'_evidence_hash'} = {};
}

sub clone_Sequence {
    my( $self, $seq ) = @_;
    
    if ($seq) {
        $self->{'_clone_Sequence'} = $seq;
    }
    return $self->{'_clone_Sequence'};
}

sub exon_Sequence {
    my( $self ) = @_;
    
    my $clone_seq = $self->clone_Sequence
        or confess "No clone_Sequence";
    my $seq = Hum::Sequence::DNA->new;
    $seq->name($self->name);
    
    my $seq_str = '';
    foreach my $exon ($self->get_all_Exons) {
	my $start = $exon->start;
	my $end   = $exon->end;
	$seq_str .= $clone_seq
	    ->sub_sequence($start, $end)
	    ->sequence_string;
    }
    $seq->sequence_string($seq_str);
    
    if ($self->strand == -1) {
        $seq = $seq->reverse_complement;
    }
    
    return $seq;
}

sub exon_Sequence_array {
    my( $self ) = @_;
    
    my $clone_seq = $self->clone_Sequence
        or confess "No clone_Sequence";
    
    my $exon_seqs = [];
    my $i = 0;
    my $name = $self->name;
    foreach my $exon ($self->get_all_Exons) {
        $i++;
	my $start = $exon->start;
	my $end   = $exon->end;
	my $seq = $clone_seq->sub_sequence($start, $end);
	if ($self->strand == -1) {
            $seq = $seq->reverse_complement;
        }
        # Give it a name so that we don't have an anonymous sequence
        $seq->name("${name}_exon_$i");
        push(@$exon_seqs, $seq);
    }
    if ($self->strand == -1) {
        @$exon_seqs = reverse @$exon_seqs;
    }
    return $exon_seqs;
}

sub mRNA_Sequence {
    my( $self ) = @_;
    
    my $strand    = $self->strand;
    my $clone_seq = $self->clone_Sequence or confess "No clone_Sequence";
    
    my $seq = Hum::Sequence::DNA->new;
    $seq->name($self->name);
    
    my $seq_str = '';
    foreach my $exon ($self->get_all_Exons) {
        $seq_str .= $clone_seq
            ->sub_sequence($exon->start, $exon->end)
            ->sequence_string;
    }
    $seq->sequence_string($seq_str);
    
    if ($strand == -1) {
        $seq = $seq->reverse_complement;
    }
    
    return $seq;
}

sub translatable_Sequence {
    my( $self ) = @_;
    
    my ($t_start, $t_end)   = $self->translation_region;
    my $strand              = $self->strand;
    my $phase               = $self->start_phase  ;
    my $clone_seq           = $self->clone_Sequence or confess "No clone_Sequence";
    
    #warn "strand = $strand, phase = $phase\n";
    
    my $seq = Hum::Sequence::DNA->new;
    $seq->name($self->name);
    
    my $seq_str = '';
    foreach my $exon ($self->get_all_CDS_Exons) {
        my $start = $exon->start;
        my $end   = $exon->end;

        # Is this the first coding exon?        
        if ($strand == 1 and $start == $t_start) {
            $start += $phase - 1;
        }
        elsif ($strand == -1 and $end == $t_end) {
            $end   += 1 - $phase;
        }
        
        $seq_str .= $clone_seq
            ->sub_sequence($start, $end)
            ->sequence_string;
    }
    $seq->sequence_string($seq_str);
    
    if ($strand == -1) {
        $seq = $seq->reverse_complement;
    }
    
    return $seq;
}

# Returns an anonymous array containing the genomic start
# coordinates of each of the codons in the translation.
sub codon_start_map {
    my( $self ) = @_;
    
    my $map = [];
    my @exons = $self->get_all_CDS_Exons;
    
    # Phase is in 0,1,2 convention instead of acedb 1,2,3
    # to make calculation of next exons's phase easiser
    my $phase = $self->start_phase - 1;
    #warn "start phase = '$phase'\n";
    
    if ($self->strand == 1) {
        foreach my $ex (@exons) {
            my $start = $ex->start + $phase;
            my $end   = $ex->end;
            for (my $i = $start; $i <= $end; $i += 3) {
                push(@$map, $i);
            }
            my $length = $end - $start + 1;
            $phase = (3 - ($length % 3)) % 3;
            #warn "Exon $start -> $end  length is ", $ex->length, " ($length)\nnext exon phase = '$phase'\n";
        }
    } else {
        foreach my $ex (reverse @exons) {
            my $start = $ex->end - $phase;
            my $end   = $ex->start;
            for (my $i = $start; $i >= $end; $i -= 3) {
                push(@$map, $i);
            }
            my $length = $start - $end + 1;
            $phase = (3 - ($length % 3)) % 3;
            #warn "Exon $start -> $end  length is ", $ex->length, " ($length)\nnext exon phase = '$phase'\n";
        }
    }
    
    return $map;
}

sub get_all_CDS_Exons {
    my( $self ) = @_;

    my ($t_start, $t_end)   = $self->translation_region;
    my $strand              = $self->strand;

    my( @cds_exons );
    foreach my $exon ($self->get_all_Exons) {
        my $start = $exon->start;
        my $end   = $exon->end;
        
        # Skip non-coding exons
        next if $end   < $t_start;
        last if $start > $t_end;
        
        # Trim coordinates to translation start and end
        if ($start < $t_start) {
            $start = $t_start;
        }
        if ($end > $t_end) {
            $end = $t_end;
        }
        
        my $cds = Hum::Ace::Exon->new;
        $cds->start($start);
        $cds->end($end);
        $cds->otter_id($exon->otter_id);
        push(@cds_exons, $cds);
    }
    
    # Add the phase to the first exon if start is not found.
    # (Needed by the ace -> ensembl transfer system.)
    my $start_exon = $strand == 1 ? $cds_exons[0] : $cds_exons[$#cds_exons];
    if ($self->start_not_found) {
        $start_exon->phase($self->start_phase);
    }
    
    return @cds_exons;
}

sub get_all_exon_Sequences {
    my( $self ) = @_;
    
    my $clone_seq = $self->clone_Sequence or confess "No clone_Sequence";
    my( @ex_seq );
    foreach my $exon ($self->get_all_Exons) {
        my $start = $exon->start;
        my $end   = $exon->end;
        push(@ex_seq, $clone_seq->sub_sequence($start, $end));
    }
    
    if ($self->strand == -1) {
        @ex_seq = reverse(@ex_seq);
        for (my $i = 0; $i < @ex_seq; $i++) {
            my $ex = $ex_seq[$i];
            $ex_seq[$i] = $ex->reverse_complement;
        }
    }
    
    return @ex_seq;
}

sub drop_all_exon_otter_id {
    my ($self) = @_;
    
    foreach my $exon ($self->get_all_Exons) {
        $exon->drop_otter_id;
    }
}

sub GeneMethod {
    my( $self, $GeneMethod ) = @_;
    
    if ($GeneMethod) {
        $self->{'_GeneMethod'} = $GeneMethod;
    }
   
    return $self->{'_GeneMethod'};
}

sub Locus {
    my( $self, $Locus ) = @_;
    
    if ($Locus) {
        unless (ref($Locus) and $Locus->isa('Hum::Ace::Locus')) {
            confess "Wrong kind of thing '$Locus'";
        }
        $self->{'_Locus'} = $Locus;
    }
    return $self->{'_Locus'};
}

sub unset_Locus {
    my( $self ) = @_;
    
    $self->{'_Locus'} = undef;
}

sub strand {
    my( $self, $strand ) = @_;
    
    if (defined $strand) {
        confess "Illegal strand '$strand'; must be '1' or '-1'"
            unless $strand =~ /^-?1$/;
        $self->{'_strand'} = $strand
    }
    return $self->{'_strand'} || confess "strand not set";
}

sub add_Exon {
    my( $self, $Exon ) = @_;
    
    confess "'$Exon' is not a 'Hum::Ace::Exon'"
        unless $Exon->isa('Hum::Ace::Exon');
    push(@{$self->{'_Exon_list'}}, $Exon);
    $self->is_sorted(0);
}

sub new_Exon {
    my( $self ) = @_;
    
    my $exon = Hum::Ace::Exon->new;
    $self->add_Exon($exon);
    return $exon;
}

sub is_sorted {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_is_sorted'} = $flag ? 1 : 0;
    }
    return $self->{'_is_sorted'};
}

sub is_archival {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_is_archival'} = $flag ? 1 : 0;
    }
    return $self->{'_is_archival'};
}

sub is_mutable {
    my( $self ) = @_;

    if (my $locus = $self->Locus) {
        if ($locus->is_truncated) {
            return 0;
        }
    }
    return $self->GeneMethod->mutable;
}

### Methods to record type?

sub sort_Exons {
    my( $self ) = @_;
    
    @{$self->{'_Exon_list'}} =
        sort {
            $a->start <=> $b->start || $a->end <=> $b->end
        } @{$self->{'_Exon_list'}};
    $self->is_sorted(1);
}

sub get_all_Exons {
    my( $self ) = @_;
    
    $self->sort_Exons unless $self->is_sorted;
    return @{$self->{'_Exon_list'}};
}

sub get_all_Exons_in_transcript_order {
    my( $self ) = @_;
    
    return $self->strand == 1 ?
        $self->get_all_Exons
      : reverse $self->get_all_Exons;
}

sub delete_Exon {
    my( $self, $gonner ) = @_;
    
    for (my $i = 0; $i < @{$self->{'_Exon_list'}}; $i++) {
        my $exon = $self->{'_Exon_list'}[$i];
        if ($exon == $gonner) {
            splice(@{$self->{'_Exon_list'}}, $i, 1);
            return 1;
        }
    }
    confess "Didn't find exon '$gonner'";
}

sub replace_all_Exons {
    my( $self, @exons ) = @_;
    
    $self->{'_Exon_list'} = [@exons];
    $self->is_sorted(0);
    return 1;
}

sub start {
    my( $self ) = @_;
    
    my @exons = $self->get_all_Exons or confess "No Exons";
    return $exons[0]->start;
}

sub end {
    my( $self ) = @_;
    
    my @exons = $self->get_all_Exons or confess "No Exons";
    return $exons[$#exons]->end;
}

sub set_translation_region_from_cds_coords {
    my( $self, @coords ) = @_;
    
    # This is fatal on failure
    my @t_region = $self->remap_coords_mRNA_to_genomic(@coords);
    
    $self->translation_region(@t_region);
}

sub remap_coords_mRNA_to_genomic {
    my $self = shift;
    
    # Sort coords so that we can bail out of the search
    # loop and go on to the next exon early.
    my @coords = sort {$a <=> $b} @_;
    
    my $strand = $self->strand;
    my @exons = $self->get_all_Exons;
    if ($strand == -1) {
        @exons = reverse @exons;
    }
    
    my $pos = 0;
    my( @remapped );
    foreach my $ex (@exons) {    
        
        # Calculate start and end of this exon in mRNA coordinates
        my $start = $pos + 1;
        my $end   = $pos + $ex->length;
        
        while (@coords) {
            # Does the first (smallest) coordinate lie in this exon?
            if ($coords[0] <= $end) {
                my $c = shift @coords;
                
                # Use of push or unshift with forward or reverse
                # strand ensures that coordinates come out in
                # @remapped sorted in genomic order
                if ($strand == 1) {
                    push   (@remapped, $ex->start +  $c - $start);
                }
                else {
                    unshift(@remapped, $ex->end   - ($c - $start));
                }
            } else {
                last;
            }
        }
        
        last unless @coords;
        $pos = $end;
    }
    
    if (@coords) {
        confess "Failed to remap coordinates: (",
            join(', ', map "'$_'", @coords),
            ") in transcript of length ",
            $pos + 1;
    }
    
    return @remapped;
}

sub remap_coords_genomic_to_mRNA {
    my( $self, @coords ) = @_;
    
    my $strand = $self->strand;
    my @exons = $self->get_all_Exons;
    if ($strand == -1) {
        @exons = reverse @exons;
    }
    
    my( @remapped );
    my $cds_length = 0;
    foreach my $exon (@exons) {
        my $start = $exon->start;
        my $end   = $exon->end;
        
        for (my $i = 0; $i < @coords; $i++) {
            next if $remapped[$i];  # Already remapped
            my $pos = $coords[$i];
            if ($pos >= $start and $pos <= $end) {
                if ($strand == 1) {
                    $remapped[$i] = $pos - $start + 1 + $cds_length;
                } else {
                    $remapped[$i] = $end - $pos   + 1 + $cds_length;
                }
            }
        }
        
        $cds_length += $exon->length;
    }
    
    return @remapped;
}

sub translation_region {
    my( $self, $start, $end ) = @_;
    
    if (defined $start) {

        foreach ($start, $end) {
            unless (/^\d+$/) {
                confess "Bad pos (start = '$start', end = '$end')";
            }
        }
        confess "start '$start' not less than or equal to end '$end'"
            unless $start <= $end;
        $self->{'_translation_region'} = [$start, $end];
    }
    if (my $pn = $self->{'_translation_region'}) {
        return @$pn;
    } else {
        return($self->start, $self->end);
    }
}

sub unset_translation_region {
    my( $self ) = @_;
    
    $self->{'_translation_region'} = undef;
}

sub translation_region_is_set {
    my( $self ) = @_;
    
    return $self->{'_translation_region'} ? 1 : 0;
}

sub cds_coords {
    my( $self ) = @_;
    
    my @t_region   = $self->translation_region;
    @t_region = reverse(@t_region) if $self->strand == -1;
    my @cds_coords = $self->remap_coords_genomic_to_mRNA(@t_region);
    
    my $err = "";
    for (my $i = 0; $i < @t_region; $i++) {
        unless ($cds_coords[$i]) {
            $err .= qq{Translation coord '$t_region[$i]' does not lie within any Exon\n};
        }
    }
    confess $err if $err;
    
    return @cds_coords;
}

sub subseq_length {
    my( $self ) = @_;
    
    return $self->end - $self->start + 1;
}

sub validate {
    my( $self ) = @_;
    
    confess "No Exons" unless $self->get_all_Exons;
    
    $self->valid_exon_coordinates;
    $self->cds_coords;
}

sub valid_exon_coordinates {
    my( $self ) = @_;
    
    my( $last_end );
    foreach my $ex ($self->get_all_Exons) {
        my $start = $ex->start;
        my $end   = $ex->end;
        confess "Illegal start-end ($start-$end)"
            unless $start <= $end;
        if ($last_end) {
            confess "Exon [$start-$end] overlap with previous (ends at $last_end)"
                if $start <= $last_end;
        }
        $last_end = $end;
    }
    return 1;
}

sub contains_all_exons {
    my( $self, $other ) = @_;
    
    confess "No other" unless $other;
    
    my  @self_exons =  $self->get_all_Exons;
    my @other_exons = $other->get_all_Exons;
    
    # Find the index of the first overlapping
    # exon in @self_exons.
    my( $first_i );
    {
        my $o_ex = $other_exons[0];
        for (my $i = 0; $i < @self_exons; $i++) {
            my $s_ex = $self_exons[$i];
            if ($s_ex->overlaps($o_ex)) {
                $first_i = $i;
                last;
            }
        }
    }
    
    my $all_contained = 0;
    if (defined $first_i) {
        @self_exons = splice(@self_exons, $first_i, scalar(@other_exons));
        if (@self_exons == @other_exons) {
            $all_contained = 1;
            for (my $i = 0; $i < @self_exons; $i++) {
                my $s_ex =  $self_exons[$i];
                my $o_ex = $other_exons[$i];
                if ($i == 0 or $i == $#other_exons) {
                    # First or last CDS exon
                    unless ($s_ex->contains($o_ex)) {
                        $all_contained = 0;
                        last;
                    }
                } else {
                    # Internal exon
                    unless ($s_ex->matches($o_ex)) {
                        $all_contained = 0;
                        last;
                    }
                }
            }
        }
    }
    
    return $all_contained;
}

sub ace_string {
    my( $self, $old_name ) = @_;
        
    my $name        = $self->name
        or confess "name not set";
    my $clone_seq   = $self->clone_Sequence
        or confess "no clone_Sequence";
    my $ott         = $self->otter_id;
    my @exons       = $self->get_all_Exons;
    my $method      = $self->GeneMethod;
    my $locus       = $self->Locus;
    
    my $clone = $clone_seq->name
        or confess "No sequence name in clone_Sequence";
    
    my $out = qq{\nSequence "$clone"\n};
    if ($old_name) {
        $out .= qq{-D SubSequence "$old_name"\n}
    } else {
        $out .= qq{-D SubSequence "$name"\n}
    }
    
    $out .= qq{\nSequence "$clone"\n};
    
    # Position in parent sequence
    my( $start, $end, $strand );
    if (@exons) {
        $start  = $self->start;
        $end    = $self->end;
        $strand = $self->strand;
        if ($strand == 1) {
            $out .= qq{SubSequence "$name"  $start $end\n};
        } else {
            $out .= qq{SubSequence "$name"  $end $start\n};
        }
    }

    ### This "-R" rename is no longer needed if everything
    ### we edit is now in the interface.
    $out .= qq{\n-R Sequence "$old_name" "$name"\n}
        if $old_name;
    
    $out .= qq{\nSequence "$name"\n}
        . qq{-D Source\n}
        . qq{-D Method\n}
        . qq{-D Locus\n}
        . qq{-D CDS\n}
        . qq{-D Source_Exons\n}
        
        #. qq{-D Start_not_found\n}
        #. qq{-D End_not_found\n}
        #. qq{-D Predicted_gene\n}
        # Commented out block above and replaced with:
        . qq{-D Properties\n}
        
        . qq{-D Continued_from\n}
        . qq{-D Continues_as\n}
        . qq{-D Remark\n}
        . qq{-D Annotation_remark\n}

        . qq{-D Sequence_matches\n}
        
        # New SubSequencce object starts here
        . qq{\nSequence "$name"\n}
        . qq{Source "$clone"\n}
        . qq{Predicted_gene\n}
        ;
    
    if ($ott) {
        $out .= qq{Transcript_id "$ott"\n};
    }
    
    if ($method) {
        my $mn = $method->name;
        my $prefix = '';
        if ($locus and my $pre = $locus->gene_type_prefix) {
            $prefix = "$pre:";
        }
        $out .= qq{Method "$prefix$mn"\n};
        my $type = $method->transcript_type;
        if ($type and $type eq 'coding') {
            my ($cds_start, $cds_end) = $self->cds_coords;
            $out .= qq{CDS  $cds_start $cds_end\n};
        }
        elsif ($mn =~ /pseudo/i) {
            $out .= qq{CDS\nPseudogene\n};
        }

        if ($mn =~ /mRNA/i) {
            $out .= qq{Processed_mRNA\n};
        }
    }
    
    if (my $phase = $self->start_not_found) {
        $out .= qq{Start_not_found $phase\n};
    }
    if ($self->end_not_found) {
        $out .= qq{End_not_found\n};
    }
    
    if (my $from = $self->upstream_subseq_name) {
        $out .= qq{Continued_from "$from"\n};
    }
    if (my $as = $self->downstream_subseq_name) {
        $out .= qq{Continues_as "$as"\n};
    }
    
    # The exons
    if ($strand == 1) {
        foreach my $ex (@exons) {
            my $x = $ex->start - $start + 1;
            my $y = $ex->end   - $start + 1;
            if (my $ott = $ex->otter_id) {
                $out .= qq{Source_Exons  $x $y "$ott"\n};
            } else {
                $out .= qq{Source_Exons  $x $y\n};
            }
        }
    } else {
        foreach my $ex (reverse @exons) {
            my $x = $end - $ex->end   + 1;
            my $y = $end - $ex->start + 1;
            if (my $ott = $ex->otter_id) {
                $out .= qq{Source_Exons  $x $y "$ott"\n};
            } else {
                $out .= qq{Source_Exons  $x $y\n};
            }
        }
    }
    
    # Need to use AceText quoting because anything can be in the remark!
    my $txt = Hum::Ace::AceText->new;
    foreach my $remark ($self->list_remarks) {
        $txt->add_tag_values(['Remark', $remark]);
    }
    foreach my $remark ($self->list_annotation_remarks) {
        $txt->add_tag_values(['Annotation_remark', $remark]);
    }
    $out .= $txt->ace_string;

    # Supporting evidence
    my $evi = $self->evidence_hash;
    foreach my $type (sort keys %$evi) {
        my $id_list = $evi->{$type};
        foreach my $name (@$id_list) {
            $out .= qq{${type}_match "$name"\n};
        }
    }
    
    if ($locus) {
        my $ln = $locus->name;
        $out .= qq{Locus "$ln"\n};
        $out .= $locus->ace_string;
    }
    
    $out .= "\n";
    
    return $out;
}

sub zmap_delete_xml_string {
    my ($self) = @_;
    
    my $xml = Hum::XmlWriter->new;
    $xml->open_tag('zmap', {action => 'delete_feature'});
    $xml->open_tag('featureset');
    $self->zmap_xml_feature_tag($xml);
    $xml->close_all_open_tags;
    return $xml->flush;
}

sub zmap_create_xml_string {
    my ($self) = @_;
    
    ### featureset tag will require "align" and "block" attributes
    ### if there is more than one in the Zmap. Can probably be
    ### taken from the attached clone_Sequence.
    my $xml = Hum::XmlWriter->new;
    $xml->open_tag('zmap', {action => 'create_feature'});
    $xml->open_tag('featureset');
    $self->zmap_xml_feature_tag($xml);
    
    my @exons = $self->get_all_Exons
        or confess "No exons";
    for (my $i = 0; $i < @exons; $i++) {
        my $ex = $exons[$i];
        if ($i > 0) {
            # Set intron span from end of previous exon to start of current
            my $pex = $exons[$i - 1];
            $xml->full_tag('subfeature', {
                ontology    => 'intron',
                start       => $pex->end + 1,
                end         => $ex->start - 1,
            });
        }
        $xml->full_tag('subfeature', {
            ontology    => 'exon',
            start       => $ex->start,
            end         => $ex->end,
        });
    }

    if ($self->translation_region_is_set) {
        my @tr = $self->translation_region;
        $xml->full_tag('subfeature', {
            ontology    => 'cds',
            start       => $tr[0],
            end         => $tr[1],
        });
    }

    $xml->close_all_open_tags;
    return $xml->flush;
}

sub zmap_xml_feature_tag {
    my ($self, $xml) = @_;
    
    my $style = $self->GeneMethod->name;
    if (my $pre = $self->Locus->gene_type_prefix) {
        $style = "$pre:$style";
    }

    $xml->open_tag('feature', {
            name            => $self->name,
            start           => $self->start,
            end             => $self->end,
            strand          => $self->strand == -1 ? '-' : '+',
            style           => $style,
            locus           => $self->Locus->name,
            start_not_found => $self->start_not_found,
            end_not_found   => $self->end_not_found ? 'true' : 'false',
    });
}

sub zmap_info_xml {
    my ($self) = @_;

    my $xml = Hum::XmlWriter->new;
    $xml->open_tag('chapter');
    
    # We add info for Zmap into the "Feature" and "Annotation" subsections of the "Details" page.
    $xml->open_tag('page', {name => 'Details'});

    if (my $locus = $self->Locus) {
        # This Locus stuff might be better in Hum::Ace::Locus
        $xml->open_tag('subsection', {name => 'Feature'});

            $xml->open_tag('paragraph', {name => 'Locus', type => 'tagvalue_table'});

            # Locus Symbol, Alias and Full name
            $xml->full_tag('tagvalue', {name => 'Symbol', type => 'simple'}, $locus->name);
            foreach my $alias ($locus->list_aliases) {
                $xml->full_tag('tagvalue', {name => 'Alias', type => 'simple'}, $alias);
            }
            $xml->full_tag('tagvalue', {name => 'Full name', type => 'simple'}, $locus->description);

            ### Author - need to add to Locus object
            if (my $ott = $locus->otter_id) {
                $xml->full_tag('tagvalue', {name => 'Locus Stable ID', type => 'simple'}, $ott);
            }

            # Locus Remarks and Annotation remarks
            foreach my $rem ($locus->list_remarks) {
                $xml->full_tag('tagvalue', {name => 'Remark',            type => 'scrolled_text'}, $rem);
            }
            foreach my $rem ($locus->list_annotation_remarks) {
                $xml->full_tag('tagvalue', {name => 'Annotation remark', type => 'scrolled_text'}, $rem);
            }

            $xml->close_tag;

        $xml->close_tag;
    }
    $xml->open_tag('subsection', {name => 'Annotation'});
    
        ### Need to add author to Hum::Ace::SubSeq object
        if (my $ott = $self->otter_id) {
            $xml->open_tag('paragraph', {type => 'tagvalue_table'});
            $xml->full_tag('tagvalue', {name => 'Transcript Stable ID', type => 'simple'}, $ott);
            $xml->close_tag;
        }

        # Subseq Remarks and Annotation remarks
        if ($self->list_remarks or $self->list_annotation_remarks) {       
            $xml->open_tag('paragraph', {type => 'tagvalue_table'});
            foreach my $rem ($self->list_remarks) {
                $xml->full_tag('tagvalue', {name => 'Remark',            type => 'scrolled_text'}, $rem);
            }
            foreach my $rem ($self->list_annotation_remarks) {
                $xml->full_tag('tagvalue', {name => 'Annotation remark', type => 'scrolled_text'}, $rem);
            }
            $xml->close_tag;
        }

        # Supporting evidence
        if ($self->count_evidence) {
            $xml->open_tag('paragraph', {name => 'Evidence', type => 'tagvalue_table'});
            my $evi = $self->evidence_hash;
            foreach my $type (sort keys %$evi) {
                my $id_list = $evi->{$type};
                foreach my $name (@$id_list) {
                    $xml->full_tag('tagvalue', {name => $type, type => 'simple'}, $name);
                }
            }
            $xml->close_tag;
        }
        # # Supporting evidence as a compound table
        # if ($self->count_evidence) {
        #     $xml->open_tag('paragraph', {
        #         name => 'Evidence',
        #         type => 'compound_table',
        #         columns => q{'Type' 'Accession.SV'},
        #         column_types => q{string string},
        #         });
        #     my $evi = $self->evidence_hash;
        #     foreach my $type (sort keys %$evi) {
        #         my $id_list = $evi->{$type};
        #         foreach my $name (@$id_list) {
        #             my $str = sprintf "%s %s", $type, $name;
        #             $xml->full_tag('tagvalue', {type => 'compound'}, $str);
        #         }
        #     }
        #     $xml->close_tag;
        # }
    
    $xml->close_tag;
    $xml->close_tag;
    
    # Add our own page called "Exons"
    $xml->open_tag('page', {name => 'Exons'});
    $xml->open_tag('subsection');
    $xml->open_tag('paragraph', {
        type => 'compound_table',
        columns => q{'#' 'Start' 'End' 'Stable ID'},
        column_types => q{int int int string},
        });
    my @ordered_exons = $self->get_all_Exons_in_transcript_order;
    for (my $i = 0; $i < @ordered_exons; $i++) {
        my $exon = $ordered_exons[$i];
        my @pos;
        if ($self->strand == 1) {
            @pos = ($exon->start, $exon->end);
        } else {
            @pos = ($exon->end, $exon->start);
        }
        my $str = sprintf "%d %d %d %s", $i + 1, @pos, $exon->otter_id || '-';
        $xml->full_tag('tagvalue', {type => 'compound'}, $str);
    }
    
    $xml->close_all_open_tags;
    return $xml->flush;
}

#sub DESTROY {
#    my( $self ) = @_;
#    
#    print STDERR "SubSeq ", $self->name, " is released\n";
#}


1;

__END__

=head1 NAME - Hum::Ace::SubSeq

=head1 DESCRIPTION

This object is used extensively in the otter
system and represents a SubSequence object
(Transcrpt) in an acedb database.

It has methods for converting to and from ace
format strings/ acedb databases.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

