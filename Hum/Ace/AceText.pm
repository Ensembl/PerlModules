
### Hum::Ace::ParseText

package Hum::Ace::ParseText;

use strict;
use 5.6.0;  # Needed for qr support
use Carp;
use Text::ParseWords 'quotewords';

sub new {
    my( $pkg, $txt ) = @_;

    $txt =~ s/\s+$/\n/s;
    return bless \$txt, $pkg;
}

sub ace_string {
    my( $self ) = @_;
    
    return $$self;
}


#sub ace_class_and_name {
#    my( $self ) = @_;
#    
#    my ($class, $name) = $self =~ /^(\w+)\s+:\s+"?([^"]+)/m
#        or confess qq{Can\'t see 'Class : "name"' specifier};
#    return $class, $name;
#}
#sub ace_class {
#    my( $self ) = @_;
#    
#    my ($class) = $self->class_and_name;
#    return $class;
#}
#
#sub name {
#    my( $self ) = @_;
#    
#    my ($name) = ($self->class_and_name)[1];
#    return $name;
#}


sub get_values {
    my( $self, $tag_path ) = @_;
    
    my ($pat, $offset) = _make_pattern_and_offset($tag_path);
    
    my( @matches );
    while ($$self =~ /$pat/img) {
        my @ele = quotewords('\s+', 0, $1);
        #warn join('  ', map "<$_>", @ele), "\n";
        push(@matches, [@ele[$offset .. $#ele]]);
    }
    return @matches;
}

sub count_tag {
    my( $self, $tag_path ) = @_;
    
    my ($pat) = _make_pattern_and_offset($tag_path);
    my $count = 0;
    while ($$self =~ /$pat/img) {
        $count++;
    }
    return $count;
}

sub delete_tag {
    my( $self, $tag_path ) = @_;
    
    my ($pat) = _make_pattern_and_offset($tag_path);
    $$self =~ s/$pat\n//img;
}

sub add_tag_values {
    my( $self, @tag_val ) = @_;
    
    foreach my $tv (@tag_val) {
        $$self .= _quoted_ace_line($tv);
    }
}

sub _quoted_ace_line {
    my( $tv ) = @_;
    
    # This may look a bit odd, but it is emulating
    # acedb's behaviour as exactly as possible!
    my $str = $tv->[0] . "\t";
    
    for (my $i = 1; $i < @$tv; $i++) {
        $_ = $tv->[$i];
        
        ## Don't quote elements which are numbers or just ':'
        #unless (/^[\.\d]+$/ or /^:$/) {

        # Don't quote elements which are numbers
        unless (/^[\.\d]+$/) {

	    # Escape quotes, back and forward slashes,
	    # percent signs, and semi-colons.
	    s/([\/"%;\\])/\\$1/g;

	    # Escape newlines and tabs
	    s/\n/\\n/g;
	    s/\n/\\t/g;

	    # Quote if tag unless it is entirely word characters
            unless (/^\w+$/) {
	        $_ = "\"$_\"";
	    }
        }
        
        $str .= " " . $_;
    }
    $str .= "\n";
    
    return $str;
}

{
    my %pattern_cache;

    sub _make_pattern_and_offset {
        my( $tag_path ) = @_;
        
        my $offset = 1;
        
        my( $pat );
        unless ($pat = $pattern_cache{$tag_path}) {
            $offset += $tag_path =~ s/\./\\s+/g;
            #warn "Tag path = '$tag_path'\n";
            $pat = $pattern_cache{$tag_path} = [qr/^($tag_path\b.*)/, $offset];
        }
        
        return @$pat
    }
}

1;

__END__

=head1 NAME - Hum::Ace::ParseText

=head1 SYNOPSIS

    # Make new object
    my $txt = Hum::Ace::ParseText->new($ace_string);

    # Get Source_Exons coordinates
    foreach my $coord ($txt->get_values('Source_Exons')) {
        print "coord = (@$coord)\n";
    }

    # Get description, which is 2 tags deep in ace file
    foreach my $desc ($txt->get_values('EMBL_dump_info.DE_line')) {
        print "desc = 'desc'\n";
    }

    # Count how many EST matches are recorded
    print "There are ", $txt->count_tag('EST_match'), " est matches\n";


=head1 DESCRIPTION

B<Hum::Ace::ParseText> parses the values for
given tags from a piece of acedb formatted text. 
It avoids having to write a bunch of regular
expressions every time you need to do this.

=head1 METHODS

=over 4

=item new

Creates a new B<Hum::Ace::ParseText> object.  It
takes a single mandatory argument, a string of
.ace formatted text.  (See SYNOPSIS above.)

=item get_values

Given the name of a tag, returns a (possibly
empty) list of array refs, each of which is the
list of values found to the right of the tag.

Where there are #Model inclues in the acedb
model, which causes two tags to occur in a row in
the .ace file, you can give multiple tags
separated by a dot.  (See the
'EMBL_dump_info.DE_line' example in SYNOPSIS.)

=item count_tag

Counts the number of times the given tag occurs
in the ace text.

=item delete_tag

Deletes all occurences of the tag from the text.

=item add_tag_values

    $txt->add_tag_values(
        ['Source_Exons', 1, 134],
        ['Source_Exons', 2005, 2471],
        );

Takes a list of array refs and adds each array to
the text, correctly quoting it for acedb.  The
first element of each array is taken to be the
name of the tag.

=item ace_string

Returns the ParseText object as ace file
formatted text.

=back

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

