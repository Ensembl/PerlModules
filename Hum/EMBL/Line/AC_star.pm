
package Hum::EMBL::Line::AC_star;

use strict;
use warnings;
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
        if length($identifier) > 35;
    
    return "AC * $identifier\n";
}

1;

__END__

=head1 Hum::EMBL::Line::AC_star

This is the line handling module for lines in
EMBL files that begin 'AC * '.   These are used
to tag our submissions to EMBL.  Once the entry
has been processed we can get the accession
assigned to it from the EMBL oracle database
using the project number (which is "12" for the
"sangerhs" entries) concatenated to the
identifier as a lookup.

AC_star has one scalar field:

=over 4

=item identifier

The identifier should begin with an underscore,
contain only capital letters and numerals, and
not exceed 35 characters.

=back

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>
