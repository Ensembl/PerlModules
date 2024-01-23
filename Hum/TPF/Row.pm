=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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

