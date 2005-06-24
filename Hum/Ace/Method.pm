
### Hum::Ace::Method

package Hum::Ace::Method;

use strict;
use Carp;
use Hum::Ace::Colors;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub new_from_AceText {
    my( $pkg, $txt ) = @_;
    
    my $self = $pkg->new;
    
    my ($n) = $txt->get_values('Method')
        or confess "Not a Method:\n$$txt";
    $self->name($n->[0] eq ':' ? $n->[1] : $n->[0]);
    
    if (my ($c) = $txt->get_values('Colour')) {
        $self->color($c->[0]);
    }
    if (my ($c) = $txt->get_values('CDS_Colour')) {
        $self->cds_color($c->[0]);
    }
    
    $self->show_up_strand(1)    if $txt->count_tag('Show_up_strand');
    $self->strand_sensitive(1)  if $txt->count_tag('Strand_sensitive');
    $self->frame_sensitive(1)   if $txt->count_tag('Frame_sensitive');
    $self->show_text(1)         if $txt->count_tag('Show_text');
    $self->percent(1)           if $txt->count_tag('Percent');
    $self->blastn(1)            if $txt->count_tag('BlastN');
    $self->gapped(1)            if $txt->count_tag('Gapped');
    $self->no_display(1)        if $txt->count_tag('No_display');

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
    
    # Single float values
    if (my ($n) = $txt->get_values('Group_number')) {
        $self->group_number($n->[0]);
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
    
    # Blixem types
    $self->blixem_type('N') if $txt->count_tag('Blixem_N');
    $self->blixem_type('X') if $txt->count_tag('Blixem_X');
    $self->blixem_type('P') if $txt->count_tag('Blixem_P');
    
    return $self;
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
    
    foreach my $tag (qw{
        Show_up_strand
        Strand_sensitive
        Frame_sensitive
        Show_text
        Percent
        BlastN
        Gapped
        No_display
        })
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
    
    foreach my $tag (qw{
        Group_number
        Right_priority
        Max_mag
        Min_mag
        Width
        })
    {
        my $tag_method = lc $tag;
        if (my $val = $self->$tag_method()) {
            $txt->add_tag($tag, $val);
        }
    }
    
    if (my $type = $self->blixem_type) {
        $txt->add_tag('Blixem_'. $type);
    }
    
    return $txt->ace_string;
}


sub new_from_ace_tag {
    my( $pkg, $tag ) = @_;
    
    my $self = $pkg->new;
    $self->process_ace_method($tag->fetch);
    return $self;
}

sub new_from_ace {
    my( $pkg, $ace ) = @_;
    
    my $self = $pkg->new;
    $self->process_ace_method($ace);
    return $self;
}

# Commented out because it is now very incomplete compared to new_from_AceText
#sub process_ace_method {
#    my( $self, $ace ) = @_;
#    
#    $self->name($ace->name);
#    my $color = $ace->at('Display.Colour[1]')
#        or confess "No color";
#    $self->color($color->name);
#    if (my $cds_color = $ace->at('Display.CDS_Colour[1]')) {
#        $self->cds_color($cds_color->name);
#    }
#}

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

sub group_number {
    my( $self, $group_number ) = @_;
    
    if ($group_number) {
        $self->{'_group_number'} = $group_number;
    }
    return $self->{'_group_number'};
}

sub right_priority {
    my( $self, $right_priority ) = @_;
    
    if ($right_priority) {
        $self->{'_right_priority'} = $right_priority;
    }
    return $self->{'_right_priority'};
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

sub width {
    my( $self, $width ) = @_;
    
    if ($width) {
        $self->{'_width'} = $width;
    }
    return $self->{'_width'};
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

# true/false methods

sub show_up_strand {
    my( $self, $show_up_strand ) = @_;
    
    if ($show_up_strand) {
        $self->{'_show_up_strand'} = $show_up_strand ? 1 : 0;
    }
    return $self->{'_show_up_strand'} || 0;
}

sub strand_sensitive {
    my( $self, $strand_sensitive ) = @_;
    
    if ($strand_sensitive) {
        $self->{'_strand_sensitive'} = $strand_sensitive ? 1 : 0;
    }
    return $self->{'_strand_sensitive'} || 0;
}

sub frame_sensitive {
    my( $self, $frame_sensitive ) = @_;
    
    if ($frame_sensitive) {
        $self->{'_frame_sensitive'} = $frame_sensitive ? 1 : 0;
    }
    return $self->{'_frame_sensitive'} || 0;
}

sub show_text {
    my( $self, $show_text ) = @_;
    
    if ($show_text) {
        $self->{'_show_text'} = $show_text ? 1 : 0;
    }
    return $self->{'_show_text'} || 0;
}

sub percent {
    my( $self, $percent ) = @_;
    
    if ($percent) {
        $self->{'_percent'} = $percent ? 1 : 0;
    }
    return $self->{'_percent'} || 0;
}

sub blastn {
    my( $self, $blastn ) = @_;
    
    if ($blastn) {
        $self->{'_blastn'} = $blastn ? 1 : 0;
    }
    return $self->{'_blastn'} || 0;
}

sub gapped {
    my( $self, $gapped ) = @_;
    
    if ($gapped) {
        $self->{'_gapped'} = $gapped ? 1 : 0;
    }
    return $self->{'_gapped'};
}

sub no_display {
    my( $self, $no_display ) = @_;
    
    if ($no_display) {
        $self->{'_no_display'} = $no_display ? 1 : 0;
    }
    return $self->{'_no_display'};
}

1;

__END__

=head1 NAME - Hum::Ace::Method

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

