
### Hum::Ace::Locus

package Hum::Ace::Locus;

use strict;
use Carp;
use Bio::EnsEMBL::Exon;
use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::Translation;
use Bio::EnsEMBL::Gene;

sub new {
    my( $pkg ) = shift;
    
    return bless {
        '_CloneSeq_list'    => [],
        '_exon_hash'        => {},
        }, $pkg;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'} || confess "name not set";
}

sub gene_type {
    my( $self, $gene_type ) = @_;
    
    if ($gene_type) {
        $self->{'_gene_type'} = $gene_type;
    }
    return $self->{'_gene_type'} || confess "gene_type not set";
}

sub gene_type_prefix {
    my( $self, $gene_type_prefix ) = @_;
    
    if ($gene_type_prefix) {
        $self->{'_gene_type_prefix'} = $gene_type_prefix;
    }
    return $self->{'_gene_type_prefix'} || '';
}

BEGIN {
    my @type_map = (
        [qw{ Known              Type.Gene.Known            }],
        [qw{ Novel_CDS          Type.Gene.Novel_CDS        }],
        [qw{ Novel_Transcript   Type.Gene.Novel_Transcript }],
        [qw{ Pseudogene         Type.Pseudogene            }],
        [qw{ Putative           Type.Putative              }],
        );

    sub save_locus_info {
        my( $self, $ace_locus ) = @_;

        #print $ace_locus->asString;

        my( @pos_name );
        foreach my $pos ($ace_locus->at('Positive.Positive_sequence[1]')) {
            push(@pos_name, $pos->name);
        }
        $self->set_positive_SubSeq_names(@pos_name);

        $self->name($ace_locus->name);

        my( $gene_type );
        foreach my $t (@type_map) {
            my( $type, $tag ) = @$t;
            if ($ace_locus->at($tag)) {
                $gene_type = $type;
                last;
            }
        }
        confess("No Gene type for locus '$ace_locus':", $ace_locus->asString)
            unless $gene_type;
        $self->gene_type($gene_type);
    }
}

sub set_positive_SubSeq_names {
    my( $self, @seq_names ) = @_;
    
    $self->{'_positive_SubSeq_name_list'} = [@seq_names];
}

sub list_positive_SubSeq_names {
    my( $self, @seq_names ) = @_;
    
    return @{$self->{'_positive_SubSeq_name_list'}};
}

sub add_CloneSeq {
    my( $self, $clone ) = @_;
    
    confess "'$clone' is not a 'Hum::Ace::CloneSeq'"
        unless $clone->isa('Hum::Ace::CloneSeq');
    push(@{$self->{'_CloneSeq_list'}}, $clone);
}

sub get_all_CloneSeqs {
    my( $self ) = @_;
    
    return @{$self->{'_CloneSeq_list'}};
}

sub set_names_lister {
    my( $self, $sub ) = @_;
    
    if ($sub) {
        confess "Not a subroutine ref '$sub'"
            unless ref($sub) eq 'CODE';
        $self->{'_set_names_lister'} = $sub;
    }
    return $self->{'_set_names_lister'};
}

sub count_CloneSeqs {
    my( $self ) = @_;
    
    return scalar @{$self->{'_CloneSeq_list'}};
}

sub list_missing_SubSeqs {
    my( $self ) = @_;
    
    my %positive_seqs = map {$_, 1} $self->list_positive_SubSeq_names;
    foreach my $clone ($self->get_all_CloneSeqs) {
        foreach my $subseq ($clone->get_all_SubSeqs) {
            my $name = $subseq->name;
            $positive_seqs{$name} = 0;
        }
    }
    return grep $positive_seqs{$_}, keys %positive_seqs;   
}

sub is_complete {
    my( $self ) = @_;
    
    return $self->list_missing_SubSeqs ? 0 : 1;
}

sub make_EnsEMBL_Gene {
    my( $self ) = @_;
    
    my $now = time();
    my $gene_name = $self->name;
    
    # Make a new EnsEMBL Gene object
    my $gene = Bio::EnsEMBL::Gene->new;
    $gene->id($self->name);
    $gene->created($now);
    $gene->modified($now);
    $gene->version(1);
    
    my $gene_type = $self->gene_type_prefix . $self->gene_type;
    $gene->type($gene_type);
    
    my $i = 0;
    foreach my $set ($self->make_transcript_sets) {
        $i++;
        my $t_name = sprintf("%s-%03d", $gene_name, $i);
        eval {
            $self->make_transcript($gene, $set, $t_name);
        };
        warn $@ if $@;
    }
    
    return $gene;
}

sub make_transcript_sets {
    my( $self ) = @_;
    
    my $gene_type = $self->gene_type;
    my %is_locus_seq = map {$_, 1} $self->list_positive_SubSeq_names;
    
    my( @clone_sets );
    my @clone_seqs = $self->get_all_CloneSeqs;
    # Loop through all the clones
    for (my $i = 0; $i < @clone_seqs; $i++) {
        
        my $pairs = [];
        
        # Make clone_sets of CDS and mRNA objects according to their names
        my ( %t_pair );
        foreach my $t ($clone_seqs[$i]->get_all_SubSeqs) {
            my $t_name = $t->name;
            
            # Only get SubSeqs from this locus
            next unless $is_locus_seq{$t_name};
            
            my( $pair_name, $is_mRNA ) = $t_name =~ /^(.+?)(\.mRNA)?$/;
            if ($is_mRNA) {
                $t_pair{$pair_name}{'mRNA'} = $t;
            } else {
                $t_pair{$pair_name}{'CDS'}  = $t;
            }
        }
                
        # Make simple arrays of CDS - mRNA clone_sets
        foreach my $pair_name (keys %t_pair) {
            my $cds  = $t_pair{$pair_name}{'CDS'};
            my $mrna = $t_pair{$pair_name}{'mRNA'};
            my $mrna_contains_all_cds_exons = 0;
            
            # Try to get a CDS from the other clone_sets if
            # we have an mRNA object, but not a CDS.
            if ($mrna and ! $cds) {
                print STDERR "Trying to find a CDS for the mRNA '$pair_name'\n";
                my( @other_cds_list );
                foreach my $other_pair (grep $_ ne $pair_name, keys %t_pair) {
                    if (my $other_cds = $t_pair{$other_pair}{'CDS'}) {
                        push(@other_cds_list, $other_cds);
                    }
                }
                foreach my $other_cds (sort {$b->subseq_length <=> $a->subseq_length} @other_cds_list) {
                    if ($mrna->contains_all_exons($other_cds)) {
                        $cds = $other_cds;
                        last;
                    }
                }
            }
            elsif ($cds and ! $mrna) {
                # Just take a copy of the CDS
                $mrna = $cds;
            }
            else {
                #warn "Already have both CDS and mRNA";
            }
            
            #warn "DEBUG - CDS only";
            #$mrna = $cds if $cds;
            
            # Check that all the CDS exons are in the mRNA exons
            if ($cds) {
                my $cds_name  = $cds->name;
                my $mrna_name = $mrna->name;
                unless ($mrna->contains_all_exons($cds)) {
                    confess "'$mrna_name' doesn't contain all the exons in '$cds_name'";
                } else {
                    #warn "'$mrna_name' contains all the exons in '$cds_name'";
                }
            }
            
            # Don't add CDS if it isn't transcribed
            if ($gene_type eq 'Pseudogene' or $gene_type eq 'Putative') {
                push(@$pairs, [$pair_name, $mrna]);
            } else {
                push(@$pairs, [$pair_name, $mrna, $cds]);
            }
        }
        
        # Eliminate mRNA == CDS pairs where we have
        # the CDS paired with one of the mRNAs
        {
            # Make a hash of all the CDS names which are
            # in pairs where mRNA != CDS
            my( %paired_cds );
            foreach my $pair (@$pairs) {
                my( $name, $mrna, $cds ) = @$pair;

                if ($cds and $cds->name ne $mrna->name) {
                    $paired_cds{$cds->name} = 1;
                }
            }

            # Remove mRNA == CDS pairs if we have the
            # CDS paired with an mRNA
            for (my $i = 0; $i < @$pairs;) {
                my( $name, $mrna, $cds ) = @{$pairs->[$i]};
                if ($cds and $cds->name eq $mrna->name) {
                    if ($paired_cds{$cds->name}) {
                        # Remove this pair, and don't increment $i
                        splice(@$pairs, $i, 1);
                        next;
                    }
                }
                $i++;
            }
        }
        
        $clone_sets[$i] = $pairs;
    }   # end of foreach CloneSeq
    
    # What is our maximum number of isoforms?
    my $isoform_count = 0;
    foreach my $c (@clone_sets) {
        if ($isoform_count) {
            $isoform_count = @$c if @$c > $isoform_count;
        } else {
            $isoform_count = @$c;
        }
    }
    print STDERR "isoforms=$isoform_count\n" if $isoform_count > 1;
    
    my( @sets );
    if ($isoform_count > 1 and @clone_sets > 1) {
        print STDERR "Processing multi-clone multi-isoform locus\n";
        
        # Show the sets
        foreach my $c (@clone_sets) {
            print STDERR "\nclone:\n";
            foreach my $pair (@$c) {
                print STDERR "  ['", $pair->[1]->name, "'";
                print STDERR ", '", $pair->[2]->name, "'" if $pair->[2];
                print STDERR "]\n";
                
            }
        }
    
        # If we have more than isoform spanning more than
        # one clone, then we need to rely on a hand-made
        # list of names which make the isoform.
        my $set_names_lister = $self->set_names_lister
                or confess "No set_names_lister subroutine";
        foreach my $names (&$set_names_lister($self->name)) {
            
            my( @s );
            for (my $i = 0; $i < @clone_sets; $i++) {
                foreach my $pair (@{$clone_sets[$i]}) {
                    my( $name, $mrna, $cds ) = @$pair;
                    
                    # Do we want this mRNA?
                    if ($names->{$mrna->name}) {
                        my $new_pair = [$name];
                        $s[$i] = $new_pair;
                        $new_pair->[1] = $mrna;
                        
                        # Do we want the CDS as well?
                        if ($cds and $names->{$cds->name}) {
                            $new_pair->[2] = $cds;
                            last;   # We've found both
                        }
                    }
                }
                if (my $new_pair = $s[$i]) {
                    my( $name, $mrna, $cds ) = @$new_pair;
                    $names->{$mrna->name} = 0;
                    $names->{$cds->name}  = 0 if $cds;
                }
            }
            if (my @missing = grep $names->{$_}, sort keys %$names) {
                warn "Failed to find (",
                    join(', ', map "'$_'", @missing),
                    ") in clone_sets";
                ## If we didn't find a name, it may be because it is the
                ## name of a CDS which we already have, which is paired
                ## up with an mRNA of a different name.
                #my( %found_cds );
                #foreach my $pair (grep defined $_, @s) {
                #    my $mRNA = $pair->[2] or next;
                #    my $cds_name = $mRNA->name;
                #    $found_cds{$cds_name} = 1;
                #}
                #for (my $i = 0; $i < @names;) {
                #    my $n = $names[$i];
                #    if ($found_cds{$n}) {
                #        splice(@names, $i, 1);
                #    } else {
                #        $i++;
                #    }
                #}
                #warn "Failed to find (",
                #    join(', ', map "'$_'", @names),
                #    ") in clone_sets" if @names;
            } else {
                push(@sets, [@s]);
            }
        }
    } else {
        for (my $i = 0; $i < $isoform_count; $i++) {
            my @s = map {defined($_) ? $_->[$i] : undef} @clone_sets;
            push(@sets, [@s]);
        }
    }
    return @sets;
}

sub make_transcript {
    my( $self, $gene, $set, $t_name ) = @_;
    
    print STDERR "\nNew transcript: '$t_name'\n";
    
    my @locus_clones = $self->get_all_CloneSeqs;
    
    # Make the transcript
    my $trans = Bio::EnsEMBL::Transcript->new;
    my $now = time();
    $trans->id($t_name);
    $trans->created($now);
    $trans->modified($now);
    $trans->version(1);
    
    # Make the translation
    my $translation = Bio::EnsEMBL::Translation->new;
    $translation->id($t_name);  # Same name as transcript
    $translation->version(1);
    
    # The orientation of the clone on the golden path (chromosome)
    my( $golden_orientation );
    
    my $is_coding = 0;
    my( @golden_exons, %exon_t_start, %exon_t_end );
    for (my $i = 0; $i < @locus_clones; $i++) {
        my $clone = $locus_clones[$i];
        my $clone_id = $clone->accession;
        my $clone_strand = $clone->golden_strand;
        my $pair  = $set->[$i] or next; # May be no exons in this clone
        my( $pair_name, $mrna, $cds ) = @$pair;

        $is_coding = 1 if $cds;

        # Check that mRNA and CDS are on the same strand
        # if we have them both.        
        my $pair_strand = $mrna->strand;
        if ($cds and $pair_strand != $cds->strand) {
            confess "CDS and mRNA on opposite strands in '$pair_name'";
        }

        # Check the orientation of this piece of the gene
        # relative to the chromosome
        my( $ori );
        if ($clone_strand == 1) {
            $ori = $pair_strand;
        } else {
            $ori = $pair_strand * -1;
        }
        if ($golden_orientation) {
            confess "In pair '$pair_name' ori '$ori' doesn't match chromosome ori '$golden_orientation'"
                unless $ori == $golden_orientation;
        } else {
            $golden_orientation = $ori;
        }
        
        # Make the EnsEMBL exons
        my @cds_exons = $cds->get_all_Exons if $cds;
        print STDERR "mRNA: ", $mrna->name;
        print STDERR " CDS ", $cds->name if $cds;
        print STDERR " strand $pair_strand\n";
        my( @clone_exons );
        my $in_translated_zone = 0;
        foreach my $m_ex ($mrna->get_all_Exons) {
            
            
            my $translation_zone_entry_flag = 0;
            my( $c_ex );
            if ($cds and $c_ex = $cds_exons[0]) {
                if ($m_ex->overlaps($c_ex)) {
                    # Is this the first CDS exon?
                    if ($in_translated_zone == 0) {
                        $translation_zone_entry_flag = 1;
                        $in_translated_zone = 1;
                    }
                    shift(@cds_exons);
                } else {
                    $c_ex = undef;
                }
            }
                        
            # Make an exon for this mRNA exon
            my $ens_exon = $self->get_unique_EnsEMBL_Exon($clone, $pair_strand, $m_ex, $c_ex);
            my $ex_id = $ens_exon->id;
            push(@clone_exons, $ens_exon);

            printf STDERR "%6d %-6d  ", $m_ex->start, $m_ex->end;
            if ($c_ex) {
                printf STDERR "%6d %-6d $ex_id\n", $c_ex->start, $c_ex->end;
            } else {
                print STDERR (" " x 14), "$ex_id\n";
            }
                        
            # If we've seen the last CDS exon, then the
            # translation must stop in this exon.
            my $translation_zone_exit_flag = 0;
            if ($in_translated_zone and ! @cds_exons) {
                $translation_zone_exit_flag = 1;
                $in_translated_zone = 0;
            }
            
            # Add translation start or stops if we're
            # entering or exiting the translated region.
            if ($translation_zone_entry_flag) {
                if ($pair_strand == 1) {
                    $self->record_t_start_point(\%exon_t_start, $ens_exon, $c_ex, $pair_strand);
                } else {
                    $self->record_t_end_point(\%exon_t_end, $ens_exon, $c_ex, $pair_strand);
                }
            }
            if ($translation_zone_exit_flag) {
                if ($pair_strand == 1) {
                    $self->record_t_end_point(\%exon_t_end, $ens_exon, $c_ex, $pair_strand);
                } else {
                    $self->record_t_start_point(\%exon_t_start, $ens_exon, $c_ex, $pair_strand);
                }
            }
        }
        confess "Failed to match all CDS exons to mRNA" if @cds_exons;
        
        # Add these exons to the list of all exons
        if ($pair_strand != $golden_orientation) {
            @clone_exons = reverse(@clone_exons);
        }
        push(@golden_exons, @clone_exons);
    }
    
    warn "no exons" and return unless @golden_exons;
    
    # Order @golden exons so that they run
    # translation start -> end.
    if ($golden_orientation == -1) {
        @golden_exons = reverse(@golden_exons);
    }
        
    if ($is_coding) {
        $trans->translation($translation);

        # Find translation start
        my( $start_exon_id, $t_start );
        foreach my $ex (@golden_exons) {
            if ($t_start = $exon_t_start{$ex->id}) {
                $start_exon_id = $ex->id;
                last;
            }
        }
        confess "Missing translation start" unless $t_start;

        # Find translation end
        my( $end_exon_id, $t_end );
        foreach my $ex (reverse @golden_exons) {
            if ($t_end = $exon_t_end{$ex->id}) {
                $end_exon_id = $ex->id;
                last;
            }
        }
        confess "Missing translation end" unless $t_end;
        
        # Add exons to the transcript
        my $prev_phase = -1;
        foreach my $ex (@golden_exons) {
            my $ex_id     = $ex->id;
            my $ace_phase  = $exon_t_start{"ace_phase-$ex_id"};

            # Set phase 0 if this is the first coding exon
            if ($ex_id eq $start_exon_id) {
                $prev_phase = 0;
            }
            # If we are in a coding region, use the phase from acedb, if set
            elsif ($prev_phase != -1) {
                $prev_phase = $ace_phase if defined($ace_phase);
            }
            
            # Get the exon with this phase
            my $phase_ex = $self->get_unique_EnsEMBL_Exon_with_phase($ex, $prev_phase);
            $trans->add_Exon($phase_ex);

            # Add translation start and/or end
            if ($ex_id eq $start_exon_id) {
                $self->translation_start_add($translation, $phase_ex, $t_start);
            }
            if ($ex_id eq $end_exon_id) {
                $self->translation_end_add($translation, $phase_ex, $t_end);
            }

            # Now calculate the phase for the next exon:

            # If the next exon will be non-coding,
            # set $prev_phase back to -1.
            if ($ex_id eq $end_exon_id) {
                $prev_phase = -1;
            }
            # Set the phase for the next exon if
            # we're in a coding region.
            elsif ($prev_phase != -1) {
                my $start  = $ex->start;
                my $end    = $ex->end;
                my $strand = $ex->strand;

                # Is the transcription start in this exon?
                if ($ex_id eq $start_exon_id) {
                    # Need to move start, so that we can calculate the
                    # correct phase for the next exon.
                    if ($strand == 1) {
                        unless ($start == $t_start) {
                            print STDERR "moving exon start $start > $t_start\n";
                            $start = $t_start;
                        }
                    } else {
                        unless ($end == $t_end) {
                            print STDERR "moving exon end $t_start < $end\n";
                            $end = $t_start;
                        }
                    }
                }
                my $translated_length = $end - $start + 1;
                $prev_phase = ($translated_length + $prev_phase) % 3;
            }
        }        
    } else {
    
        # Add exons to the transcript
        foreach my $ex (@golden_exons) {
            my $phase_ex = $self->get_unique_EnsEMBL_Exon_with_phase($ex, -1);
            $trans->add_Exon($phase_ex);
        }
    }
    
    $gene->add_Transcript($trans);
}

sub record_t_start_point {
    my( $self, $exon_pos, $ens_exon, $cds_exon, $strand ) = @_;
    
    my $ace_phase = $cds_exon->phase;
    my $ex_id     = $ens_exon->id;
    
    my( $phase );
    if (defined $ace_phase) {
        print STDERR "Exon '$ex_id' has phase $ace_phase from acedb CDS object\n";
        $phase = $ace_phase;
    } else {
        $phase = 0;
    }

    my $offset = (3 - $phase) % 3;
    if ($strand == 1) {
        $exon_pos->{$ex_id} = $cds_exon->start + $offset;
    } else {
        $exon_pos->{$ex_id} = $cds_exon->end   - $offset;
    }

    # Only record the ace_phase if both the EnsEMBL and
    # CDS exons start in the same place.
    if (defined $ace_phase) {
        if ($strand == 1 and $cds_exon->start == $ens_exon->start) {
            $exon_pos->{"ace_phase-$ex_id"} = $ace_phase;
        }
        elsif ($strand == -1 and $cds_exon->end == $ens_exon->end) {
            $exon_pos->{"ace_phase-$ex_id"} = $ace_phase;
        }
    }
}

sub record_t_end_point {
    my( $self, $exon_pos, $ens_exon, $cds_exon, $strand ) = @_;
    
    my $ex_id = $ens_exon->id;
    if ($strand == 1) {
        $exon_pos->{$ex_id} = $cds_exon->end;
    } else {
        $exon_pos->{$ex_id} = $cds_exon->start;
    }
}

sub translation_start_add {
    my( $self, $transl, $exon, $start ) = @_;
        
    $start = $self->exon_coord($exon, $start);
    
    $transl->start_exon_id($exon->id);
    $transl->start($start);
}

sub translation_end_add {
    my( $self, $transl, $exon, $end ) = @_;
        
    $end = $self->exon_coord($exon, $end);
    
    $transl->end_exon_id($exon->id);
    $transl->end($end);
}

sub exon_coord {
    my( $self, $exon, $coord ) = @_;
        
    if ($exon->strand == 1) {
        my $start = $exon->start;
        return $coord - $start + 1;
    } else {
        my $end = $exon->end;
        return $end - $coord + 1;
    }
}

sub get_unique_EnsEMBL_Exon_with_phase {
    my( $self, $exon, $phase ) = @_;
    
    my $key = join('-'
        , $exon->contig_id
        , $exon->strand
        , $exon->start
        , $exon->end
        , $phase
        );

    my( $ens_exon );
    unless ($ens_exon = $self->{'_phased_exon_hash'}{$key}) {
        my $exon_id = $exon->id;
        if ($phase == -1) {
            $exon_id .= $phase;
        } else {
            $exon_id .= '+' . $phase;
        }
        
        $ens_exon = Bio::EnsEMBL::Exon->new;
        $ens_exon->id($exon_id);
        $ens_exon->phase($phase);
        foreach my $field (qw{
            start
            end
            strand
            contig_id
            created
            modified
            version
            })
        {
            $ens_exon->$field($exon->$field());
        }
        
        # Cache in the hash
        $self->{'_phased_exon_hash'}{$key} = $ens_exon;
    }
    
    return $ens_exon;
}

sub get_unique_EnsEMBL_Exon {
    my( $self, $clone, $strand, $exon ) = @_;
    
    my $clone_name = $clone->accession;
    my $ens_contig = $clone->EnsEMBL_Contig;
    my $ens_contig_id = $ens_contig->id;
    my $now = time();
    
    my $start = $exon->start;
    my $end   = $exon->end;
    
    my $key = join('-'
        , $ens_contig_id
        , $strand
        , $start
        , $end
        );
    
    my( $ens_exon );
    unless ($ens_exon = $self->{'_exon_hash'}{$key}) {
        my $exon_number = sprintf("%03d", scalar(keys %{$self->{'_exon_hash'}}) + 1);
        
        # Make a shiny new exon
        $ens_exon = Bio::EnsEMBL::Exon->new;
        $ens_exon->id($self->name .'-'. $exon_number);
        $ens_exon->created($now);
        $ens_exon->modified($now);
        $ens_exon->version(1);
        $ens_exon->start($start);
        $ens_exon->end($end);
        $ens_exon->strand($strand);
        $ens_exon->contig_id($ens_contig_id);
        
        # Cache in the hash
        $self->{'_exon_hash'}{$key} = $ens_exon;
    }
    return $ens_exon;
}




1;

__END__

=head1 NAME - Hum::Ace::Locus

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

