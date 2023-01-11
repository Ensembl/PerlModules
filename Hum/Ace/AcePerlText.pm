=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


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

