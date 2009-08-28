
### Hum::TPF::Row

package Hum::TPF::Row;

use strict;
use warnings;
use Carp;
use Hum::Tracking 'prepare_cached_track_statement';

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

sub remark {
    my( $self, $remark ) = @_;
    
    if ($remark) {
        $self->{'_remark'} = $remark;
    }
    return $self->{'_remark'};
}
 

# This is overridden in TPF::Row::Gap
sub is_gap { return 0; }

sub get_next_id_tpfrow {
    my( $self ) = @_;
    
    my $sth = prepare_cached_track_statement(q{SELECT tpfr_seq.nextval FROM dual});
    $sth->execute;
    my ($id) = $sth->fetchrow;
    $sth->finish;
    $self->db_id($id);
}

1;

__END__

=head1 NAME - Hum::TPF::Row

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

