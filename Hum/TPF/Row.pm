
### Hum::TPF::Row

package Hum::TPF::Row;

use strict;
use Carp;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub db_id {
    my( $self, $db_id ) = @_;
    
    if ($db_id) {
        $self->{'_db_id'} = $db_id;
    }
    return $self->{'_db_id'};
}



1;

__END__

=head1 NAME - Hum::TPF::Row

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

