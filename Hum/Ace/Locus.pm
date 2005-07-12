
### Hum::Ace::Locus

package Hum::Ace::Locus;

use strict;
use Carp qw{ confess cluck };

use Bio::EnsEMBL::Exon;
use Bio::EnsEMBL::Translation;

use Bio::Otter::Author;
use Bio::Otter::AnnotatedGene;
use Bio::Otter::AnnotatedTranscript;
use Bio::Otter::Evidence;
use Bio::Otter::TranscriptInfo;
use Bio::Otter::GeneInfo;
use Bio::Otter::GeneRemark;
use Bio::Otter::GeneName;
use Bio::Otter::TranscriptRemark;
use Bio::Otter::TranscriptClass;
use Bio::Otter::GeneSynonym;
use Bio::Otter::Converter;
use Data::Dumper;

sub new {
    my( $pkg ) = shift;
    
    return bless {
        '_CloneSeq_list'    => [],
        '_exon_hash'        => {},
        }, $pkg;
}

sub new_from_ace {
    my( $pkg, $ace ) = @_;
    
    my $self = $pkg->new;
    $self->save_locus_info($ace);
    return $self;
}

sub new_from_ace_tag {
    my( $pkg, $ace ) = @_;
    
    my $self = $pkg->new;
    $self->save_locus_info($ace->fetch);
    return $self;
}

sub new_from_Locus {
    my ($old) = @_;

    my $new = ref($old)->new;

    $new->set_aliases( $old->list_aliases );
    $new->set_remarks( $old->list_remarks );
    $new->set_positive_SubSeq_names( $old->list_positive_SubSeq_names );

    
    foreach my $method ( qw{
        name
        description
        gene_type
        gene_type_prefix
        is_truncated
        is_complete
        is_new_format
        }){
        
        $new->$method( $old->$method() );
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

sub description {
    my( $self, $description ) = @_;
    
    if ($description) {
        $self->{'_description'} = $description;
    }
    return $self->{'_description'};
}

sub otter_id {
    my( $self, $otter_id ) = @_;
    
    if ($otter_id) {
        $self->{'_otter_id'} = $otter_id;
    }
    return $self->{'_otter_id'};
}

sub gene_type {
    my( $self, $gene_type ) = @_;
    
    if ($gene_type) {
        $self->{'_gene_type'} = $gene_type;
    }
    return $self->{'_gene_type'};
}

sub unset_gene_type{
    my ($self ) = @_ ;
    $self->{'_gene_type'} = undef ;
}


sub gene_type_prefix {
    my( $self, $gene_type_prefix ) = @_;
    
    # Can unset with empty string
    if (defined $gene_type_prefix) {
        $self->{'_gene_type_prefix'} = $gene_type_prefix;
    }
    return $self->{'_gene_type_prefix'} || '';
}


sub is_truncated {
    my( $self, $is_truncated ) = @_;
    
    #cluck "called is_truncated";
    
    if (defined $is_truncated) {
        $self->{'_is_truncated'} = $is_truncated ? 1 : 0;
    }
    return $self->{'_is_truncated'} || 0;
}


{
    ### Gene types need to be set from set of transcripts
    ### Need to propagate Unprocessed/Processed Pseudogene
    my @type_map = (
        [qw{ Known                      Type.Gene.Known                 }],
        [qw{ Novel_CDS                  Type.Gene.Novel_CDS             }],
        [qw{ Novel_Transcript           Type.Gene.Novel_Transcript      }],
        [qw{ Unprocessed_pseudogene     Type.Pseudogene.Unprocessed     }],
        [qw{ Processed_pseudogene       Type.Pseudogene.Processed       }],
        [qw{ Pseudogene                 Type.Pseudogene                 }],
        [qw{ Putative                   Type.Putative                   }],
        [qw{ Transposon                 Type.Transposon                 }],
        [qw{ Ig_Segment                 Type.Ig_Segment                 }],
        [qw{ Ig_Pesuodgene_Segment      Type.Ig_Pesuodgene_Segments     }],
        );

    sub save_locus_info {
        my( $self, $ace_locus ) = @_;

        #print STDERR $ace_locus->asString;
        $self->name($ace_locus->name);

        if (my $ott = $ace_locus->at('Otter.Locus_id[1]')) {
            $self->otter_id($ott->name);
        }

        if ($ace_locus->at('Otter.Truncated')) {
            $self->is_truncated(1);
            #warn $self->name, " is truncated";
        }

        if (my $type = $ace_locus->at('Type_prefix[1]')) {
            $self->gene_type_prefix($type->name);
        }

        my( @pos_name );
        foreach my $pos ($ace_locus->at('Positive.Positive_sequence[1]')) {
            my $name = $pos->name;
            $name =~ s/^em://i;
            push(@pos_name, $name);
        }
        $self->set_positive_SubSeq_names(@pos_name);

        my( @aliases );
        foreach my $alias ($ace_locus->at('Alias[1]')) {
            my $alias_str = $alias->asString;
            chomp($alias_str);
            push(@aliases, $alias_str);
        }
        $self->set_aliases(@aliases);

        if (my $full = $ace_locus->at('Full_name[1]')) {
            my $txt = $full->name;
            $txt =~ s/\s+$//;
            $txt =~ s/\n/ /g;
            $self->description($txt);
        }

        my( @remarks );
        foreach my $rem ($ace_locus->at('Remark[1]')) {
            my $txt = $rem->name;
            $txt =~ s/\s+$//;
            $txt =~ s/\n/ /g;
            push(@remarks, $txt);
        }
        $self->set_remarks(@remarks);



        my( $gene_type );
        foreach my $t (@type_map) {
            my( $type, $tag ) = @$t;
            if ($ace_locus->at($tag)) {
                $gene_type = $type;
                last;
            }
        }
        
        if ($gene_type) {
            $self->gene_type($gene_type);
        } else {
            #warn("No Gene type for locus '$ace_locus' :\n", $ace_locus->asString);
        }        
    }
}

sub set_aliases {
    my( $self, @aliases ) = @_;
    
    $self->{'_Alias_name_list'} = [@aliases];
}

sub list_aliases {
    my( $self ) = @_;
    
    if (my $al = $self->{'_Alias_name_list'}) {
        return @$al;
    } else {
        return;
    }
}

sub set_remarks {
    my( $self, @remarks ) = @_;
    
    $self->{'_remark_list'} = [@remarks];
}

sub list_remarks {
    my( $self ) = @_;
    
    if (my $rl = $self->{'_remark_list'}) {
        return @$rl;
    } else {
        return;
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

sub drop_positive_SubSeq_names {
    my( $self ) = @_;
    
    $self->{'_positive_SubSeq_name_list'} = undef;
}

sub get_all_SubSeqs {
    my( $self ) = @_;
    
    my %locus_subseq = map {$_, 1} $self->list_positive_SubSeq_names;
    my( @subs );
    foreach my $clone ($self->get_all_CloneSeqs) {
        foreach my $sub ($clone->get_all_SubSeqs) {
            my $name = $sub->name;
            if ($locus_subseq{$name}) {
                push(@subs, $sub);
                $locus_subseq{$name} = 0;
            }
        }
    }
    
    ### Could check that we found all the SubSeqs in %locus_subseq
    
    return @subs;
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

sub is_new_format {
    my( $self ) = @_;
    
    my $old_format = 0;
    my $new_format = 0;
    
    my $err = '';
    foreach my $sub ($self->get_all_SubSeqs) {
        my $sub_name  = $sub->name;
        my $meth_name = $sub->GeneMethod->name;
        next if $meth_name =~ /^GD/;
        
        $err .= sprintf "  %12s  %-s\n", $sub_name, $meth_name;
        
        if ($meth_name =~ /supported_CDS/) {
            $old_format = 1;
        }
        elsif ($meth_name =~ /supported$/) {
            $new_format = 1;
        }
        
        unless ($new_format) {
            if ($sub->upstream_subseq_name
                or $sub->downstream_subseq_name) {
                $new_format = 1;
            }
        }
    }
    
    if ($old_format == $new_format) {
        if ($old_format and $new_format) {
            confess "Locus '", $self->name,
                "' has both old and new format SubSequences:\n", $err;
        } else {
            # Default to new_format - this happens
            # when the Locus doesn't contain a CDS.
            $new_format = 1;
        }
    }
    return $new_format ? 1 : 0;
}

sub make_Otter_Gene {
    my( $self ) = @_;
    
    require Hum::Fox::AceData::Locus;
    require Hum::Fox::AceData::SubSequence;

    my $gene_name = $self->name;
    my $pre       = $self->gene_type_prefix;
    my $otter_gene_name = $pre ? "$pre:$gene_name" : $gene_name;
    
    # Make a new Otter Gene object
    my $gene = Bio::Otter::AnnotatedGene->new;

    # Get annotator and edit_time from Fox database
    my ($author_name, $edit_time) = Hum::Fox::AceData::Locus
        ->get_who_and_edit_time($gene_name);
    if (! $author_name or $author_name eq 'jgrg') {
        $author_name = 'vega';
    }
    $edit_time ||= time;
    my $author = new Bio::Otter::Author(
        -NAME  => $author_name,
        -EMAIL => "$author_name\@sanger.ac.uk",
        );

    my @gene_remarks;
    foreach my $remark ($self->list_remarks) {
      push @gene_remarks, Bio::Otter::GeneRemark->new(-remark => $remark);
    }

    my $geneinfo = new Bio::Otter::GeneInfo(-author    => $author,
                                            -name      => new Bio::Otter::GeneName( -name => $otter_gene_name),
                                            -remark    => \@gene_remarks);
    $gene->description($self->description);
    $gene->gene_info($geneinfo);
    $gene->version(1);
    $gene->created($edit_time);
    $gene->modified($edit_time);

    foreach my $alias ($self->list_aliases) {
      $geneinfo->synonym(new Bio::Otter::GeneSynonym(-name => $alias));
    }
    
    my $gene_type = $self->gene_type;
    if ($gene_type eq 'Known' or $gene_type eq 'Polymorphic_known') {
        $geneinfo->known_flag(1);
    }

    my $i = 0;
    foreach my $set ($self->make_transcript_sets) {
        $i++;
        my $t_name = sprintf("%s-%03d", $gene_name, $i);
        my $trans = $self->make_transcript($gene, $set, $t_name);
    }
    if (scalar(@{$gene->get_all_Transcripts})) {
        # Gene type is aggregate function of transcript types
        #$gene->set_gene_type_from_transcript_classes;
        my $type = Bio::Otter::Converter::gene_type_from_transcript_set($gene->get_all_Transcripts(), $geneinfo->known_flag());
        $type = $pre ? "$pre:$type" : $type;
        print "Decided on genetype '$type'\n";
        $gene->type($type);
        return $gene;
    } else {
        warn "Gene didn't get assigned any transcripts\n";
        return;
    }
}

### This doesn't know about gene_type_prefix.
sub make_EnsEMBL_Gene {
    my( $self ) = @_;
    
    my $gene_name = $self->name;
    
    # Make a new EnsEMBL Gene object
    my $time = time;
    my $gene = Bio::EnsEMBL::Gene->new;
    $gene->stable_id($self->name);
    
    my $gene_type = $self->gene_type_prefix . $self->gene_type;
    $gene->type($gene_type);
    $gene->version(1);
    $gene->created($time);
    $gene->modified($time);

    my $i = 0;
    foreach my $set ($self->make_transcript_sets) {
        $i++;
        my $t_name = sprintf("%s-%03d", $gene_name, $i);
        $self->make_transcript($gene, $set, $t_name);
    }
    if (@{$gene->get_all_Transcripts}) {
        return $gene;
    } else {
        return;
    }
}

sub make_transcript_sets {
    my( $self ) = @_;
    
    my $gene_type = $self->gene_type;
    my $is_new_format = $self->is_new_format;
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
            my $gene_method_name = $t->GeneMethod->name;
            
            # Ignore Gene ID transcripts
            ####if ($gene_method_name =~ /^GD/) {
####                warn "Skipping Gene ID transcript '$t_name'\n";
####                next;
####            },
            
            # Only get SubSeqs from this locus
            next unless $is_locus_seq{$t_name};
            
            #unless ($t->get_all_Exons) {
            #    warn "Transcript '$t_name' has zero exons in golden path - skipping\n";
            #    next;
            #}
            
            my( $pair_name, $is_mRNA ) = $t_name =~ /^(.+?)(\.mRNA)?$/;
            unless ($is_mRNA) {
                if ($gene_method_name =~ /mRNA$/) {
                    $is_mRNA = 1;
                }
            }
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
            
            # Try to get a CDS from the other clone_sets if
            # we have an mRNA object, but not a CDS.
            # (But not if it is a new format Locus, where
            # the mRNA CDS pairs are kept together).
            if ($mrna and ! $cds and ! $is_new_format) {
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
            
            # Check that all the CDS exons (if there are any)
            # are in the mRNA exons.
            # (Unless it is the same object.)
            if ($cds and $cds != $mrna and $cds->get_all_Exons) {
                my $cds_name  = $cds->name;
                my $mrna_name = $mrna->name;
                
                ### contains_all_exons can be improved so that it
                ### checks for mismatches in internal exons.
                unless ($mrna->contains_all_exons($cds)) {
                    confess "'$mrna_name' doesn't contain all the exons in '$cds_name'";
                } else {
                    #warn "'$mrna_name' contains all the exons in '$cds_name'";
                }
            }
            
            # Don't add CDS if it isn't transcribed
            if ($gene_type eq 'Pseudogene' or $gene_type eq 'Putative' or 
                $gene_type eq 'Processed_pseudogene' or $gene_type eq 'Unprocessed_pseudogene') {
                push(@$pairs, [$pair_name, $mrna]);
            } else {
                push(@$pairs, [$pair_name, $mrna, $cds]);
            }
        }
        
        # Eliminate mRNA + CDS pairs where the mRNA
        # object is actually the CDS object, but the
        # CDS is infact paired with another mRNA
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
            # CDS paired with another mRNA
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

    # Show the clone sets we have made
    foreach my $c (@clone_sets) {
        print STDERR "\nclone:\n";
        foreach my $pair (@$c) {
            print STDERR "  ['", $pair->[1]->name, "'";
            print STDERR ", '", $pair->[2]->name, "'" if $pair->[2];
            print STDERR "]\n";

        }
    }
    
    my( @sets );
    if ($isoform_count > 1 and @clone_sets > 1) {
        #SMJS For ZFish don't check isoform_count if ($isoform_count > 1 and @clone_sets > 1) {
        #if (@clone_sets > 1) {
        print STDERR "Processing multi-clone multi-isoform locus\n";
    
        @sets = $self->make_transcript_sets_for_complex_locus(@clone_sets)
            or die "Got zero sets from complex locus";
    } else {
        for (my $i = 0; $i < $isoform_count; $i++) {
            my @s = map {defined($_) ? $_->[$i] : undef} @clone_sets;
            push(@sets, [@s]);
        }
    }
    return @sets;
}

sub make_name_hashes_from_continue_tags {
    my( $self ) = @_;
    
    my %name_SubSeq = map {$_->name, $_} $self->get_all_SubSeqs;
    
    my( @name_hashes );
    foreach my $name (keys %name_SubSeq) {
        my $sub = $name_SubSeq{$name} or next;
        #warn "\n  Starting from: '$name'\n";
        $name_SubSeq{$name} = 0;
        my $nh = {$name => 1};
        push(@name_hashes, $nh);
    
        my $up = $sub;
        while (my $up_name = $up->upstream_subseq_name) {
            #warn "       Upstream: '$up_name'\n";
            $up = $name_SubSeq{$up_name}
                or confess "Can't see '$up_name'";
            $name_SubSeq{$up_name} = 0;
            $nh->{$up_name} = 1;
        }

        my $down = $sub;
        while (my $down_name = $down->downstream_subseq_name) {
            #warn "     Downstream: '$down_name'\n";
            $down = $name_SubSeq{$down_name}
                or confess "Can't see '$down_name'";
            $name_SubSeq{$down_name} = 0;
            $nh->{$down_name} = 1;
        }
    }
    
    return @name_hashes;
}

sub make_transcript_sets_for_complex_locus {
    my( $self, @clone_sets ) = @_;

    my( @name_hashes );
    if (my $lister = $self->set_names_lister) {
        # If we have more than isoform spanning more than
        # one clone, then we need to rely on a hand-made
        # list of names which make the isoform.
        @name_hashes = &$lister($self);
    }
    unless (@name_hashes) {
        @name_hashes = $self->make_name_hashes_from_continue_tags;
    }
    confess "Can't get name sets" unless @name_hashes;
    
    #use Data::Dumper;
    #print STDERR Dumper(\@name_hashes);

    my( @sets );
    foreach my $names (@name_hashes) {
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
                $names->{ $cds->name} = 0 if $cds;
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
    
    return @sets;
}

sub make_transcript {
    my( $self, $gene, $set, $t_name ) = @_;
    
    print STDERR "\nNew transcript: '$t_name'\n";
    
    my @locus_clones = $self->get_all_CloneSeqs
        or confess "No CloneSeqs attached";
    
    # Make the transcript
    my $trans = Bio::Otter::AnnotatedTranscript->new;
    
    my $ti = Bio::Otter::TranscriptInfo->new(
        -name                 => $t_name,
        -cds_start_not_found  => 0,
        -cds_end_not_found    => 0,
        -mrna_start_not_found => 0,
        -mrna_end_not_found   => 0,
        );

    $trans->transcript_info($ti);
    $trans->version(1);    
    
    # Make the translation
    my $translation = Bio::EnsEMBL::Translation->new;
    $translation->version(1);
    
    # The orientation of the transcript on the golden path (chromosome)
    my( $golden_orientation );
    
    my $is_coding  = 0;
    
    my $transcript_remarks            = {};
    my $transcript_type               = {};
    my $evidence_type                 = {};
    my( $author_name, $edit_time );
    my( @golden_exons, %exon_t_start, %exon_t_end );
    for (my $i = 0; $i < @locus_clones; $i++) {
        my $clone = $locus_clones[$i];
        #my $clone_id = $clone->accession;
        my $clone_strand = $clone->golden_strand;
        
        # May be no exons in this clone
        my $pair  = $set->[$i] or next;

        my( $pair_name, $mrna, $cds ) = @$pair;
        
        # All the exons might have been trimmed from the sequence
        # because none of them are on the golden path
        next unless $mrna->get_all_Exons;
        
        {
            my @unique = ($mrna);
            if ($cds and $cds != $mrna) {
                push(@unique, $cds);
            }
            
            foreach my $sub (@unique) {
                $transcript_type->{$sub->GeneMethod->name}++;

                my $evidence = $sub->evidence_hash;
                while (my ($type, $ev) = each %$evidence) {
                    foreach my $id (@$ev) {
                        $evidence_type->{$type}{$id} = 1;
                    }
                }

                # Get latest author and edit time from Fox for this set of subsequences
                my ($who, $when) = Hum::Fox::AceData::SubSequence
                    ->get_who_and_edit_time($sub->name);
                if ($who) {
                    if ($author_name) {
                        next if $when < $edit_time;
                    }
                    $author_name = $who;
                    $edit_time   = $when;
                }
            }
        }
        
        $self->extract_transcript_remarks($mrna, $transcript_remarks);
        if ($cds) {
            $is_coding = 1;
            $self->extract_transcript_remarks($cds, $transcript_remarks)
                unless $cds == $mrna;
        }

        # Check that mRNA and CDS are on the same strand
        # if we have them both.        
        my $pair_strand = $mrna->strand;
        if ($cds and $pair_strand != $cds->strand) {
            confess "CDS and mRNA on opposite strands in '$pair_name'";
        }

        # Check the orientation of this piece of the gene
        # relative to the chromosome
        my $ori = $pair_strand * $clone_strand;
        if ($golden_orientation) {
            #confess "In pair '$pair_name' ori '$ori' doesn't match chromosome ori '$golden_orientation'"
            warn "In pair '$pair_name' ori '$ori' doesn't match chromosome ori '$golden_orientation'"
                unless $ori == $golden_orientation;
        } else {
            $golden_orientation = $ori;
        }

        if (($golden_orientation == 1 and $i == 0) or ($golden_orientation == -1 and $i == $#locus_clones)) {
            if ($mrna->start_not_found or ($cds and $cds->start_not_found)) {
                $ti->mRNA_start_not_found(1);
            }
        }

        if (($golden_orientation == 1 and $i == $#locus_clones) or ($golden_orientation == -1 and $i == 0)) {
            if ($mrna->end_not_found or ($cds and $cds->end_not_found)) {
                $ti->mRNA_end_not_found(1);
            }
        }
        
        # Make the EnsEMBL exons
        my @cds_exons = $cds->get_all_CDS_Exons if $cds;
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
            my $ex_id = $ens_exon->stable_id;
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
    
    if (! $author_name or $author_name eq 'jgrg') {
        $author_name = 'vega';
    }
    $edit_time ||= time;
    my $author = new Bio::Otter::Author(
        -name  => $author_name,
        -email => "$author_name\@sanger.ac.uk",
        );
    $ti->author($author);

    # Order @golden exons so that they run
    # translation start -> end.
    if ($golden_orientation == -1) {
        @golden_exons = reverse(@golden_exons);
    }
        
    if ($is_coding) {
        $trans->translation($translation);

        # Find translation start
        my( $start_exon_id, $t_start );
        for (my $i = 0; $i < @golden_exons; $i++) {
            my $ex = $golden_exons[$i];
            
            ### What is in these exon stable_ids?
            if ($t_start = $exon_t_start{$ex->stable_id}) {
                $start_exon_id = $ex->stable_id;
                
                # CDS start has not been found if the mRNA start is
                # not found and the translation begins at the first
                # base of the first exon.
                if ($i == 0 and $ti->mRNA_start_not_found) {
                    if (($ex->strand == 1 and $ex->start == $t_start) or ($ex->end == $t_start)) {
                        $ti->cds_start_not_found(1);
                    }
                }
                
                last;
            }
        }
        confess "Missing translation start" unless $t_start;

        # Find translation end
        my( $end_exon_id, $t_end );
        for (my $i = $#golden_exons; $i >= 0; $i--) {
            my $ex = $golden_exons[$i];
            
            if ($t_end = $exon_t_end{$ex->stable_id}) {
                $end_exon_id = $ex->stable_id;
                
                # CDS end has not been found if the mRNA end is
                # not found and the translation ends on the last
                # base of the last exon.
                if ($i == $#golden_exons and $ti->mRNA_end_not_found) {
                    if (($ex->strand == 1 and $ex->end == $t_end) or ($ex->start == $t_end)) {
                        $ti->cds_end_not_found(1);
                    }
                }
                
                last;
            }
        }
        confess "Missing translation end" unless $t_end;
        
        # Add exons to the transcript
        my $prev_phase = -1;
        foreach my $ex (@golden_exons) {
            my $ex_id     = $ex->stable_id;
            my $ace_phase  = $exon_t_start{"ace_phase-$ex_id"};

            # Set phase from acedb or phase 0 if this is the first coding exon
            if ($ex_id eq $start_exon_id) {
                $prev_phase = defined($ace_phase) ? $ace_phase : 0;
            }

            # Now calculate the phase for the next exon:
            
            # If the next exon will be non-coding,
            # set $end_phase back to -1.
            my $end_phase = -1;
            if ($ex_id eq $end_exon_id) {
                $end_phase = -1;
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
                            #print STDERR "moving exon start $start > $t_start\n";
                            $start = $t_start;
                        }
                    } else {
                        unless ($end == $t_end) {
                            #print STDERR "moving exon end $t_start < $end\n";
                            $end = $t_start;
                        }
                    }
                }
                my $translated_length = $end - $start + 1;
                $end_phase = ($translated_length + $prev_phase) % 3;
            }

            # Get the exon with this phase
            my $phase_ex = $self->get_unique_EnsEMBL_Exon_with_phase($ex, $prev_phase, $end_phase);
            $trans->add_Exon($phase_ex);
            # Add translation start and/or end
            if ($ex_id eq $start_exon_id) {
                $self->translation_start_add($translation, $phase_ex, $t_start);
            }
            if ($ex_id eq $end_exon_id) {
                $self->translation_end_add($translation, $phase_ex, $t_end);
            }

            $prev_phase = $end_phase;
        }
    } else {
    
        # Add exons to the transcript
        foreach my $ex (@golden_exons) {
            my $phase_ex = $self->get_unique_EnsEMBL_Exon_with_phase($ex, -1, -1);
            $trans->add_Exon($phase_ex);
        }
    }
    
    # Add transcript evidence
    {
        my( @all_evidence );
        while (my ($type, $id_list) = each %$evidence_type) {
            foreach my $id (keys %$id_list) {
                push(@all_evidence,  Bio::Otter::Evidence->new(
                    -NAME   => $id,
                    -TYPE   => $type,
                    ));
            }
        }
        $ti->add_Evidence(@all_evidence);
    }
    
    # Add transcript remarks - in the order in which they were made
    foreach my $remark (sort {$transcript_remarks->{$a} <=> $transcript_remarks->{$b}} keys %$transcript_remarks) {
        $ti->remark(
            Bio::Otter::TranscriptRemark->new(
                -remark => $remark,
                )
            );
    }
    
    $self->set_transcript_class($trans, $transcript_type);
    
    $gene->add_Transcript($trans);
}

{
    # These Gene types can only have one type of transcript
    my %simple = map {$_, 1} qw{
        Unprocessed_pseudogene
        Processed_pseudogene
        Pseudogene
        Putative
        Transposon
        IG_segement
        };
    
    # Most genes have either a coding or non-coding transcript
    my %typical = map {$_, 1} qw{
        Known
        Novel_CDS
        Novel_Transcript
        Polymorphic
        Polymorphic_known
        };

    sub set_transcript_class {
        my( $self, $trans, $types ) = @_;

        my $gene_type = $self->gene_type or confess "gene_type not set";
        my( $class );
        if ($typical{$gene_type}) {
            if ($types->{'Pseudogene'}) {
                $class = 'Pseudogene';
            }
            elsif ($trans->translation) {
                $class = 'Coding';
            }
            else {
                $class = 'Transcript';
            }
        }
        elsif ($simple{$gene_type}) {
            $class = $gene_type;
        }
        else {
            confess "Unknown gene type '$gene_type'";
        }
        
        $trans->transcript_info->class(
            Bio::Otter::TranscriptClass->new( -name => $class )
            );
    }
}

sub extract_transcript_remarks {
    my( $self, $subseq, $remarks_hash ) = @_;
    
    my $i = keys %$remarks_hash;
    my @remarks = (
        $subseq->list_remarks,
        map("Annotation_remark- $_", $subseq->annotation_remarks),
        );
    foreach my $remark (@remarks) {
        $remark =~ s/continue.?\s+(as|from)\s+\S+(\s+in\s+\S+)?//ig;
        $remark =~ s/[,\s]*variant\s*\d+\s*$//ig;
        next unless $remark =~ /\w/;
        unless ($remarks_hash->{$remark}) {
            $remarks_hash->{$remark} = $i;
            $i++;
        }
    }
}

sub record_t_start_point {
    my( $self, $exon_pos, $ens_exon, $cds_exon, $strand ) = @_;
    
    my $ens_phase = $cds_exon->ensembl_phase;
    my $ex_id     = $ens_exon->stable_id;

    if ($strand == 1) {
        $exon_pos->{$ex_id} = $cds_exon->start;
    } else {
        $exon_pos->{$ex_id} = $cds_exon->end;
    }

    # Only record the ace_phase if both the EnsEMBL and
    # CDS exons start in the same place.
    if (defined $ens_phase) {
        if ($strand == 1 and $cds_exon->start == $ens_exon->start) {
            $exon_pos->{"ace_phase-$ex_id"} = $ens_phase;
        }
        elsif ($strand == -1 and $cds_exon->end == $ens_exon->end) {
            $exon_pos->{"ace_phase-$ex_id"} = $ens_phase;
        }
    }
}

sub record_t_end_point {
    my( $self, $exon_pos, $ens_exon, $cds_exon, $strand ) = @_;
    
    my $ex_id = $ens_exon->stable_id;
    if ($strand == 1) {
        $exon_pos->{$ex_id} = $cds_exon->end;
    } else {
        $exon_pos->{$ex_id} = $cds_exon->start;
    }
}

sub translation_start_add {
    my( $self, $transl, $exon, $start ) = @_;
        
    $start = $self->exon_coord($exon, $start);
    
    $transl->start_Exon($exon);
    $transl->start($start);
}

sub translation_end_add {
    my( $self, $transl, $exon, $end ) = @_;
        
    $end = $self->exon_coord($exon, $end);
    
    $transl->end_Exon($exon);
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
    my( $self, $exon, $phase, $end_phase ) = @_;
    
    my $key = join('-'
        , $exon->contig->dbID
        , $exon->strand
        , $exon->start
        , $exon->end
        , $phase
        , $end_phase
        );

    #print STDERR "Got key $key\n";
    my( $ens_exon );
    unless ($ens_exon = $self->{'_phased_exon_hash'}{$key}) {
        #print STDERR "Making new exon for $key\n";
        my $exon_id = $exon->stable_id;
        if ($phase == -1) {
            $exon_id .= $phase;
        } else {
            $exon_id .= '+' . $phase;
        }
        if ($end_phase == -1) {
            $exon_id .= $end_phase;
        } else {
            $exon_id .= '+' . $end_phase;
        }
        
        $ens_exon = Bio::EnsEMBL::Exon->new;
        $ens_exon->stable_id($exon_id);
        $ens_exon->phase($phase);
        $ens_exon->end_phase($end_phase);
        foreach my $field (qw{
            start
            end
            contig
            strand
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
    my( $self, $clone, $strand, $exon, $cds_exon ) = @_;
    
    my $clone_name = $clone->accession;
    my $ens_contig = $clone->EnsEMBL_Contig
        or confess "No Ensembl contig attached";
    my $ens_contig_id = $ens_contig->id;
    my $ens_contig_dbid = $ens_contig->dbID;
    
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
        $ens_exon->stable_id($self->name .'-'. $exon_number);
        $ens_exon->version(1);
        $ens_exon->created(time);
        $ens_exon->modified(time);
        $ens_exon->start($start);
        $ens_exon->end($end);
        $ens_exon->strand($strand);
        $ens_exon->contig($ens_contig);
        
        # Cache in the hash
        $self->{'_exon_hash'}{$key} = $ens_exon;
    }

    return $ens_exon;
}

sub ace_string {
    my( $self, $old_name ) = @_;

    my $name = $self->name;
    my $ace = '';
    if ($old_name){
        $ace .= qq{-R Locus "$old_name" "$name"\n};
    }

    $ace .= qq{\nLocus : "$name"\n}
        . qq{-D Type_prefix\n}
        . qq{-D Type\n}
        . qq{-D Full_name\n}
        . qq{-D Remark\n}
        . qq{-D Alias\n}
        . qq{\n};

    my $txt = Hum::Ace::AceText->new;
    $txt->add_tag_values(['Locus', ':', $name]);

    ### Need to add locus type and positive sequences
    ### Are the ?Seqence tags pointing to Clone or SubSeqences?

    if (my $ott = $self->otter_id) {
        $txt->add_tag_values(['Locus_id', $ott]);
    }
    if (my $prefix = $self->gene_type_prefix) {
        $txt->add_tag_values(['Type_prefix', $prefix]);
    }
    if (my $type = $self->gene_type) {
        if ($type =~ /^((Unp|P)rocessed)_pseuodgene$/) {
            $type = $1;
        }
        $txt->add_tag($type);
    }
    foreach my $alias ($self->list_aliases) {
        $txt->add_tag_values(['Alias', $alias]);
    }
    if (my $desc = $self->description) {
        $txt->add_tag_values(['Full_name', $desc]);
    }
    foreach my $remark ($self->list_remarks) {
        $txt->add_tag_values(['Remark', $remark]);
    }

    $ace .= $txt->ace_string . "\n";

    return $ace;
}

# Needed to preserve otter_id?
# If locus is renamed twice, then otter
sub old_ace_string {
    my( $self, $old_name ) = @_;

    my $name = $self->name ;
    my $ace = '';
    if ($old_name){
        $ace .= qq{-R Locus "$old_name" "$name"\n};
    }

    $ace .= qq{\nLocus : "$name"\n}
        . qq{-D Type_prefix\n}
        . qq{-D Type\n}
        . qq{-D Full_name\n}
        . qq{-D Remark\n}
        . qq{\nLocus : "$name"\n};

    ### Need to add locus type and positive sequences
    ### Are the ?Seqence tags pointing to Clone or SubSeqences?

    if (my $ott = $self->otter_id) {
        $ace .= qq{Locus_id "$ott"\n};
    }
    if (my $prefix = $self->gene_type_prefix) {
        $ace .= qq{Type_prefix "$prefix"\n};
    }
    if (my $type = $self->gene_type) {
        if ($type =~ /^((Unp|P)rocessed)_pseuodgene$/) {
            $type = $1;
        }
        $ace .= qq{$type\n};
    }
    if (my $desc = $self->description) {
        $ace .= qq{Full_name "$desc"\n};
    }
    foreach my $remark ($self->list_remarks) {
        $ace .= qq{Remark "$remark"\n};
    }

    $ace .= "\n";

    return $ace;
}

#sub clone {
#    my( $old ) = @_;
#
#    my $new = ref($old)->new;
#    foreach my $field (qw{
#        name
#        otter_id
#        })
#    {
#        $new->$field($old->$field());
#    }
#    
#}

#sub DESTROY {
#    my( $self ) = @_;
#    
#    print STDERR "Locus ", $self->name, " is released\n";
#}


1;

__END__

=head1 NAME - Hum::Ace::Locus

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

