
### Hum::Ace::MethodCollection

package Hum::Ace::MethodCollection;

use strict;
use Carp;
use Symbol 'gensym';

use Hum::Ace::Method;
use Hum::Ace::AceText;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub new_from_string {
    my( $pkg, $str ) = @_;
    
    my $self = $pkg->new;

    # Split text into paragraphs (which are separated by one or more blank lines).
    foreach my $para (split /\n{2,}/, $str) {
        # Create Method object from paragraphs that have
        # any lines that begin with a word character.
        if ($para =~ /^\w/m) {
            my $txt  = Hum::Ace::AceText->new($para);
            my $meth = Hum::Ace::Method->new_from_AceText($txt);
            $self->add_Method($meth);
        }
    }
    return $self;
}

sub new_from_ace_handle {
    my ($pkg, $ace) = @_;
    
    $ace->raw_query('find Method *');
    # Using the AceText object strips out any server comments and nulls
    my $meths = Hum::Ace::AceText->new($ace->raw_query('show -a'));
    return $pkg->new_from_string($meths->ace_string);
}


sub ace_string {
    my( $self ) = @_;
    
    my $str = '';
    foreach my $meth (@{$self->get_all_Methods}) {
        $str .= $meth->ace_string;
        $str .= $meth->zmap_style_string;
    }
    return $str;
}

sub new_from_file {
    my( $pkg, $file ) = @_;
    
    local $/ = undef;
    
    my $fh = gensym();
    open $fh, $file or die "Can't read '$file' : $!";
    my $str = <$fh>;
    close $fh or die "Error reading '$file' : $!";
    return $pkg->new_from_string($str);
}

sub write_to_file {
    my( $self, $file ) = @_;
    
    my $fh = gensym();
    open $fh, "> $file" or confess "Can't write to '$file' : $!";
    print $fh $self->ace_string;
    close $fh or confess "Error writing to '$file' : $!";
}

sub add_Method {
    my( $self, $method ) = @_;
    
    if ($method) {
        my $name = $method->name
            or confess "Can't add un-named method";
        if (my $existing = $self->{'_method_by_name'}{$name}) {
            confess "Already have method called '$name':\n",
                $existing->ace_string;
        }
        my $lst = $self->get_all_Methods;
        push @$lst, $method;
        $self->{'_method_by_name'}{$name} = $method;
        
    } else {
        confess "missing Hum::Ace::Method argument";
    }
}

sub get_all_Methods {
    my( $self ) = @_;
    
    my $lst = $self->{'_method_list'} ||= [];
    return $lst;
}

sub get_all_transcript_Methods {
    my ($self) = @_;
    
    if (my $lst = $self->{'_method_list'}) {
        return grep $_->transcript_type, @$lst;
    } else {
        return;
    }
}

sub get_all_mutable_Methods {
    my ($self) = @_;
    
    if (my $lst = $self->{'_method_list'}) {
        return grep $_->mutable, @$lst;
    } else {
        return;
    }
}

sub get_all_mutable_non_transcript_Methods {
    my ($self) = @_;
    
    if (my $lst = $self->{'_method_list'}) {
        return grep {$_->mutable and ! $_->transcript_type} @$lst;
    } else {
        return;
    }
}

sub get_Method_by_name {
    my( $self, $name ) = @_;
    
    confess "Missing name argument" unless $name;
    
    return $self->{'_method_by_name'}{$name};
}

sub flush_Methods {
    my( $self ) = @_;
    
    $self->{'_method_list'} = [];
    $self->{'_method_by_name'} = {};
}

sub process_for_otterlace {
    my( $self ) = @_;
    
    $self->create_full_gene_Methods;
    $self->cluster_Methods_with_same_column_group;
    $self->order_by_zone;
    $self->assign_right_priorities;
}

sub order_by_zone {
    my( $self ) = @_;
    
    my $lst = $self->get_all_Methods;
    
    # Multiple methods with the same zone_number will
    # be left in their original order by sort.
    @$lst = sort { ($a->zone_number || 0) <=> ($b->zone_number || 0) } @$lst;
}

sub order_by_right_priority {
    my( $self ) = @_;
    
    my $lst = $self->get_all_Methods;
    @$lst = sort { ($a->right_priority || 0) <=> ($b->right_priority || 0) } @$lst;
}


sub cluster_Methods_with_same_column_group {
    my( $self ) = @_;
    
    my @all_meth = @{$self->get_all_Methods};
    $self->flush_Methods;
    my %column_cluster = ();
    foreach my $meth (@all_meth) {
        if (my $col = $meth->column_group) {
            my $cluster = $column_cluster{$col} ||= [];
            push(@$cluster, $meth);
        }
    }
    while (my $meth = shift @all_meth) {
        if (my $col = $meth->column_group) {
            # Add the whole cluster where we find its first
            # member in the list.
            if (my $cluster = delete $column_cluster{$col}) {
                my $zone = $meth->zone_number;
                foreach my $meth (@$cluster) {
                    # Make sure they are all in the same zone
                    $meth->zone_number($zone);
                    $self->add_Method($meth);
                }
            }
        } else {
            $self->add_Method($meth);
        }
    }
}

sub assign_right_priorities {
    my( $self ) = @_;
    
    my $incr = 0.001;
    
    # This is a bit bigger than the hard-coded
    # value for right_priority of DNA in fMap: 
    my $dna_pos = 6.3;
    
    # The "oligo zone" is a region of the fMap where weird things
    # happen due to the special oligo drawing code.
    my @oligo_zone = (3.2, 3.9);
    
    my $meth_list = $self->get_all_Methods;
    # Must start at 0.1 or objects get drawn left of the ruler in fMap
    my $pos = 0.1;
    for (my $i = 0; $i < @$meth_list; $i++) {
        my $method = $meth_list->[$i];
        next if $method->right_priority_fixed;

        my $prev = $i > 0 ? $meth_list->[$i - 1] : undef;

        # Don't increase right_priority if we are
        # in the same column as the previous method
        if  ($prev and $prev->column_group and $prev->column_group eq $method->column_group) {
            $method->right_priority($prev->right_priority);
        }
        elsif ($pos >= $oligo_zone[0] and $pos <= $oligo_zone[1]) {
            #warn "Skipping oligo twilight zone\n";
            $pos = $oligo_zone[1] + $incr;
        }
        elsif (my $pri = $method->right_priority) {
            # Keep values greater than 5 greater than 5
            if ($pri >= $dna_pos and $pos < $dna_pos) {
                $pos = $dna_pos;
            }
            # Keep values greater than 4 greater than what was set
            elsif ($pri >= 4 and $pos < 4) {
                $pos = $pri;
            }
            else {
                $pos += $incr;
            }
        }
        else {
            $pos += $incr;
        }

        $method->right_priority($pos);
    }
}

sub create_full_gene_Methods {
    my( $self ) = @_;
    
    my $meth_list = $self->get_all_Methods;
    $self->flush_Methods;
    
    # Take the skeleton prefix methods out of the list
    my @prefix_methods;
    for (my $i = 0; $i < @$meth_list;) {
        my $meth = $meth_list->[$i];
        if ($meth->name =~ /^\w+:$/) {
            splice(@$meth_list, $i, 1);
            push(@prefix_methods, $meth);
        } else {
            $i++;
        }
    }
    
    my @mutable_methods;
    foreach my $method (@$meth_list) {
        # Skip existing _trunc methods - we will make new ones
        next if $method->name =~ /_trunc$/;
        
        $self->add_Method($method);
        if (my $type = $method->mutable) {
            # $method->column_group('Transcript');
            # Do not add non-transcript mutable methods because
            # we don't need prefixed or truncated versions of them.
            next unless $method->transcript_type;
            push(@mutable_methods, $method);
            $self->add_Method($self->make_trunc_Method($method));
        }
    }

    # Make copies of all the editable transcript methods for each prefix
    foreach my $prefix (@prefix_methods) {
        foreach my $method (@mutable_methods) {
            my $new = $method->clone;
            $new->mutable(0);
            $new->name($prefix->name . $method->name);
            # $new->column_group($prefix->name . 'Transcript');
            $new->color($prefix->color);
            if ($method->cds_color) {
                $new->cds_color($prefix->cds_color);
            }
            $self->add_Method($new);
            $self->add_Method($self->make_trunc_Method($new));
        }
    }
}

sub make_trunc_Method {
    my( $self, $method ) = @_;
    
    my $new = $method->clone;
    $new->name($method->name . '_trunc');
    $new->mutable(0);
    $new->color('GRAY');
    $new->cds_color('BLACK') if $method->cds_color;
    return $new;
}

1;

__END__

=head1 NAME - Hum::Ace::MethodCollection

Hard coded values in fMap:

        static FeatureMapColSettingsStruct defaultMapColumns[] =
        {
          /* all column position 100, -90 ... should be different */
        #define STL_STATUS_0
          {-100.0, TRUE, "Locator", fMapShowMiniSeq},
          {-90.0, TRUE, "Sequences & ends", fMapShowCanonical},

        #ifdef STL_STATUS  /* mike holman status column */
          {-89.0, TRUE, "Cosmids by group", fMapShowOrigin},
        #endif

          {-2.1, FALSE, "Up Gene Translation", fMapShowUpGeneTranslation},
          {-1.9,  TRUE, "-Confirmed introns", fMapShowSoloConfirmed},
          {-0.1,  TRUE, "Restriction map", fMapShowCptSites},

        #ifdef ACEMBLY
          /* Contig bar supersedes locator */
          {0.0, FALSE, "Summary bar", fMapShowSummary},
        #else
          {0.0,  TRUE, "Summary bar", fMapShowSummary},
        #endif

          {0.1,  TRUE, "Scale", fMapShowScale},
          {1.9,  TRUE, "Confirmed introns", fMapShowSoloConfirmed},
          {3.0,  TRUE, "EMBL features", fMapShowEmblFeatures},

        #ifdef STL_STATUS
          {3.1,  TRUE, "Cosmid Status", fMapShowStatus},
        #endif

          {3.2, FALSE, "CDS Lines", fMapShowCDSLines},
          {3.25, FALSE, "CDS Boxes", fMapShowCDSBoxes},
          {3.3,  TRUE, "Alleles", fMapShowAlleles},
          {3.4, FALSE, "cDNAs", fMapShowcDNAs},
          {3.5, FALSE, "Gene Names", fMapShowGeneNames},
          {3.7,  TRUE, "Assembly Tags", fMapShowAssemblyTags},
          {3.8, TRUE, "Oligos", fMapOspShowOligo},
          {3.82, TRUE, "Oligo_pairs", fMapOspShowOligoPairs},
        /* isFrame starts if either of next 2 are On */
          {4.0, FALSE, "3 Frame Translation", fMapShow3FrameTranslation},
          {4.05, FALSE, "ORF's", fMapShowORF},
          {4.1, TRUE, "Coding Frame", fMapShowCoding},	/* only shows if isFrame */
          {4.2, FALSE, "ATG", fMapShowATG},
        /* frame dependent stuff ends */
          /* {4.98, FALSE, "Gene Translation", fMapShowGeneTranslation}, */
          {4.99, FALSE, "Down Gene Translation", fMapShowDownGeneTranslation},

        #ifdef ACEMBLY
          {5.5,  TRUE, "Alignements", fMapShowAlignments},
          {5.6,  TRUE, "Previous Contigs", fMapShowPreviousContigs},
          {5.7,  TRUE, "Contigs", fMapShowContig},
          {5.8,  TRUE, "Trace Assembly", fMapShowTraceAssembly},
          {5.9,  TRUE, "Multiplets", fMapShowVirtualMultiplets},
        #endif

          {6.0, FALSE, "Coords", fMapShowCoords},
          {6.1, FALSE, "DNA Sequence", fMapShowDNA},

        #ifdef ACEMBLY
          {6.2, FALSE, "Assembly DNA", fMapShowVirtualDna},
        #endif

          {6.5, FALSE, "Brief Identifications", fMapShowBriefID},
          {7.0, TRUE, "Text Features", fMapShowText},
          {0.0, FALSE, NULL, NULL}

        } ;


=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

