
package Hum::EMBL::Line::AC_star;

use strict;
use Carp;
use Hum::EMBL::Line;
use vars qw( @ISA );

BEGIN {
    @ISA = qw( Hum::EMBL::Line );
    Hum::EMBL::Line::AC_star->makeFieldAccessFuncs(qw( primary     ));
    Hum::EMBL::Line::AC_star->makeListAccessFuncs (qw( secondaries ));
}

sub parse {
    my( $line, $s ) = @_;
    
    my @lines = $$s =~ /^AC \* (.+)$/mg;
    my( @ac );
    foreach (@lines) {
        push( @ac, split /;\s*/ );
    }
    my $primary = shift( @ac );
    $line->primary    ( $primary );
    $line->secondaries( @ac );
}

sub compose {
    my( $line ) = @_;
    
    my $ac = join( '', map "$_;", ($line->primary(), $line->secondaries()) );
    
    return $line->string($line->wrap('AC * ', $ac));
}

1;
