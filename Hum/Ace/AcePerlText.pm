
### Hum::Ace::AcePerlText

package Hum::Ace::AcePerlText;

use strict;
use Carp;
use Ace;
use Hum::Ace::AceText;

###  I could not get inheritance from Ace to work due
###  to problems with AutoLoader.  So I just inject
###  this code into the Ace package:

package Ace;


sub AceText_from_tag {
    my( $self, $tag ) = @_;
    
    my $str = $self->raw_query("show -a $tag");
    return Hum::Ace::AceText->new($str);
}

sub values_from_tag {
    my ($self, $tag) = @_;
    
    my $text = $self->AceText_from_tag($tag);
    return $text->get_values($tag);
}

sub count_from_tag {
    my ($self, $tag) = @_;
    
    my $text = $self->AceText_from_tag($tag);
    return $text->count_tag($tag);
}


1;

__END__

=head1 NAME - Hum::Ace::AcePerlText

=head1 DESCRIPTION

Extends Lincoln's AcePerl C<Ace> base class to
provide methods that query tags using
C<Hum::Ace::AceText> objects. This greatly speeds
up fetching tags from very large acedb objects.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

