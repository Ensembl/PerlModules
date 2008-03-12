
### Hum::XmlWriter

package Hum::XmlWriter;

use strict;
use Carp;


sub xml_escape {
    my $str = shift;

    # Must do ampersand first!
    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/"/&quot;/g;
    $str =~ s/'/&apos;/g;
    return $str;
}


my (%indent, %level, %open_tag, %string);

sub DESTROY {
    my ($self) = @_;
    
    # Could check here for tags left open or xml string un-flushed.

    delete $indent{$self};
    delete $level{$self};
    delete $open_tag{$self};
    delete $string{$self};
}

sub new {
    my ($pkg, $x) = @_;
    
    my $scalar;
    my $self = bless \$scalar, $pkg;
    $indent{$self} = $x || 2;
    $level{$self} = 0;
    $open_tag{$self} = [];
    return $self;
}

sub add_data {
    my ($self, $data) = @_;
    
    $string{$self} .= $data;
}

sub flush {
    my ($self) = @_;
    
    # Could check that we don't have open tags, but might be
    # too restrictive; we might want to send a large quantity
    # of data down a filehandle and close the tags later.
    return delete $string{$self};
}

sub open_tag {
    my ($self, $name, $attr) = @_;
    
    my $tag_str = $self->_begin_tag($name, $attr). qq{\n};
    push @{$open_tag{$self}}, $name;
    $string{$self} .= $tag_str;
    $level{$self} += $indent{$self};
}

sub close_tag {
    my ($self) = @_;
    
    my $name = pop @{$open_tag{$self}} or confess "No tag to close";
    $level{$self} -= $indent{$self};
    $string{$self} .= ' ' x $level{$self} . qq{</$name>\n};
}

sub close_all_open_tags {
    my ($self) = @_;
    
    while (@{$open_tag{$self}}) {
        $self->close_tag;
    }
}

sub full_tag {
    my ($self, $name, $attr, $data) = @_;

    $string{$self} .= $self->_begin_tag($name, $attr)
        . xml_escape($data)
        . qq{</$name>\n};
}

sub _begin_tag {
    my ($self, $name, $attr) = @_;
    
    my $tag_str = ' ' x $level{$self} . qq{<$name};
    if ($attr) {
        while (my ($attrib, $value) = each %$attr) {
            #$tag_str .= qq{ $attrib="} . xml_escape($value) . qq{"};
            $tag_str .= qq{ $attrib="$value"};
        }
    }
    $tag_str .= '>';
    return $tag_str;
}

1;

__END__

=head1 NAME - Hum::XmlWriter

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

