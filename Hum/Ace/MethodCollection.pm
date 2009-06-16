
### Hum::Ace::MethodCollection

package Hum::Ace::MethodCollection;

use strict;
use Carp;

use Hum::Ace::Method;
use Hum::Ace::Zmap_Style;
use Hum::Ace::AceText;
use Hum::Sort qw{ ace_sort };

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub new_from_string {
    my( $pkg, $str ) = @_;
    
    # warn "Collection:\n$str\n";
    
    my $self = $pkg->new;

    # Split text into paragraphs (which are separated by one or more blank lines).
    foreach my $para (split /\n{2,}/, $str) {
        # Create Method object from paragraphs that have
        # any lines that begin with a word character.
        if ($para =~ /^\w/m) {
            my $txt  = Hum::Ace::AceText->new($para);
            my ($class, $name) = $txt->class_and_name;
            if ($class eq 'Method') {
                my $meth = Hum::Ace::Method->new_from_name_AceText($name, $txt);
                $self->add_Method($meth);                
            }
            elsif ($class eq 'Zmap_Style') {
                my $style = Hum::Ace::Zmap_Style->new_from_name_AceText($name, $txt);
                $self->add_Zmap_Style($style);
            }
            else {
                warn qq{Ignoring unknown class: $class : "$name" in:\n$para};
            }
        }
    }
    
    my $err = $self->link_Zmap_Styles;
    $err .= $self->link_Methods_to_Zmap_Styles;
    $err .= $self->link_column_children;
    $err .= $self->check_all_leaf_Methods_have_Zmap_Styles;
    confess $err if $err;
    
    return $self;
}

# # This isn't useful, because the methods are sorted by name, and
# # the mutable GeneMethods don't get populated.
# sub new_from_ace_handle {
#     my ($pkg, $ace) = @_;
#     
#     $ace->raw_query('find Method *');
#     my $str = $ace->raw_query('show -a');
#     $ace->raw_query('find Zmap_Style *');
#     $str .= $ace->raw_query('show -a');
#     
#     # Using the AceText object strips out any server comments and nulls
#     my $meths = Hum::Ace::AceText->new($str);
#     return $pkg->new_from_string($meths->ace_string);
# }


sub ace_string {
    my( $self ) = @_;
    
    my $z_styles = $self->get_Zmap_Styles_hash;
    my %got_z_style;
    
    my $str = '';
    foreach my $meth (@{$self->get_all_Methods}) {
        $str .= $meth->ace_string;
        if (my $style_name = $meth->style_name) {
            if (my $style = delete $z_styles->{$style_name}) {
                $str .= $style->ace_string;
                $got_z_style{$style_name} = 1;
            }
            elsif (! $got_z_style{$style_name}) {
                confess "Method refers to non-existant Zmap_Style '$style_name':\n",
                    $meth->ace_string;
            }
        }
    }
    
    foreach my $style (sort { ace_sort($a->name, $b->name) } values %$z_styles) {
        $str .= $style->ace_string;
    }
    
    return $str;
}

sub new_from_file {
    my( $pkg, $file ) = @_;
    
    local $/ = undef;
    
    open my $fh, $file or die "Can't read '$file' : $!";
    my $str = <$fh>;
    close $fh or die "Error reading '$file' : $!";
    return $pkg->new_from_string($str);
}

sub write_to_file {
    my( $self, $file ) = @_;
    
    open my $fh, "> $file" or confess "Can't write to '$file' : $!";
    print $fh $self->ace_string;
    close $fh or confess "Error writing to '$file' : $!";
}

sub add_Method {
    my( $self, $method ) = @_;
    
    if ($method) {
        my $name = $method->name
            or confess "Can't add un-named Method";
        if (my $existing = $self->{'_method_by_name'}{$name}) {
            confess "Already have Method called '$name':\n",
                $existing->ace_string;
        }
        my $lst = $self->get_all_Methods;
        push @$lst, $method;
        $self->{'_method_by_name'}{$name} = $method;
        # warn "Added Method '$name'\n";
    } else {
        confess "missing Hum::Ace::Method argument";
    }
}

sub add_Zmap_Style {
    my ($self, $style) = @_;
    
    if ($style) {
        my $name = $style->name
            or confess ("Can't add un-name Zmap_Style");
        if (my $exisiting = $self->{'_zmap_style'}{$name}) {
            confess "Already have Zmap_Style called '$name':\n",
                $exisiting->ace_string;
        } else {
            $self->{'_zmap_style'}{$name} = $style;
        }
    } else {
        confess "missing Hum::Ace::Zmap_Style argument";
    }
}

sub get_Zmap_Style {
    my ($self, $name) = @_;
    
    return $self->{'_zmap_style'}{$name};
}

sub get_Zmap_Styles_hash {
    my ($self) = @_;
    
    my $zsh = $self->{'_zmap_style'} ||= {};

    # Return a ref to a copy of the hash
    return {%$zsh};
}

sub link_Zmap_Styles {
    my ($self) = @_;
    
    my $zsh = $self->get_Zmap_Styles_hash;
    my $err = '';
    foreach my $style (values %$zsh) {
        my $name = $style->parent_name or next;
        if (my $parent = $zsh->{$name}) {
            # printf STDERR "Adding style parent '%s' to Zmap_Style '%s'\n",
            #     $parent->name, $style->name;
            $style->parent_Style($parent);
        } else {
            $err .= sprintf qq{Style_parent '%s' of Zmap_Style '%s' does not exist\n},
                $name, $style->name;
        }
    }
    return $err;
}

sub link_Methods_to_Zmap_Styles {
    my ($self) = @_;
    
    my $err = '';
    foreach my $method (@{$self->get_all_Methods}) {
        if (my $name = $method->style_name) {
            if (my $style = $self->get_Zmap_Style($name)) {
                # printf STDERR "Adding Zmap_Style object '%s' to Method '%s'\n",
                #     $style->name, $method->name;
                $method->Zmap_Style($style);
            } else {
                $err .= sprintf qq{Zmap_Style '%s' in Method '%s' does not exist\n},
                    $name, $method->name;
            }
        }
    }
    return $err;
}

sub link_column_children {
    my ($self) = @_;
    
    my $err = '';
    my %parent_columns = map {$_->name, $_} $self->get_all_top_level_Methods;
    foreach my $method (grep $_->column_parent, @{$self->get_all_Methods}) {
        my $parent_name = $method->column_parent;
        if (my $parent = $parent_columns{$parent_name}) {
            $parent->add_child_Method($method);
        } else {
            $err .= qq{No top level Method called '$parent_name'\n};
        }
    }
    return $err;
}

sub check_all_leaf_Methods_have_Zmap_Styles {
    my ($self) = @_;
    
    my $err = '';
    foreach my $method (@{$self->get_all_Methods}) {
        next if $method->get_all_child_Methods;
        unless ($method->Zmap_Style) {
            $err .= sprintf qq{Method '%s' has no children and no Zmap_Style\n}, $method->name;
        }
    }
    return $err;
}

sub get_all_Methods {
    my( $self ) = @_;
    
    my $lst = $self->{'_method_list'} ||= [];
    return $lst;
}

sub get_all_transcript_Methods {
    my ($self) = @_;
    
    return grep $_->is_transcript, @{$self->get_all_Methods};
}

sub add_mutable_GeneMethod {
    my ($self, $method) = @_;
    
    my $core = $self->{'_core_transcript_meths'} ||= [];
    push @$core, $method;
}

sub get_all_mutable_GeneMethods {
    my ($self) = @_;
    
    if (my $core = $self->{'_core_transcript_meths'}) {
        return @$core;
    } else {
        return;
    }
}

sub get_all_mutable_Methods {
    my ($self) = @_;
    
    return grep $_->mutable, @{$self->get_all_Methods};
}

sub get_all_mutable_non_transcript_Methods {
    my ($self) = @_;
    
    return grep {$_->mutable and ! $_->is_transcript} @{$self->get_all_Methods};
}

sub get_all_top_level_Methods {
    my ($self) = @_;
    
    return grep ! $_->column_parent, @{$self->get_all_Methods};
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
    
    foreach my $method (@$meth_list) {
        # Skip any existing _trunc methods - we will make new ones
        next if $method->name =~ /_trunc$/;
        
        $self->add_Method($method);

        if ($method->mutable) {
            # Do not add non-transcript mutable methods because
            # we don't need prefixed or truncated versions of them.
            if ($method->is_transcript) {
                $self->add_mutable_GeneMethod($method);
                $self->add_Method($self->make_trunc_Method($method));
                next;
            }
        }
    }

    # Make copies of all the editable transcript methods for each prefix
    foreach my $prefix (@prefix_methods) {
        foreach my $method ($self->get_all_mutable_GeneMethods) {
            my $new = $method->clone;
            $new->column_parent($prefix->column_parent);
            $new->name($prefix->name . $method->name);
            $new->Zmap_Style($prefix->Zmap_Style);
            $self->add_Method($new);
            $self->add_Method($self->make_trunc_Method($new));
        }
    }
}

sub make_trunc_Method {
    my( $self, $method ) = @_;
    
    my $new = $method->clone;
    $new->name($method->name . '_trunc');
    my $style = $self->get_Zmap_Style('truncated_tsct');
    $new->Zmap_Style($style);
    ### Dullen colours
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

