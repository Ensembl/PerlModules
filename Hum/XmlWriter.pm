
### Hum::XmlWriter

package Hum::XmlWriter;

use strict;
use warnings;
use Carp;


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

    $indent{$self} = 2;
    $level{$self} = $x || 0;
    $open_tag{$self} = [];

    return $self;
}

sub add_XML {
    my ($self, $xml) = @_;
    
    $xml->close_all_open_tags;
    
    ### Add indent to XML string?
    
    $string{$self} .= $xml->flush;
}

sub add_data {
    my ($self, $data) = @_;
    $string{$self} .= $self->xml_escape($data);
}

sub add_data_with_indent {
    my ($self, $data) = @_;
    $self->add_data($self->_indent_text($data));
}

sub add_raw_data {
    my ($self, $data) = @_;
     
    $string{$self} .= $data;
}

sub add_raw_data_with_indent {
    my ($self, $data) = @_;
    $self->add_raw_data($self->_indent_text($data));
}

sub _indent_text {
    my ($self, $data) = @_;
    my $ind = ' ' x $level{$self};
    $data =~ s/(.+)(\n|$)/$ind$1\n/g;
    return $data;
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

    if (defined $data) {
        $string{$self} .= $self->_begin_tag($name, $attr)
            . $self->xml_escape($data)
            . qq{</$name>\n};
    } else {
        $string{$self} .= ' ' x $level{$self} . qq{<$name}
          . $self->_format_attribs($attr)
          . qq{ />\n};
    }
}

sub _begin_tag {
    my ($self, $name, $attr) = @_;
    
    my $tag_str = ' ' x $level{$self} . qq{<$name};
    if ($attr) {
        $tag_str .= $self->_format_attribs($attr);
    }
    $tag_str .= '>';
    return $tag_str;
}

sub _format_attribs {
    my ($self, $attr) = @_;
    
    my $tag_str = '';
    while (my ($attrib, $value) = each %$attr) {
        $tag_str .= qq{ $attrib="} . $self->xml_escape($value) . qq{"};
    }
    return $tag_str;
}

sub flush {
    my ($self) = @_;
    
    # Could check that we don't have open tags, but might be
    # too restrictive; we might want to send a large quantity
    # of data down a filehandle and close the tags later.
    return delete $string{$self};
}

sub xml_escape {
    my ($self, $str) = @_;

    # Must do ampersand first!
    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/"/&quot;/g;
    $str =~ s/'/&apos;/g;
    return $str;
}

1;

__END__

=head1 NAME - Hum::XmlWriter

=head1 DESCRIPTION

Module for formatting data into nicely indented and correctly escaped XML.
Tags opened with the C<open_tag> method increase the indentation, and the tag
name is pused onto a stack where the C<close_tag> method can use it.

Attribute values and data have their XML special characters replaced by XML
entities. For example C<&> will become C<&amp;>.

=head1 METHODS

=over 4

=item new

  my $xml = Hum::XmlWriter->new($integer);

Creates a new XmlWriter object. Optional argument is the number of spaces to
use per indentation level. Default is B<2>.

=item open_tag

  $xml->open_tag($tag_name, $attrib_hash);

For example:

  $xml->open_tag('gene', {type => 'coding'});

will add the string:

  <gene type="coding">

to the XmlWriter object, prefixed by the appropriate number of spaces for the
current indentation level, and followed by a newline.

=item add_data

  $xml->add_data($string);

Repleaces any XML special characters (ampersands, greater and less than,
single and double quotes) with entities in the string argument, then appends
it to the XmlWriter object.

=item add_raw_data

  $xml->add_raw_data($string);

Appends the string argument to the XmlWriter object without escaping any
of the XML special characters.

=item close_tag

  $xml->close_tag;

Closes the current open tag and adds a newline. Takes no arguments - opened
tags are remembered on a stack.

=item full_tag

  $xml->full_tag($tag_name, $attrib_hash, $data);

Puts a complete xml tag on one line. Adds the opening and closing tags,
attributes and values, and any data given in the third argument between the
tags, followed by a newline. For example, this code:

  $xml->full_tag('tagvalue', {name => 'Remark', type => 'external'},
    'Short teminal exon');

will add this string, with a trailing newline, to the XmlWriter:

  <tagvalue name="Remark" type="external">Short terminal exon</tagvalue>

=item close_all_open_tags

  $xml->close_all_open_tags;

The XmlWriter object keeps a stack of opened tags, so it can automatically
close all the opening tags for you.

=item flush

  my $xml_string = $xml->flush;

Deletes the XML string from the XmlWriter object and returns it. The XmlWriter
object will still contain open tags you have not yet closed, so you can format
more data and call C<flush> again. This behaviour is useful if, for example,
you are generating very large XML documents and streaming them from a server.

=back

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

