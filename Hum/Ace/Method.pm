
### Hum::Ace::Method

package Hum::Ace::Method;

use strict;
use warnings;
use Carp;
use Hum::Ace::Colors qw{ acename_to_webhex };

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

my @boolean_tags = qw{
    
    Has_parent
    Edit_score
    Edit_display_label
    Coding
    Allow_misalign
    
    };

sub new_from_name_AceText {
    my( $pkg, $name, $txt ) = @_;
    
    my $self = $pkg->new;
    $self->name($name);
    
    # True/false tags
    foreach my $tag (@boolean_tags) {
        my $method = lc $tag;
        if ($txt->count_tag($tag)) {
            $self->$method(1);
        }
    }
        
    # Methods with the same column_parent are put in the same column in the Zmap display
    if (my ($grp) = $txt->get_values('Column_parent')) {
        $self->column_parent($grp->[0]);
    }
    
    if (my ($name) = $txt->get_values('Style')) {
        $self->style_name($name->[0]);
    }
    
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
            column_parent
            valid_length
            remark
            style_name
            },
            @boolean_methods,
        ) {
            $new->$method($self->$method());
        }

        return $new;
    }
}

sub ace_string {
    my( $self ) = @_;
    
    my $name = $self->name;
    my $txt = Hum::Ace::AceText->new(qq{\nMethod : "$name"\n});
    
    if (my $group = $self->column_parent) {
        $txt->add_tag('Column_parent', $group);
    }
    
    if (my $sn = $self->style_name) {
        $txt->add_tag('Style', $sn);
    }

    foreach my $tag (@boolean_tags)
    {
        my $tag_method = lc $tag;
        $txt->add_tag($tag) if $self->$tag_method();
    }
        
    foreach my $tag (qw{
        Valid_length
        Remark
        })
    {
        my $tag_method = lc $tag;
        if (defined (my $val = $self->$tag_method())) {
            $txt->add_tag($tag, $val);
        }
    }
    
    # A bit messy, but thank's to the sgifacesever's GFF
    # dumping mechanism, it depends on these tags being
    # present in the Method object to trigger the score
    # being reported for Homols and Features
    if (my $style = $self->ZMapStyle) {
        my $min_score = $style->min_score;
        my $max_score = $style->max_score;
        if (defined($min_score) && defined($max_score)) {
            $txt->add_tag('Score_bounds', ($min_score, $max_score));
        }
        if (my $score_mode = $style->score_mode) {
            $txt->add_tag('Score_by_width') if $score_mode eq 'width';
            $txt->add_tag('Percent')        if $score_mode eq 'percent';
        }
        if (my $mode = $style->mode) {
            if ($mode eq 'Graph') {
                $txt->add_tag('Score_by_histogram');
            }
            
            if ($mode eq 'alignment') {
                if ($style->alignment_parse_gaps) {
                    $txt->add_tag('Map_gaps');
                    $txt->add_tag('Export_coords');
                }
            }
        }
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

sub column_parent {
    my( $self, $column_parent ) = @_;
    
    if ($column_parent) {
        $self->{'_column_parent'} = $column_parent;
    }
    return $self->{'_column_parent'} || '';
}

sub get_all_child_Methods {
    my ($self) = @_;
    
    if (my $chld = $self->{'_column_children'}) {
        return @$chld;
    } else {
        return;
    }
}

sub add_child_Method {
    my ($self, $method) = @_;
    
    my $chld = $self->{'_column_children'} ||= [];
    push(@$chld, $method);
}

sub style_name {
    my $self = shift;
    
    if (@_) {
        my $style_name = shift;
        $self->{'_style_name'} = $style_name;
    }
    if (my $style = $self->ZMapStyle) {
        my $name = $style->name
            or confess "Anonymous ZMapStyle object attached to Method";
        return $name;
    } else {
        return $self->{'_style_name'};
    }
}

sub ZMapStyle {
    my( $self, $ZMapStyle ) = @_;
    
    if ($ZMapStyle) {
        $self->{'_ZMapStyle'} = $ZMapStyle;
        $self->style_name(undef);
    }
    return $self->{'_ZMapStyle'};
}

sub is_transcript {
    my ($self) = @_;
    
    if (my $style = $self->ZMapStyle) {
        return $style->mode && $style->mode eq 'transcript';
    } else {
        return 0;
    }
}

sub remark {
    my( $self, $remark ) = @_;
    
    if ($remark) {
        $self->{'_remark'} = $remark;
    }
    return $self->{'_remark'};
}

sub mutable {
    my( $self ) = @_;
    
    # True if the attached Style is or descends from a "curated_*" style
    if (my $style = $self->ZMapStyle) {
        return $style->is_mutable;
    } else {
        return 0;
    }
}

sub coding {
    my( $self, $coding ) = @_;
    
    if ($coding) {
        $self->{'_coding'} = $coding;
    }
    return $self->{'_coding'};
}

# Controls nesting of transcript sub-types in TranscriptWindow menu
sub has_parent {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_has_parent'} = $flag ? 1 : 0;
    }
    return $self->{'_has_parent'};
}

# Next three methods are used by GenomicFeatures window

sub valid_length {
    my( $self, $valid_length ) = @_;
    
    if ($valid_length) {
        $self->{'_valid_length'} = $valid_length;
    }
    return $self->{'_valid_length'};
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

sub allow_misalign {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_allow_misalign'} = $flag ? 1 : 0;
    }
    return $self->{'_allow_misalign'};
}

1;

__END__

=head1 NAME - Hum::Ace::Method

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

