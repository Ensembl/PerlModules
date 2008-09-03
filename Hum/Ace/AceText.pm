
### Hum::Ace::AceText

package Hum::Ace::AceText;

use strict;
use 5.006_001;  # Perl 5.6.1 is needed for qr support
use Carp;
use Text::ParseWords 'quotewords';

sub new {
    my( $pkg, $txt ) = @_;

    $txt = '' unless defined $txt;

    # Trim trailing empty lines so that it
    # is safe to add data onto the end.
    $txt =~ s/\s+$/\n/s;
    
    # Remove pesky nulls
    $txt =~ s/\0//g;
    
    return bless \$txt, $pkg;
}

sub ace_string {
    my( $self ) = @_;
    
    return $$self;
}

sub get_values {
    my( $self, $tag_path ) = @_;
    
    my ($pat, $offset) = _make_pattern_and_offset($tag_path);
    
    my( @matches );
    while ($$self =~ /$pat/g) {
        my @ele = quotewords('\s+', 0, $1);
        #warn join('  ', map "<$_>", @ele), "\n";
        push(@matches, [@ele[$offset .. $#ele]]);
    }
    return @matches;
}

### Not used - not as quick as get_values due to the checks it
### does, but is nicer to use.
#sub get_unique_value {
#    my $self = shift;
#    
#    my @matches = $self->get_values(@_);
#    if (@matches > 1) {
#        confess 'Got ', scalar(@matches), ' matches, not 1. Is tag "UNIQUE"?';
#    }
#    elsif (@matches == 1) {
#        if (@{$matches[0]} == 1) {
#            return $matches[0][0];
#        } else {
#            confess "match is not a simple value:\n",
#                join(', ', map "'$_'", @{$matches[0]});
#        }
#    }
#    else {
#        return;
#    }
#}

sub count_tag {
    my( $self, $tag_path ) = @_;
    
    my ($pat) = _make_pattern_and_offset($tag_path);
    my $count = 0;
    while ($$self =~ /$pat/g) {
        $count++;
    }
    return $count;
}

sub delete_tag {
    my( $self, $tag_path ) = @_;
    
    my ($pat) = _make_pattern_and_offset($tag_path);
    $$self =~ s/$pat\n//g;
}

sub add_tag_values {
    my( $self, @tag_val ) = @_;
    
    foreach my $tv (@tag_val) {
        $$self .= _quoted_ace_line($tv);
    }
}

sub add_tag {
    my $self = shift;
    
    $$self .= _quoted_ace_line(\@_);
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

        # Don't quote elements which are numbers or just ':'
        unless (/^[\+\-]?[\.\d]+$/ or $_ eq ':') {

	        # Escape quotes, back and forward slashes,
	        # percent signs, and semi-colons.
	        s/([\/"%;\\])/\\$1/g;

	        # Escape newlines and tabs
	        s/\n/\\n/g;
	        s/\t/\\t/g;

	        # Quote tag unless it is entirely word characters
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
            confess "tag path '$tag_path' ends with non-word character"
                if $tag_path =~ /\W$/;
            $offset += $tag_path =~ s/\./\\s+/g;
            #warn "Tag path = '$tag_path'\n";
            $pat = $pattern_cache{$tag_path} = [qr/^($tag_path\b.*?)\s*$/im, $offset];
        }
        
        return @$pat
    }
}

1;

__END__

=head1 NAME - Hum::Ace::AceText

=head1 SYNOPSIS

    # Make new object
    my $txt = Hum::Ace::AceText->new($ace_string);

    # Get Source_Exons coordinates
    foreach my $coord ($txt->get_values('Source_Exons')) {
        print "coord = (@$coord)\n";
    }

    # Get description, which is 2 tags deep in ace file
    foreach my $desc ($txt->get_values('EMBL_dump_info.DE_line')) {
        print "desc = '$desc->[0]'\n";
    }

    # Get the accession - which can only have a unique value
    my $acc = $txt->get_single_value('Accession');

    # Count how many EST matches are recorded
    print "There are ", $txt->count_tag('EST_match'), " est matches\n";

    # Get values under a data tag.  (The double quote is
    # qualified by a '?' in case the tag is not quoted).
    foreach my $val ($txt->get_values('Feature."?NonGolden')) {
        my ($start, $end) = @$val;
    }

=head1 DESCRIPTION

B<Hum::Ace::AceText> parses the values for
given tags from a piece of acedb formatted text. 
It avoids having to write a bunch of regular
expressions every time you need to do this.

=head1 METHODS

=over 4

=item new

Creates a new B<Hum::Ace::AceText> object.  It
takes a single mandatory argument which is a
string of .ace formatted text.  (See SYNOPSIS
above.)

=item get_values

Given the name of a tag, returns a (possibly
empty) list of array refs, each of which is the
list of values found to the right of the tag.

Where there are #Model inclues in the acedb
model, which causes two tags to occur in a row in
the .ace file, you can give multiple tags
separated by a dot.  (See the
'EMBL_dump_info.DE_line' example in SYNOPSIS.)

=item get_single_value

Given the name of a tag, returns a string which
is the value under that tag. This will only work
where there is a single UNIQUE value under the
tag.

Returns C<undef> if the tag is absent or empty.
Throws an exception if there is more than one
match.

=item count_tag

Counts the number of times the given tag occurs
in the ace text.

=item delete_tag

Deletes all occurences of the given tag (and its
values) from the text.

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

Returns the B<AceText> object as an ace file
formatted string.

=back

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

