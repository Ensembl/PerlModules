
### Hum::Ace::AcePerlText

package Hum::Ace::AcePerlText;

use strict;
use warnings;
use Carp;
#use base 'Ace';
use Ace;
use Hum::Ace::AceText;

###  I could not get inheritance from Ace to work due
###  to problems with AutoLoader.  It can't find the
###  *.al files for each method because it is looking
###  for them in the "auto/Hum/Ace/AcePerlText" directory
###  instead of "auto/Ace".
###  So I just inject this code into the Ace package:

package Ace;


sub AceText_from_tag {
    my( $self, $tag ) = @_;
    
    my $str = $self->raw_query("show -a $tag");
    #warn "show -a $tag = <$str>";
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

