
### Hum::Ace::SubSeq

package Hum::Ace::SubSeq;

use strict;
use Hum::Sequence::DNA;
use Hum::Ace::Exon;
use Hum::Ace::PolyA;
use Carp;

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
    
    # Make the exons
    foreach ($t_seq->at('Structure.From.Source_exons[1]')) {
        
        # Make an Exon object
        my $exon = Hum::Ace::Exon->new;
        
        my ($x, $y) = map $_->name, $_->row;
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
        $self->add_Exon($exon);
    }
    
    # Parse Contines_from and Continues_as
    if (my ($from) = $t_seq->at('Structure.Continued_from[1]')) {
        $self->upstream_subseq_name($from->name);
    }
    if (my ($as) = $t_seq->at('Structure.Continues_as[1]')) {
        $self->downstream_subseq_name($as->name);
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
    my( $start_phase );
    {
        my( $s_n_f, $codon_start );
        eval{ ($s_n_f, $codon_start) = map "$_", $t_seq->at('Properties.Start_not_found')->row() };
        if ($s_n_f) {
            $codon_start ||= 1;
            $self->start_not_found($codon_start);
        }
        if ($codon_start and $t_seq->at('Properties.Coding.CDS')) {
            unless ($codon_start =~ /^[123]$/) {
                confess("Bad codon start ('$codon_start') in '$t_seq'");
            }
            
            # Store phase in AceDB convention (not EnsEMBL)
            $start_phase = $codon_start;
        }
    }
    # Add the phase to the first exon
    if (defined $start_phase) {
        my( $start_exon );
        if ($strand == 1) {
            $start_exon = $exons[0];
        } else {
            $start_exon = $exons[$#exons];
        }
        $start_exon->phase($start_phase);
        #warn "Setting exon phase=$start_phase ", join(' ',
        #    $self->name,
        #    $start_exon->start,
        #    $start_exon->end,
        #    $strand,
        #    ), "\n";
    }

    $self->validate;
}

sub clone {
    my( $old ) = @_;
    
    # Make new SubSeq object
    my $new = ref($old)->new;
    
    # Copy scalar fields (But not is_archival!)
    foreach my $meth (qw{
        name
        clone_Sequence
        GeneMethod
        Locus
        strand
        translation_region
        start_not_found
          end_not_found
        upstream_subseq_name
        downstream_subseq_name
        })
    {
        $new->$meth($old->$meth());
    }

    # Clone each exon, and add to new SubSeq
    foreach my $old_ex ($old->get_all_Exons) {
        my $new_ex = $old_ex->clone;
        $new->add_Exon($new_ex);
    }
    
    # Clone all the PolyA sites
    foreach my $poly ($old->get_all_PolyA) {
        $new->add_PolyA($poly->clone);
    }
    
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

# Can't call this method before clone_Sequence is attached
sub add_all_PolyA_from_ace {
    my( $self, $ace ) = @_;
    
    # Is the PolyA signal marked?
    my( %name_signal );
    foreach my $sig ($ace->at('Feature.polyA_signal[1]')) {
        my($x, $y, $score, $name) =  map $_->name, $sig->row;
        unless (($x and $y) and ($x < $y)) {
            confess "Bad polyA_signal ('$x' -> '$y', score = '$score')";
        }
        $name_signal{$name} = $x;
    }
    
    return unless %name_signal;
    
    my $mRNA = $self->exon_Sequence;

    # The two numbers for the polyA_site are the last
    # two bases of the mRNA in the genomic sequence
    # (Laurens' counterintuitive idea.)
    foreach my $site ($ace->at('Feature.polyA_site[1]')) {
        my($x, $y, $score, $name) = map $_->name, $site->row;
        unless (($x and $y) and ($x + 1 == $y)) {
            confess "Bad polyA_site coordinates ('$x','$y')";
        }
        my $sig_pos = $name_signal{$name}
            or confess "Can't find site for polyA_signal [$x, $y, $score, $name]";
        my $signal = $mRNA
            ->sub_sequence($sig_pos, $sig_pos + 5)
            ->sequence_string;
        my $cons = Hum::Ace::PolyA::Consensus->fetch_by_signal($signal);

        my ($sig_start) = $self->remap_coords_mRNA_to_genomic($sig_pos);
        my ($site_end)  = $self->remap_coords_mRNA_to_genomic($y);

        my $p = Hum::Ace::PolyA->new;
        $p->signal_position($sig_start);
        $p->site_position($site_end);
        $p->consensus($cons);
        
        $self->add_PolyA($p);
    }
}

sub find_PolyA_above_score {
    my( $self, $score ) = @_;
    
    return grep $_->score >= $score, Hum::Ace::PolyA->find_best_in_SubSeq($self);
}

sub add_PolyA {
    my( $self, $polyA ) = @_;
    
    my $pa = $self->{'_PolyA'} ||= [];
    push(@$pa, $polyA);
}

sub get_all_PolyA {
    my( $self ) = @_;
    
    if (my $pa = $self->{'_PolyA'}) {
        return @$pa;
    } else {
        return;
    }
}

sub replace_all_PolyA {
    my( $self, @poly ) = @_;
    
    $self->{'_PolyA'} = [@poly];
}

#  Feature  "polyA_signal" 36228 36233 0.500000 "polyA_signal"
#  Feature  "polyA_signal" 36239 36244 0.500000 "polyA_signal"
#  Feature  "polyA_signal" 79853 79848 0.500000 "polyA_signal"
#  Feature  "polyA_site" 36257 36258 0.500000 "polyA_site"
#  Feature  "polyA_site" 79831 79830 0.500000 "polyA_site"
sub make_PolyA_ace_string {
    my( $self ) = @_;
    
    my $ace = '';
    
    foreach my $poly ($self->get_all_PolyA) {
        my $gen_sig_start = $poly->signal_position;
        my $gen_site_end  = $poly->site_position;
        my $signal        = $poly->consensus->signal;
        my $score = sprintf "%.2f", $poly->score;
        
        my ($sig_start, $site_end) = $self
            ->remap_coords_genomic_to_mRNA($gen_sig_start, $gen_site_end);
        
        # Check remapping was successful
        my $err = '';
        $err .= "failed to remap PolyA signal position '$gen_sig_start'\n" unless $sig_start;
        $err .= "failed to remap PolyA site position '$gen_site_end'\n"    unless $site_end;
        confess $err if $err;
        
        my $sig_end = $sig_start + 5;
        my $site_start = $site_end - 1;
        
        my $name = "polyA $signal ($site_start-$sig_end)";
        $ace .= qq{Feature  "polyA_signal"  $sig_start  $sig_end  $score  "$name"\n};
        $ace .= qq{Feature  "polyA_site"  $site_start  $site_end  $score  "$name"\n};
    }
    
    return $ace;
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

sub translatable_Sequence {
    my( $self ) = @_;
    
    my ($t_start, $t_end)   = $self->translation_region;
    my $strand              = $self->strand;
    my $phase               = $self->start_phase;
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
            $end += 1 - $phase;
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
        push(@cds_exons, $cds);
    }
    return @cds_exons;
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
        $self->{'_Locus'} = $Locus;
    }
    return $self->{'_Locus'};
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
        confess "start '$start' not less than end '$end'"
            unless $start < $end;
        $self->{'_translation_region'} = [$start, $end];
    }
    if (my $pn = $self->{'_translation_region'}) {
        return @$pn;
    } else {
        return($self->start, $self->end);
    }
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

#sub OLD_cds_coords {
#    my( $self ) = @_;
#    
#    my @t_region    = $self->translation_region;
#    my @exons       = $self->get_all_Exons;
#    my( @cds_coords );
#    my $cds_length = 0;
#    if ($self->strand == 1) {
#        foreach my $exon (@exons) {
#            my $start = $exon->start;
#            my $end   = $exon->end;
#            for (my $i = 0; $i < @t_region; $i++) {
#                my $pos = $t_region[$i];
#                if ($pos >= $start and $pos <= $end) {
#                    $cds_coords[$i] = $pos - $start + 1 + $cds_length;
#                }
#            }
#            $cds_length += $exon->length;
#        }
#    } else {
#        @t_region = reverse @t_region;
#        foreach my $exon (reverse @exons) {
#            my $start = $exon->start;
#            my $end   = $exon->end;
#            for (my $i = 0; $i < @t_region; $i++) {
#                my $pos = $t_region[$i];
#                if ($pos >= $start and $pos <= $end) {
#                    $cds_coords[$i] = $end - $pos + 1 + $cds_length;
#                }
#            }
#            $cds_length += $exon->length;
#        }
#    }
#    
#    my $err = "";
#    for (my $i = 0; $i < @t_region; $i++) {
#        unless ($cds_coords[$i]) {
#            $err .= qq{Translation coord '$t_region[$i]' does not lie within any Exon\n};
#        }
#    }
#    confess $err if $err;
#    
#    return @cds_coords;
#}

sub subseq_length {
    my( $self ) = @_;
    
    return $self->end - $self->start + 1;
}

sub validate {
    my( $self ) = @_;
    
    return -1 unless $self->get_all_Exons;
    
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
            unless $start < $end;
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
    my @exons       = $self->get_all_Exons;
    my $method      = $self->GeneMethod;
    my $locus       = $self->Locus;
    
    my $clone = $clone_seq->name
        or confess "No sequence name in clone_Sequence";
    
    # Position in parent sequence
    my $out = qq{\nSequence "$clone"\n};
    if ($old_name) {
        $out .= qq{-D SubSequence "$old_name"\n}
    } else {
        $out .= qq{-D SubSequence "$name"\n}
    }
    
    $out .= qq{\nSequence "$clone"\n};
    
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
        # Commented out above block and replaced with:
        . qq{-D Properties\n}
        
        . qq{-D Continued_from\n}
        . qq{-D Continues_as\n}
        . qq{-D Feature "polyA_signal"\n}
        . qq{-D Feature "polyA_site"\n}
        
        . qq{\nSequence "$name"\n}
        . qq{Source "$clone"\n}
        . qq{Predicted_gene\n}
        ;
    
    if ($locus) {
        my $ln = $locus->name;
        $out .= qq{Locus "$ln"\n};
    }
    
    if ($method) {
        my $mn = $method->name;
        $out .= qq{Method "$mn"\n};
        if ($method->is_coding) {
            my( $cds_start, $cds_end ) = $self->cds_coords;
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
    
    if ($strand == 1) {
        foreach my $ex (@exons) {
            my $x = $ex->start - $start + 1;
            my $y = $ex->end   - $start + 1;
            $out .= qq{Source_Exons  $x $y\n};
        }
    } else {
        foreach my $ex (reverse @exons) {
            my $x = $end - $ex->end   + 1;
            my $y = $end - $ex->start + 1;
            $out .= qq{Source_Exons  $x $y\n};
        }
    }
    
    $out .= $self->make_PolyA_ace_string;
    
    $out .= "\n";
    
    return $out;
}



1;

__END__

=head1 NAME - Hum::Ace::SubSeq

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

