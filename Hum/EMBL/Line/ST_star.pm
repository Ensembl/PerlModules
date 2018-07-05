=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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


### Hum::EMBL::Line::ST_star (it was Hum::EMBL::Line::HD_star)
### ERROR: HD line not allowed with the new ID line, use the ST line instead

package Hum::EMBL::Line::ST_star;

use strict;
use warnings;
use Carp;
use Hum::EMBL::Line;
use Hum::EMBL::Utils qw( EMBLdate dateEMBL );
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::ST_star->makeFieldAccessFuncs(qw( hold_date ));

sub parse {
    my( $line, $s ) = @_;
    
    my ($date) = $$s =~ /^ST \* private (\S+)$/mg;
    $date = dateEMBL($date);
    $line->hold_date($date);
}

sub _compose {
    my( $line ) = @_;
    
    my $date = $line->hold_date
        or confess "Missing hold_date";
    $date = EMBLdate($date);
    
    return "ST * private $date\n";
}


1;

__END__

=head1 NAME - Hum::EMBL::Line::ST_star

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

