
### Hum::Ace::MethodCollection

package Hum::Ace::MethodCollection;

use strict;
use warnings;
use Carp;

use Hum::Ace::Method;
use Hum::Ace::AceText;
use Hum::Sort qw{ ace_sort };

#use Graphics::ColorObject;

sub new {
    my ($pkg) = @_;

    return bless {}, $pkg;
}

sub new_from_string {
    my ($pkg, $str, $styles_collection) = @_;

    # warn "Collection:\n$str\n";

    my $self = $pkg->new;

    $self->ZMapStyleCollection($styles_collection);

    # Split text into paragraphs (which are separated by one or more blank lines).
    foreach my $para (split /\n{2,}/, $str) {

        # Create Method object from paragraphs that have
        # any lines that begin with a word character.
        if ($para =~ /^\w/m) {
            my $txt = Hum::Ace::AceText->new($para);
            my ($class, $name) = $txt->class_and_name;
            if ($class eq 'Method') {
                my $meth = Hum::Ace::Method->new_from_name_AceText($name, $txt);
                $self->add_Method($meth);
            }
            else {
                warn qq{Ignoring unknown class: $class : "$name" in:\n$para};
            }
        }
    }

    my $err = $self->link_Methods_to_ZMapStyles;
    $err .= $self->link_column_children;
    $err .= $self->check_all_leaf_Methods_have_ZMapStyles;
    confess $err if $err;

    return $self;
}

sub ace_string {
    my ($self) = @_;

    my $str = '';
    foreach my $meth (@{ $self->get_all_Methods }) {
        $str .= $meth->ace_string;
    }

    return $str;
}

sub new_from_file {
    my ($pkg, $file, $styles_collection) = @_;

    local $/ = undef;

    open my $fh, $file or die "Can't read '$file' : $!";
    my $str = <$fh>;
    close $fh or die "Error reading '$file' : $!";
    return $pkg->new_from_string($str, $styles_collection);
}

sub write_to_file {
    my ($self, $file) = @_;

    open my $fh, "> $file" or confess "Can't write to '$file' : $!";
    print $fh $self->ace_string;
    close $fh or confess "Error writing to '$file' : $!";
}

sub add_Method {
    my ($self, $method) = @_;

    if ($method) {
        my $name = $method->name
          or confess "Can't add un-named Method";
        if (my $existing = $self->{'_method_by_name'}{$name}) {
            confess "Already have Method called '$name':\n", $existing->ace_string;
        }
        my $lst = $self->get_all_Methods;
        push @$lst, $method;
        $self->{'_method_by_name'}{$name} = $method;

        # warn "Added Method '$name'\n";
    }
    else {
        confess "missing Hum::Ace::Method argument";
    }
}

sub add_ZMapStyle {
    my ($self, $style) = @_;

    if ($style) {
        my $name = $style->name
          or confess("Can't add un-named ZMapStyle");
        if (my $existing = $self->ZMapStyleCollection->get_style($name)) {
            confess "Already have ZMapStyle called '$name'";
        }
        else {
            $self->ZMapStyleCollection->add_style($style);
        }
    }
    else {
        confess "missing Hum::ZMapStyle argument";
    }
}

sub get_ZMapStyle {
    my ($self, $name) = @_;

    return $self->ZMapStyleCollection->get_style($name);
}

sub ZMapStyleCollection {
    my ($self, $zsc) = @_;
    $self->{_zsc} = $zsc if $zsc;
    return $self->{_zsc};
}

sub link_Methods_to_ZMapStyles {
    my ($self) = @_;

    my $err = '';
    foreach my $method (@{ $self->get_all_Methods }) {
        if (my $name = $method->style_name) {
            if (my $style = $self->get_ZMapStyle($name)) {
                $method->ZMapStyle($style);
            }
            else {
                $err .= sprintf qq{ZMapStyle '%s' in Method '%s' does not exist\n}, $name, $method->name;
            }
        }
    }
    return $err;
}

sub link_column_children {
    my ($self) = @_;

    my $err = '';
    my %parent_columns = map { $_->name, $_ } $self->get_all_top_level_Methods;
    foreach my $method (grep $_->column_parent, @{ $self->get_all_Methods }) {
        my $parent_name = $method->column_parent;
        if (my $parent = $parent_columns{$parent_name}) {
            $parent->add_child_Method($method);
        }
        else {
            $err .= qq{No top level Method called '$parent_name'\n};
        }
    }
    return $err;
}

sub check_all_leaf_Methods_have_ZMapStyles {
    my ($self) = @_;

    my $err = '';
    foreach my $method (@{ $self->get_all_Methods }) {
        next if $method->get_all_child_Methods;
        unless ($method->ZMapStyle) {
            $err .= sprintf qq{Method '%s' has no children and no ZMapStyle\n}, $method->name;
        }
    }
    return $err;
}

sub get_all_Methods {
    my ($self) = @_;

    my $lst = $self->{'_method_list'} ||= [];
    return $lst;
}

sub get_all_transcript_Methods {
    my ($self) = @_;

    return grep $_->is_transcript, @{ $self->get_all_Methods };
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
    }
    else {
        return;
    }
}

sub get_all_mutable_Methods {
    my ($self) = @_;

    return grep $_->mutable, @{ $self->get_all_Methods };
}

sub get_all_mutable_non_transcript_Methods {
    my ($self) = @_;

    return grep { $_->mutable and !$_->is_transcript } @{ $self->get_all_Methods };
}

sub get_all_top_level_Methods {
    my ($self) = @_;

    return grep !$_->column_parent, @{ $self->get_all_Methods };
}

sub get_Method_by_name {
    my ($self, $name) = @_;

    confess "Missing name argument" unless $name;

    return $self->{'_method_by_name'}{$name};
}

sub flush_Methods {
    my ($self) = @_;

    $self->{'_method_list'}    = [];
    $self->{'_method_by_name'} = {};
}

sub process_for_otterlace {
    my ($self) = @_;

    $self->create_full_gene_Methods;
}

sub create_full_gene_Methods {
    my ($self) = @_;

    my $meth_list = $self->get_all_Methods;
    $self->flush_Methods;

    # Take the skeleton prefix methods out of the list
    my @prefix_methods;
    for (my $i = 0; $i < @$meth_list;) {
        my $meth = $meth_list->[$i];
        if ($meth->name =~ /^\w+:$/) {
            splice(@$meth_list, $i, 1);
            push(@prefix_methods, $meth);
        }
        else {
            $i++;
        }
    }

    foreach my $method (@$meth_list) {

        # Skip any existing _trunc methods - we will make new ones
        next if $method->name =~ /_trunc$/;

        # add the method itself
        $self->add_Method($method);

        if ($method->is_transcript) {

            $self->add_mutable_GeneMethod($method) if $method->mutable;

            unless ($method->column_parent) {

                # we need to create a column parent to house both
                # the method and its truncated version
                my $parent = Hum::Ace::Method->new;
                $parent->name($method->name . '_parent');
                $self->add_Method($parent);
                $method->column_parent($parent->name);
            }

            # create a truncated method
            $self->add_Method($self->make_trunc_Method($method));
        }
    }

    # Make copies of all the editable transcript methods for each prefix
    foreach my $prefix (@prefix_methods) {
        foreach my $method ($self->get_all_mutable_GeneMethods) {
            my $new = $method->clone;
            $new->column_parent($prefix->column_parent);
            $new->name($prefix->name . $method->name);
            $new->ZMapStyle($prefix->ZMapStyle);
            $self->add_Method($new);
            $self->add_Method($self->make_trunc_Method($new));
        }
    }
}

sub make_trunc_Method {
    my ($self, $method) = @_;

    my $new_meth = $method->clone;
    $new_meth->name($method->name . '_trunc');
    my $style = $self->get_ZMapStyle($method->style_name);

    my $new_style = Hum::ZMapStyle->new;
    $new_style->name($style->name . '_trunc');
    $new_style->parent_style($style);
    $new_style->mode($style->mode);
    $new_style->collection($style->collection);

    ### Lighten colours

    #    for my $clr (qw{
    #        colours_normal_border
    #        colours_normal_fill
    #        cds_colour_normal_fill
    #        cds_colour_normal_border
    #    }) {
    #        my $new = $style->inherited($clr) || $style->$clr;
    #        eval {
    #            die "Colour '$new' not set" unless $new;
    #            $new = $self->lighten_color($new,0.6);
    #        };
    #        if ($@) {
    #            warn "Couldn't lighten colour: $@";
    #        }
    #
    #        $new_style->$clr($new);
    #    }

    ### Just use the old colours for all truncated transcripts for now

    $new_style->colours("normal fill LightGray ; normal border SlateGray");
    $new_style->transcript_cds_colours("normal fill WhiteSmoke ; normal border DarkSlateGray");

    $self->add_ZMapStyle($new_style) unless $self->get_ZMapStyle($new_style->name);

    $new_meth->ZMapStyle($new_style);

    return $new_meth;
}

#sub lighten_color {
#
#    my ($self, $color, $factor) = @_;
#
#    unless ($self->{_rgb_map}) {
#        my $rgb_txt_file;
#
#        for my $rgbf (qw{
#            /etc/X11/rgb.txt
#            /usr/X11R6/lib/X11/rgb.txt
#            /usr/X11/share/X11/rgb.txt
#        }) {
#            if (-e $rgbf) {
#                $rgb_txt_file = $rgbf;
#                last;
#            }
#        }
#
#        die "Can't find rgb.txt file\n" unless $rgb_txt_file;
#
#        open RGB_TXT, $rgb_txt_file or die "Can't read '$rgb_txt_file' : $!";
#
#        while (<RGB_TXT>) {
#            s/^\s+//;
#            chomp;
#            next if /^\!/;   # Skip comment lines
#            my ($r, $g, $b, $name) = split /\s+/, $_, 4;
#            $self->{_rgb_map}->{lc($name)} = [$r, $g, $b];
#        }
#
#        close RGB_TXT;
#    }
#
#    my $color_obj;
#
#    if ($color =~ /[0-9A-Fa-f]{6}/) {
#        $color_obj = Graphics::ColorObject->new_RGBhex($color);
#    }
#    elsif (my $rgb = $self->{_rgb_map}->{lc($color)}) {
#        $color_obj = Graphics::ColorObject->new_RGB255($rgb);
#    }
#    else {
#        die "Can't identify color: $color from rgb.txt";
#    }
#
#    my $lch = $color_obj->as_HSL;
#    $lch->[0] = $lch->[0] + ($factor * (1 - $lch->[0]));
#    $lch->[1] = $lch->[1] + ($factor * (1 - $lch->[1]));
#    $lch->[2] = $lch->[2] + ($factor * (1 - $lch->[2]));
#    return '#'.Graphics::ColorObject->new_HSL($lch)->as_RGBhex;
#}

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

