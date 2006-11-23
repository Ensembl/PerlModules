
### Hum::Ace::SeqFeature::Simple

package Hum::Ace::SeqFeature::Simple;

use strict;
use base 'Hum::Ace::SeqFeature';


sub Method {
    my( $self, $Method ) = @_;
    
    if ($Method) {
        $self->{'_Method'} = $Method;
    }
    return $self->{'_Method'};
}


1;

__END__

=head1 NAME - Hum::Ace::SeqFeature::Simple

=head1 DESCRIPTION

Subclass of C<Hum::Ace::SeqFeature> used to
represent simple features edited in otterlace,
such as polyA signals and sites.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

