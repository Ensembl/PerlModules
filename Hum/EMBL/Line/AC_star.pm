
package Hum::EMBL::Line::AC_star;

use strict;
use Carp;
use Hum::EMBL::Line;
use vars qw( @ISA );

BEGIN {
    @ISA = qw( Hum::EMBL::Line );
    Hum::EMBL::Line::AC_star->makeFieldAccessFuncs(qw( identifier ));
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
    
    my $identifier = $line->identifier;
    confess "Identifier '$identifier' too long"
        if length($identifier) > 75;
    
    return $line->string("AC * $identifier");
}

1;
