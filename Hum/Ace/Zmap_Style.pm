
### Hum::Ace::Zmap_Style

package Hum::Ace::Zmap_Style;

use strict;
use Carp;
use Hum::Ace::AceText;
use warnings;

my %colour_tags;
foreach my $clr_str (qw{
    Colours.Normal.Border
    Colours.Normal.Fill
    Colours.Selected.Border
    Colours.Selected.Fill
    })
{
    my $meth = lc $clr_str;
    $meth =~ s/\./_/g;
    my $clr_print = $clr_str;
    $clr_print =~ s/\./\t/g;
    $colour_tags{$clr_str} = [$meth, $clr_print];
}

my @boolean_tags = qw{
    Show_when_empty
    Directional_ends
    Strand_sensitive
    Show_up_strand
    Score_by_width
    Score_percent
    Frame_sensitive
    Show_only_as_3_frame
    Show_only_as_1_column
    Bump_fixed
};

my @value_tags = qw{
    Remark
    Description
    Width
    Max_mag
    Min_mag
    Bump_spacing
};

### Column state
### Frame colours

sub new {
    my ($pkg) = @_;
    
    return bless {}, $pkg;
}

sub new_from_name_AceText {
    my( $pkg, $name, $txt ) = @_;
    
    my $self = $pkg->new;
    $self->name($name);
    
    if (my ($parent) = $txt->get_values('Style_parent')) {
        $self->parent_name($parent->[0]);
    }
    
    # Parse colours
    foreach my $tag (keys %colour_tags) {
        if (my ($clr) = $txt->get_values($tag)) {
            my $meth = $colour_tags{$tag}->[0];
            $self->$meth($clr->[0]);
        }
    }
    
    # Parse bump mode
    if (my ($over) = $txt->get_values('Bump_initial.Bump_mode')) {
        $self->bump_initial($over->[0]);
    }
    if (my ($over) = $txt->get_values('Bump_default.Bump_mode')) {
        $self->bump_default($over->[0]);
    }
    
    # Zmap mode (Transcript, Alignment etc...)
    $self->parse_zmap_mode($txt);
    
    # Tags with single values
    foreach my $tag (@value_tags) {
        my $meth = lc $tag;
        if (my ($val) = $txt->get_values($tag)) {
            $self->$meth($val->[0]);
        }
    }
    
    # True/false tags
    foreach my $tag (@boolean_tags) {
        my $method = lc $tag;
        if ($txt->count_tag($tag)) {
            $self->$method(1);
        }
    }

    if (my ($s) = $txt->get_values('Score_bounds')) {
        $self->score_bounds(@$s[0,1]);
    }

    foreach my $tag (qw{ Hide Show_hide Show }) {
        if ($txt->count_tag($tag)) {
            $self->column_state($tag);
        }
    }

    # # Overlap mode
    # $self->overlap_mode('overlap')  if $txt->count_tag('Overlap');
    # $self->overlap_mode('bumpable') if $txt->count_tag('Bumpable');
    # $self->overlap_mode('cluster')  if $txt->count_tag('Cluster');
    # 
    # if (my ($g) = $txt->get_values('Gapped')) {
    #     $self->gapped($g->[0] || 0);
    # }
    # if (my ($j) = $txt->get_values('Join_aligns')) {
    #     $self->join_aligns($j->[0] || 0);
    # }
    # 
    # # Blixem types
    # $self->blixem_type('N') if $txt->count_tag('Blixem_N');
    # $self->blixem_type('X') if $txt->count_tag('Blixem_X');
    # $self->blixem_type('P') if $txt->count_tag('Blixem_P');
    # 
    # if (my ($rem) = $txt->get_values('Remark')) {
    #     $self->remark($rem->[0]);
    # }

    return $self;
}

{
    my @zmap_mode = qw{
        Basic
        Transcript
        Alignment
        Sequence
        Peptide
        Plain_Text
        Graph
        Glyph
        };

    sub parse_zmap_mode {
        my ($self, $txt) = @_;
        
        my ($found_mode, $mode_data);
        foreach my $mode (@zmap_mode) {
            my @data = $txt->get_values($mode);
            next unless @data;
            if ($found_mode) {
                confess sprintf "Zmap_Style '%s' cannot have both '%s' and '%s' Zmap modes\n",
                    $self->name, $found_mode, $mode;
            } else {
                $found_mode = $mode;
                $mode_data = [@data];
            }
        }
        if ($found_mode) {
            # use Data::Dumper;
            # printf STDERR "Mode of Zmap_Style '%s' is '%s' with data:\n%s",
            #     $self->name, $found_mode, Dumper($mode_data);
            $self->mode($found_mode);
            $self->mode_data($mode_data);
        }
    }
}

sub bump_initial {
    my( $self, $bump_initial ) = @_;
    
    if ($bump_initial) {
        $self->{'_bump_initial'} = $bump_initial;
    }
    return $self->{'_bump_initial'};
}

sub bump_default {
    my( $self, $bump_default ) = @_;
    
    if ($bump_default) {
        $self->{'_bump_default'} = $bump_default;
    }
    return $self->{'_bump_default'};
}


sub ace_string {
    my ($self) = @_;
    
    # use Data::Dumper;
    # print STDERR Dumper($self);
    
    my $name = $self->name or confess "Zmap_Style has no name\n";
    my $txt = Hum::Ace::AceText->new(qq{\nZmap_Style : "$name"\n});
    
    if (my $pn = $self->parent_name) {
        $txt->add_tag('Style_parent', $pn);
    }
    
    foreach my $meth_tagstr (sort {$a->[0] cmp $b->[0]} values %colour_tags) {
        my ($meth, $tag_str) = @$meth_tagstr;
        if (my $clr = $self->$meth()) {
            $txt->add_tag($tag_str, $clr);
        }
    }
    
    if (my $mode = $self->mode) {
        foreach my $md (@{$self->mode_data}) {
            $txt->add_tag($mode, @$md);
        }
    }
    
    foreach my $tag (@boolean_tags) {
        my $meth = lc $tag;
        $txt->add_tag($tag) if $self->$meth();
    }
    
    foreach my $tag (@value_tags) {
        my $meth = lc $tag;
        if (my $val = $self->$meth()) {
            $txt->add_tag($tag, $val);
        }
    }
    
    if (my @bounds = $self->score_bounds) {
        $txt->add_tag('Score_bounds', @bounds);
    }
    
    if (my $state = $self->column_state) {
        $txt->add_tag($state);
    }
    
    if (my $mode = $self->bump_initial) {
        $txt->add_tag(qw{ Bump_initial Bump_mode }, $mode);
    }
    if (my $mode = $self->bump_default) {
        $txt->add_tag(qw{ Bump_default Bump_mode }, $mode);
    }
    
    return $txt->ace_string;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub parent_name {
    my $self = shift;
    
    if (@_) {
        $self->{'_parent_name'} = shift;
    }
    if (my $parent = $self->parent_Style) {
        my $name = $parent->name
            or confess "Anonymous parent Zmap_Style attached";
        return $name;
    } else {
        return $self->{'_parent_name'};
    }
}

sub parent_Style {
    my( $self, $parent_Style ) = @_;
    
    if ($parent_Style) {
        $self->{'_parent_Style'} = $parent_Style;
        $self->parent_name(undef);
    }
    return $self->{'_parent_Style'};
}

sub mode {
    my( $self, $mode ) = @_;
    
    if ($mode) {
        $self->{'_mode'} = $mode;
    }
    return $self->{'_mode'};
}

sub inherited_mode {
    my ($self) = @_;

    if (my $mode = $self->mode) {
        return $mode;
    }
    elsif (my $style = $self->parent_Style) {
        return $style->inherited_mode;
    }
    else {
        return '';
    }
}

sub inherited {
    my ($self, $method) = @_;
    
    return wantarray ? $self->_inherited_list($method) : $self->_inherited_scalar($method);
}

sub _inherited_scalar {
    my ($self, $method) = @_;
    
    # warn "Returning '$method' in scalar context\n";
    
    if (defined(my $val = $self->$method())) {
        return $val
    }
    elsif (my $style = $self->parent_Style) {
        return $style->_inherited_scalar($method);
    }
    else {
        return;
    }
}

sub _inherited_list {
    my ($self, $method) = @_;
    
    # warn "Returning '$method' in list context\n";
    
    if (my @val = $self->$method()) {
        return @val
    }
    elsif (my $style = $self->parent_Style) {
        return $style->_inherited_list($method);
    }
    else {
        return;
    }
}


sub mode_data {
    my ($self, $mode_data) = @_;
    
    if ($mode_data) {
        $self->{'_mode_data'} = $mode_data;
    }
    return $self->{'_mode_data'};
}

sub get_mode_data {
    my ($self, $tag_path) = @_;
    
    # collect all the mode data from the style hierarchy
    
    my $all_mode_data = $self->mode_data ? [@{$self->mode_data}] : [];
    
    my $style = $self;
    
    while ($style = $style->parent_Style) {
        if (my $mode_data = $style->mode_data) {
            push @{ $all_mode_data }, @{ $mode_data };
        }
    }
  
    return unless $all_mode_data;
    
    # now see if there are any matches
    
    my @matches;
    
    DATA: foreach my $data (@$all_mode_data) {
        for (my $i = 0; $i < @$tag_path; $i++) {
            next DATA if $data->[$i] ne $tag_path->[$i];
        }
        push(@matches, $data);
    }
    
    return @matches;
}

sub create_mode_data {
    my ($self, @tag_path) = @_;
    
    my $data_list = $self->mode_data || $self->mode_data([]);
    my $data = [@tag_path];
    push(@$data_list, $data);
    return $data;
}

sub get_set_mode_data {
    my ($self, $value, @tag_path) = @_;
    
    my $i = @tag_path;
    my ($clr_data) = $self->get_mode_data([@tag_path]);
    if ($value) {
        confess "Mode not set" unless $self->inherited_mode;
        my $clr_data = $self->create_mode_data(@tag_path);
        $clr_data->[$i] = $value;
    }
    return $clr_data ? $clr_data->[$i] : undef;
}

sub is_mutable {
    my ($self) = @_;
    
    if ($self->name =~ /^curated/) {
        return 1;
    }
    elsif (my $style = $self->parent_Style) {
        return $style->is_mutable;
    }
    else {
        return 0;
    }
}

sub score_bounds {
    my( $self, @bounds ) = @_;
    
    if (@bounds) {
        unless (@bounds == 2) {
            confess "Need two arguments for score bounds; args: (",
                join(", ", map "'$_'", @bounds), ")";
        }
        $self->{'_score_bounds'} = [@bounds];
    }
    if (my $sb = $self->{'_score_bounds'}) {
        return @$sb;
    } else {
        return;
    }
}

# Colour methods

# Four methods for normal and selected colour of fill and border of features

sub colours_normal_border {
    my( $self, $colours_normal_border ) = @_;
    
    if ($colours_normal_border) {
        $self->{'_colours_normal_border'} = $colours_normal_border;
    }
    return $self->{'_colours_normal_border'};
}

sub colours_normal_fill {
    my( $self, $colours_normal_fill ) = @_;
    
    if ($colours_normal_fill) {
        $self->{'_colours_normal_fill'} = $colours_normal_fill;
    }
    return $self->{'_colours_normal_fill'};
}

sub colours_selected_border {
    my( $self, $colours_selected_border ) = @_;
    
    if ($colours_selected_border) {
        $self->{'_colours_selected_border'} = $colours_selected_border;
    }
    return $self->{'_colours_selected_border'};
}

sub colours_selected_fill {
    my( $self, $colours_selected_fill ) = @_;
    
    if ($colours_selected_fill) {
        $self->{'_colours_selected_fill'} = $colours_selected_fill;
    }
    return $self->{'_colours_selected_fill'};
}


# Four methods for normal and selected colour of fill and border of transcript CDS regions

sub cds_colour_normal_border {
    my( $self, $colour ) = @_;
    
    return $self->get_set_mode_data($colour, qw{ CDS_Colour Normal Border });
}

sub cds_colour_normal_fill {
    my( $self, $colour ) = @_;
    
    return $self->get_set_mode_data($colour, qw{ CDS_Colour Normal Fill });
}

sub cds_colour_selected_border {
    my( $self, $colour ) = @_;
    
    return $self->get_set_mode_data($colour, qw{ CDS_Colour Selected Border });
}

sub cds_colour_selected_fill {
    my( $self, $colour ) = @_;
    
    return $self->get_set_mode_data($colour, qw{ CDS_Colour Selected Fill });
}



# Boolean methods

sub show_when_empty {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_show_when_empty'} = $flag ? 1 : 0;
    }
    return $self->{'_show_when_empty'};
}

sub directional_ends {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_directional_ends'} = $flag ? 1 : 0;
    }
    return $self->{'_directional_ends'};
}

sub strand_sensitive {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_strand_sensitive'} = $flag ? 1 : 0;
    }
    return $self->{'_strand_sensitive'};
}

sub show_up_strand {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_show_up_strand'} = $flag ? 1 : 0;
    }
    return $self->{'_show_up_strand'};
}

sub score_by_width {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_score_by_width'} = $flag ? 1 : 0;
    }
    return $self->{'_score_by_width'};
}

sub score_percent {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_score_percent'} = $flag ? 1 : 0;
    }
    return $self->{'_score_percent'};
}

sub frame_sensitive {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_frame_sensitive'} = $flag ? 1 : 0;
    }
    return $self->{'_frame_sensitive'};
}

sub show_only_as_3_frame {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_show_only_as_3_frame'} = $flag ? 1 : 0;
    }
    return $self->{'_show_only_as_3_frame'};
}

sub show_only_as_1_column {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_show_only_as_1_column'} = $flag ? 1 : 0;
    }
    return $self->{'_show_only_as_1_column'};
}

sub bump_fixed {
    my( $self, $bump_fixed ) = @_;
    
    if ($bump_fixed) {
        $self->{'_bump_fixed'} = $bump_fixed;
    }
    return $self->{'_bump_fixed'};
}


# Value methods

sub remark {
    my( $self, $remark ) = @_;
    
    if ($remark) {
        $self->{'_remark'} = $remark;
    }
    return $self->{'_remark'};
}

sub description {
    my( $self, $description ) = @_;
    
    if ($description) {
        $self->{'_description'} = $description;
    }
    return $self->{'_description'};
}

sub width {
    my( $self, $width ) = @_;
    
    if ($width) {
        $self->{'_width'} = $width;
    }
    return $self->{'_width'};
}

sub max_mag {
    my( $self, $max_mag ) = @_;
    
    if ($max_mag) {
        $self->{'_max_mag'} = $max_mag;
    }
    return $self->{'_max_mag'};
}

sub min_mag {
    my( $self, $min_mag ) = @_;
    
    if ($min_mag) {
        $self->{'_min_mag'} = $min_mag;
    }
    return $self->{'_min_mag'};
}

sub bump_spacing {
    my( $self, $bump_spacing ) = @_;
    
    if ($bump_spacing) {
        $self->{'_bump_spacing'} = $bump_spacing;
    }
    return $self->{'_bump_spacing'};
}

sub column_state {
    my( $self, $column_state ) = @_;
    
    if ($column_state) {
        $self->{'_column_state'} = $column_state;
    }
    return $self->{'_column_state'};
}



1;

__END__

=head1 NAME - Hum::Ace::Zmap_Style

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

