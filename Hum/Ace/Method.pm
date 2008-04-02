
### Hum::Ace::Method

package Hum::Ace::Method;

use strict;
use Carp;
use Hum::Ace::Colors qw{ acename_to_webhex };

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

my @boolean_tags = qw{

    Show_up_strand
    Strand_sensitive
    Frame_sensitive
    Show_only_as_3_frame
    Show_text
    Percent
    BlastN
    Outline
    Right_priority_fixed
    No_display
    Built_in
    
    Mutable
    Has_parent
    Edit_score
    Edit_display_label
    
    Init_hidden
    
    };

sub new_from_AceText {
    my( $pkg, $txt ) = @_;
    
    my $self = $pkg->new;
    
    my ($n) = $txt->get_values('Method')
        or confess "Not a Method:\n$$txt";
    # Is there a colon between "Method" and the name?
    $self->name($n->[0] eq ':' ? $n->[1] : $n->[0]);
    
    # Display colours
    if (my ($c) = $txt->get_values('Colour')) {
        $self->color($c->[0]);
    }
    if (my ($c) = $txt->get_values('CDS_Colour')) {
        $self->cds_color($c->[0]);
    }
    
    # True/false tags
    foreach my $tag (@boolean_tags) {
        my $method = lc $tag;
        if ($txt->count_tag($tag)) {
            $self->$method(1);
        }
    }
    
    # Coding or non-coding transcript methods
    $self->transcript_type('coding')     if $txt->count_tag('Coding');
    $self->transcript_type('non_coding') if $txt->count_tag('Non_coding');
    $self->transcript_type('transcript') if $txt->count_tag('Transcript');

    # Score method
    $self->score_method('width')     if $txt->count_tag('Score_by_width');
    $self->score_method('offset')    if $txt->count_tag('Score_by_offset');
    $self->score_method('histogram') if $txt->count_tag('Score_by_histogram');
    
    if (my ($s) = $txt->get_values('Score_bounds')) {
        $self->score_bounds(@$s[0,1]);
    }

    # Overlap mode
    $self->overlap_mode('overlap')  if $txt->count_tag('Overlap');
    $self->overlap_mode('bumpable') if $txt->count_tag('Bumpable');
    $self->overlap_mode('cluster')  if $txt->count_tag('Cluster');
    
    # Zmap display mode
    foreach my $mode (qw{
        text
        graph
        basic
        alignment
        transcript
        allele
        graph
        })
    {
        my $tag = "Zmap_mode_$mode";
        if ($txt->count_tag($tag)) {
            $self->zmap_mode($mode);
            last;
        }
    }
    
    # Methods with the same column_group get the same right_priority
    if (my ($grp) = $txt->get_values('Column_group')) {
        $self->column_group(       $grp->[0]);
        $self->column_group_method($grp->[1]);
    }
    
    # Single float values
    if (my ($n) = $txt->get_values('Zone_number')) {
        $self->zone_number($n->[0]);
    }
    if (my ($off) = $txt->get_values('Right_priority')) {
        $self->right_priority($off->[0]);
    }
    if (my ($off) = $txt->get_values('Max_mag')) {
        $self->max_mag($off->[0]);
    }
    if (my ($off) = $txt->get_values('Min_mag')) {
        $self->min_mag($off->[0]);
    }
    if (my ($w) = $txt->get_values('Width')) {
        $self->width($w->[0]);
    }
    if (my ($g) = $txt->get_values('Gapped')) {
        $self->gapped($g->[0] || 0);
    }
    if (my ($j) = $txt->get_values('Join_aligns')) {
        $self->join_aligns($j->[0] || 0);
    }
    
    # Blixem types
    $self->blixem_type('N') if $txt->count_tag('Blixem_N');
    $self->blixem_type('X') if $txt->count_tag('Blixem_X');
    $self->blixem_type('P') if $txt->count_tag('Blixem_P');
    
    # Correct length for feature
    if (my ($len) = $txt->get_values('Valid_length')) {
        $self->valid_length($len->[0]);
    }
    
    # Remarks, which are used to display a little more information
    # than the name alone in parts of otterlace and zmap.
    if (my ($rem) = $txt->get_values('Remark')) {
        $self->remark($rem->[0]);
    }
    
    return $self;
}

{
    my @boolean_methods = map lc, @boolean_tags;

    sub clone {
        my( $self ) = @_;

        my $new = ref($self)->new;

        foreach my $method (qw{
            name
            color
            cds_color
            column_group
            column_group_method
            zone_number
            right_priority
            max_mag
            min_mag
            width
            score_bounds
            score_method
            blixem_type
            overlap_mode
            transcript_type
            valid_length
            gapped
            join_aligns
            zmap_mode
            remark
            }
        ) {
            $new->$method($self->$method());
        }

        foreach my $method (@boolean_methods) {
            $new->$method($self->$method());
        }

        return $new;
    }
}


sub zmap_style_string {
    my ($self) = @_;
    
    my $name = $self->name;
    my $txt = Hum::Ace::AceText->new(qq{\nZmap_Style : "$name"\n});

    # We must have a Zmap mode
    my $mode = $self->zmap_mode;
    unless ($mode) {
        if ($self->transcript_type) {
            $mode = 'transcript';
        }
        elsif (defined $self->join_aligns) {
            # Is this the best way to spot Alignment columns?
            $mode = 'alignment';
        }
        else {
            $mode = 'basic';
        }
    }
    $mode = 'plain_text' if $mode eq 'text';
    $txt->add_tag(ucfirst $mode);
    # Connect style to base style
    $txt->add_tag('Parent', ucfirst $mode . '_Base');

    my $fill_or_border = $mode eq 'transcript' ? 'Border' : 'Fill';
    if (my $c = $self->color) {
        $txt->add_tag(qw{Colours Normal }, $fill_or_border, acename_to_webhex(uc $c));
    }
    if (my $c = $self->cds_color) {
        #$txt->add_tag(qw{Transcript CDS_colour Normal }, $fill_or_border, acename_to_webhex(uc $c));
        $txt->add_tag(qw{Transcript CDS_colour Normal }, 'Fill', acename_to_webhex(uc $c));
    }
    
    # Have not dealt with the following boolean methods:
    #  Show_text
    #  BlastN
    #  Has_parent

    #  Edit_score
    #  Edit_display_label
    #
    #  Init_hidden

    # Boolean methods:
    foreach my $tag (qw{
        Show_up_strand
        Strand_sensitive
        Frame_sensitive
        Show_only_as_3_frame
        })
    {
        my $tag_method = lc $tag;
        $txt->add_tag($tag) if $self->$tag_method();
    }
    
    $txt->add_tag('Score_percent') if $self->percent;

    if ($self->no_display) {
        $txt->add_tag(qw{Hide Always});
    }
    elsif ($self->init_hidden) {
        $txt->add_tag(qw{Hide Initially});
    }
    
    if (my $meth = $self->score_method) {
        if ($meth eq 'width') {
            $txt->add_tag('Score_by_width');
        }
        elsif ($meth eq 'histogram') {
            $txt->add_tag(qw{Graph Mode Histogram});
        }
        else {
            warn "score / display method '$meth' not supported by Zmap";
        }
    }
    
    if (my @bounds = $self->score_bounds) {
        $txt->add_tag('Score_bounds', @bounds);
    }
    
    # Overlap methods.
    my $over = $self->overlap_mode || 'overlap';
    if ($over ne 'overlap') {
        $txt->add_tag(qw{ Bump_mode Overlap_mode Ends_range });
    }
    else {
        $txt->add_tag(qw{ Bump_mode Overlap_mode Overlap });
    }
    
    if (my $width = $self->width) {
        $txt->add_tag('Width', 5 * $width);
    }
    
    ### Might need to add "Valid_length" to Zmap_styles in future.
    ### It is used by GenomicFeatures window to validate length
    ### of some feature types eg: PolyA signals and sites.
    foreach my $tag (qw{
        Max_mag
        Min_mag
        Remark
        })
    {
        my $tag_method = lc $tag;
        if (defined (my $val = $self->$tag_method())) {
            $txt->add_tag($tag, $val);
        }
    }
    
    if (defined (my $n = $self->join_aligns)) {
        $txt->add_tag(qw{ Alignment Gapped External }, $n);
    }
    
    if (defined (my $n = $self->gapped)) {
        $txt->add_tag(qw{ Alignment Gapped Internal }, $n);
    }
    
    if (my $group = $self->column_group) {
        $txt->add_tag('Column_group', $group, $self->column_group_method);
    }
    
    return $txt->ace_string;
}

sub ace_string {
    my( $self ) = @_;
    
    my $name = $self->name;
    my $txt = Hum::Ace::AceText->new(qq{\nMethod : "$name"\n});

    if (my $c = $self->color) {
        $txt->add_tag('Colour', $c)
    }
    if (my $c = $self->cds_color) {
        $txt->add_tag('CDS_Colour', $c);
    }
    
    foreach my $tag (@boolean_tags)
    {
        my $tag_method = lc $tag;
        $txt->add_tag($tag) if $self->$tag_method();
    }
    
    if (my $meth = $self->score_method) {
        $txt->add_tag('Score_by_'. $meth);
    }
    
    if (my @bounds = $self->score_bounds) {
        $txt->add_tag('Score_bounds', @bounds);
    }
    
    if (my $over = $self->overlap_mode) {
        $txt->add_tag(ucfirst $over);
    }
    
    if (my $mode = $self->zmap_mode) {
        $txt->add_tag("Zmap_mode_$mode");
    }
    
    if (my $type = $self->transcript_type) {
        $txt->add_tag(ucfirst $type);
    }
    
    foreach my $tag (qw{
        Zone_number
        Right_priority
        Max_mag
        Min_mag
        Width
        Valid_length
        Gapped
        Join_aligns
        Remark
        })
    {
        my $tag_method = lc $tag;
        if (defined (my $val = $self->$tag_method())) {
            $txt->add_tag($tag, $val);
        }
    }
    
    if (my $group = $self->column_group) {
        $txt->add_tag('Column_group', $group, $self->column_group_method);
    }
    
    if (my $type = $self->blixem_type) {
        $txt->add_tag('Blixem_'. $type);
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

sub color {
    my( $self, $color ) = @_;
    
    if ($color) {
        $self->{'_color'} = $color;
    }
    return $self->{'_color'};
}

sub cds_color {
    my( $self, $cds_color ) = @_;
    
    if ($cds_color) {
        $self->{'_cds_color'} = $cds_color;
    }
    return $self->{'_cds_color'};
}

sub column_group {
    my( $self, $column_group ) = @_;
    
    if ($column_group) {
        $self->{'_column_group'} = $column_group;
    }
    return $self->{'_column_group'} || '';
}

sub column_group_method {
    my( $self, $column_group_method ) = @_;
    
    if ($column_group_method) {
        $self->{'_column_group_method'} = $column_group_method;
    }
    # The Method on the end of the column group line
    # defaults to the name of the method.
    return $self->{'_column_group_method'} || $self->name;
}

sub zone_number {
    my( $self, $zone_number ) = @_;
    
    if (defined $zone_number) {
        $self->{'_zone_number'} = $zone_number;
    }
    return $self->{'_zone_number'};
}

sub right_priority {
    my( $self, $right_priority ) = @_;
    
    if (defined $right_priority) {
        $self->{'_right_priority'} = sprintf "%.3f", $right_priority;
    }
    return $self->{'_right_priority'};
}

sub max_mag {
    my( $self, $max_mag ) = @_;
    
    if (defined $max_mag) {
        $self->{'_max_mag'} = $max_mag;
    }
    return $self->{'_max_mag'};
}

sub min_mag {
    my( $self, $min_mag ) = @_;
    
    if (defined $min_mag) {
        $self->{'_min_mag'} = $min_mag;
    }
    return $self->{'_min_mag'};
}

sub width {
    my( $self, $width ) = @_;
    
    if (defined $width) {
        $self->{'_width'} = $width;
    }
    return $self->{'_width'} || 2;
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

sub valid_length {
    my( $self, $valid_length ) = @_;
    
    if ($valid_length) {
        $self->{'_valid_length'} = $valid_length;
    }
    return $self->{'_valid_length'};
}

sub gapped {
    my( $self, $gapped ) = @_;
    
    if (defined $gapped) {
        $self->{'_gapped'} = $gapped;
    }
    return $self->{'_gapped'};
}

sub join_aligns {
    my( $self, $join_aligns ) = @_;
    
    if (defined $join_aligns) {
        $self->{'_join_aligns'} = $join_aligns;
    }
    return $self->{'_join_aligns'};
}

sub remark {
    my( $self, $remark ) = @_;
    
    if ($remark) {
        $self->{'_remark'} = $remark;
    }
    return $self->{'_remark'};
}

sub hex_color {
    my( $self ) = @_;
    
    my $color = $self->color;
    return Hum::Ace::Colors::acename_to_webhex($color);
}

sub hex_cds_color {
    my( $self ) = @_;
    
    my $color = $self->cds_color;
    return Hum::Ace::Colors::acename_to_webhex($color);
}


# enum methods

sub score_method {
    my( $self, $score_method ) = @_;
    
    if ($score_method) {
        if ($score_method ne 'width' and
            $score_method ne 'offset' and
            $score_method ne 'histogram'
        ) {
            confess "Unrecognized score method '$score_method'";
        }
        $self->{'_score_method'} = $score_method;
    }
    return $self->{'_score_method'};
}

sub blixem_type {
    my( $self, $blixem_type ) = @_;
    
    if ($blixem_type) {
        if ($blixem_type ne 'N' and
            $blixem_type ne 'X' and
            $blixem_type ne 'P'
        ) {
            confess "Unrecognized blixem type '$blixem_type'";
        }
        $self->{'_blixem_type'} = $blixem_type;
    }
    return $self->{'_blixem_type'};
}

sub overlap_mode {
    my( $self, $overlap_mode ) = @_;
    
    if ($overlap_mode) {
        if ($overlap_mode ne 'overlap' and
            $overlap_mode ne 'bumpable' and
            $overlap_mode ne 'cluster'
        ) {
            confess "Unrecognized overlap mode '$overlap_mode'";
        }
        $self->{'_overlap_mode'} = $overlap_mode;
    }
    return $self->{'_overlap_mode'};
}

sub zmap_mode {
    my( $self, $zmap_mode ) = @_;
    
    if ($zmap_mode) {
        if ($zmap_mode ne 'text'        and
            $zmap_mode ne 'graph'       and
            $zmap_mode ne 'basic'       and
            $zmap_mode ne 'alignment'   and
            $zmap_mode ne 'transcript'  and
            $zmap_mode ne 'allele'
        ) {
            confess "Unrecognized zmap mode '$zmap_mode'";
        }
        $self->{'_zmap_mode'} = $zmap_mode;
    }
    return $self->{'_zmap_mode'};
}


sub transcript_type {
    my( $self, $transcript_type ) = @_;
    
    if ($transcript_type) {
        if ($transcript_type ne 'coding' and
            $transcript_type ne 'non_coding' and
            $transcript_type ne 'transcript'
        ) {
            confess "Unrecognized transcript type '$transcript_type'";
        }
        $self->{'_transcript_type'} = $transcript_type;
    }
    return $self->{'_transcript_type'};
}


# True / false methods:

sub show_up_strand {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_show_up_strand'} = $flag ? 1 : 0;
    }
    return $self->{'_show_up_strand'};
}

sub strand_sensitive {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_strand_sensitive'} = $flag ? 1 : 0;
    }
    return $self->{'_strand_sensitive'};
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

sub show_text {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_show_text'} = $flag ? 1 : 0;
    }
    return $self->{'_show_text'};
}

sub percent {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_percent'} = $flag ? 1 : 0;
    }
    return $self->{'_percent'};
}

sub blastn {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_blastn'} = $flag ? 1 : 0;
    }
    return $self->{'_blastn'};
}

sub outline {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_outline'} = $flag ? 1 : 0;
    }
    return $self->{'_outline'};
}

sub right_priority_fixed {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_right_priority_fixed'} = $flag ? 1 : 0;
    }
    return $self->{'_right_priority_fixed'};
}

sub no_display {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_no_display'} = $flag ? 1 : 0;
    }
    return $self->{'_no_display'};
}

sub built_in {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_built_in'} = $flag ? 1 : 0;
    }
    return $self->{'_built_in'};
}

sub mutable {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_mutable'} = $flag ? 1 : 0;
    }
    return $self->{'_mutable'};
}

sub has_parent {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_has_parent'} = $flag ? 1 : 0;
    }
    return $self->{'_has_parent'};
}

sub init_hidden {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_init_hidden'} = $flag ? 1 : 0;
    }
    return $self->{'_init_hidden'};
}

sub edit_score {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_edit_score'} = $flag ? 1 : 0;
    }
    return $self->{'_edit_score'};
}

sub edit_display_label {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_edit_display_label'} = $flag ? 1 : 0;
    }
    return $self->{'_edit_display_label'};
}

1;

__END__

=head1 NAME - Hum::Ace::Method

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

