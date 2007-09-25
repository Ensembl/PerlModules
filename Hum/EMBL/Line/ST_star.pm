
### Hum::EMBL::Line::ST_star (it was Hum::EMBL::Line::HD_star)
### ERROR: HD line not allowed with the new ID line, use the ST line instead

package Hum::EMBL::Line::ST_star;

use strict;
use Carp;
use Hum::EMBL::Line;
use Hum::EMBL::Utils qw( EMBLdate dateEMBL );
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::HD_star->makeFieldAccessFuncs(qw( hold_date ));

sub parse {
    my( $line, $s ) = @_;
    
    my ($date) = $$s =~ /^ST \* confidential (\S+)$/mg;
    $date = dateEMBL($date);
    $line->hold_date($date);
}

sub _compose {
    my( $line ) = @_;
    
    my $date = $line->hold_date
        or confess "Missing hold_date";
    $date = EMBLdate($date);
    
    return "ST * confidential $date\n";
}


1;

__END__

=head1 NAME - Hum::EMBL::Line::HD_star

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

