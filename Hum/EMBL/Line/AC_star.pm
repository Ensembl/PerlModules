
package Hum::EMBL::Line::AC_star;

use strict;
use Carp;
use Hum::EMBL::Line;
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::AC_star->makeFieldAccessFuncs(qw( identifier ));

sub parse {
    my( $line, $s ) = @_;
    
    my ($id) = $$s =~ /^AC \* (\S+)$/mg;
    $line->identifier( $id );
}

sub _compose {
    my( $line ) = @_;
    
    my $identifier = $line->identifier;
    confess "Identifier '$identifier' too long"
        if length($identifier) > 75;
    
    return "AC * $identifier\n";
}

1;
