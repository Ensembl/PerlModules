
### Hum::Ace::SubSeq

package Hum::Ace::SubSeq;

use strict;
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

    # Is this a partial CDS?
    my( $start_phase );
    {
        my( $s_n_f, $codon_start );
        eval{ ($s_n_f, $codon_start) = map "$_", $t_seq->at('Properties.Start_not_found')->row() };
        if ($s_n_f) {
            $codon_start ||= 1;
        }
        if ($codon_start and $t_seq->at('Properties.Coding.CDS')) {
            unless ($codon_start =~ /^[123]$/) {
                confess("Bad codon start ('$codon_start') in '$t_seq'");
            }
            
            # Store phase in AceDB convention (not EnsEMBL)
            $start_phase = $codon_start;
        }
    }
    
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
    
    my @exons = $self->get_all_Exons
        or confess "No exons in '", $self->name, "'";
    
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
    
    # Copy scalar fields
    foreach my $meth (qw{
        name
        clone_Sequence
        GeneMethod
        strand
        })
    {
        $new->$meth($old->$meth());
    }

    # Clone each exon, and add to new SubSeq
    foreach my $old_ex ($old->get_all_Exons) {
        my $new_ex = $old_ex->clone;
        $new->add_Exon($new_ex);
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

sub clone_Sequence {
    my( $self, $seq ) = @_;
    
    if ($seq) {
        $self->{'_clone_Sequence'} = $seq;
    }
    return $self->{'_clone_Sequence'};
}

sub GeneMethod {
    my( $self, $GeneMethod ) = @_;
    
    if ($GeneMethod) {
        $self->{'_GeneMethod'} = $GeneMethod;
    }
    return $self->{'_GeneMethod'};
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

sub is_sorted {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_is_sorted'} = $flag ? 1 : 0;
    }
    return $self->{'_is_sorted'};
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
    
    confess "No new exons given"
        unless @exons;
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
    
    my @t_region    = $self->translation_region;
    my @exons       = $self->get_all_Exons;
    my $strand      = $self->strand;
    my( @cds_coords );
    my $cds_length = 0;
    if ($strand == 1) {
        foreach my $exon (@exons) {
            my $start = $exon->start;
            my $end   = $exon->end;
            for (my $i = 0; $i < @t_region; $i++) {
                my $pos = $t_region[$i];
                if ($pos >= $start and $pos <= $end) {
                    $cds_coords[$i] = $pos - $start + 1 + $cds_length;
                }
            }
            $cds_length += $exon->length;
        }
    } else {
        @t_region = reverse @t_region;
        foreach my $exon (reverse @exons) {
            my $start = $exon->start;
            my $end   = $exon->end;
            for (my $i = 0; $i < @t_region; $i++) {
                my $pos = $t_region[$i];
                if ($pos >= $start and $pos <= $end) {
                    $cds_coords[$i] = $end - $pos + 1 + $cds_length;
                }
            }
            $cds_length += $exon->length;
        }
    }
    
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
    
    my @self_exons  =  $self->get_all_Exons;
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

sub as_ace_file_format_text {
    my( $self ) = @_;
        
    my $name        = $self->name
        or confess "name not set";
    my $clone_seq   = $self->clone_Sequence
        or confess "no clone_Sequence";
    my $start       = $self->start;
    my $end         = $self->end;
    my $strand      = $self->strand;
    my @exons       = $self->get_all_Exons;
    my $method      = $self->GeneMethod;
    
    my $clone = $clone_seq->name
        or confess "No sequence name in clone_Sequence";
    
    # Position in parent sequence
    my $out = qq{\nSequence "$clone"\n}
        . qq{-D SubSequence "$name"\n};
    if ($strand == 1) {
        $out .= qq{SubSequence "$name"  $start $end\n};
    } else {
        $out .= qq{SubSequence "$name"  $end $start\n};
    }
    
    $out .= qq{\n-D Sequence "$name"\n};
    
    $out .= qq{\nSequence "$name"\n}
        . qq{Source "$clone"\n};
    
    
    if ($method) {
        my $mn = $method->name;
        $out .= qq{Method "$mn"\n};
        if ($method->is_coding) {
            my( $cds_start, $cds_end ) = $self->cds_coords;
            $out .= qq{CDS  $cds_start $cds_end\n};
        }
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
    
    return $out;
}


1;

__END__

=head1 NAME - Hum::Ace::SubSeq

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

