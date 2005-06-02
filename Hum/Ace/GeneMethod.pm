
### Hum::Ace::GeneMethod

package Hum::Ace::GeneMethod;

use strict;
use Carp;
use Hum::Ace::Colors;

use base 'Hum::Ace::Method';

sub is_mutable {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        my $value = $self->{'_is_mutable'};
        if (defined $value) {
            confess "attempt to change read-only property";
        } else {
            $self->{'_is_mutable'} = $flag ? 1 : 0;
        }
    }
    return $self->{'_is_mutable'};
}

sub is_coding {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_is_coding'} = $flag ? 1 : 0;
    } else {
        if (defined($flag = $self->{'_is_coding'})) {
            return $flag;
        } else {
            return $self->name =~ /(pseudo|mrna)/i ? 0 : 1;
        }
    }
}

sub has_parent{
    my ($self , $flag) = @_ ;
    if (defined $flag){
        $self->{'_has_parent'} = $flag ;
    }
    return  $self->{'_has_parent'};
    
}

1;

__END__

=head1 NAME - Hum::Ace::GeneMethod

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

