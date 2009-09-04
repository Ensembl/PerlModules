
package Hum::EMBL::Line::BQ_star;

use strict;
use warnings;
use Carp;
use Hum::EMBL::Line;
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::BQ_star->makeFieldAccessFuncs(qw( quality ));

sub parse {
    my( $line, $s ) = @_;
    
    my( $string );
    while ($$s =~ /^BQ \* ([\d ]+)$/mg) {
        if (length($1) % 3) {
            confess "Bad quality line: $1";
        }
        $string .= $1;
    }
    
    my $qual = pack('C*', split /\s+/, $string);
    
    $line->quality( $qual );
}

sub _compose {
    my( $line ) = @_;
    
    my $qual = $line->quality;
    my $len = length($qual);
    my $bq = '';            # Stores formatted output
    my $N = 25;             # Number of quality values per line
    my $pat = 'A3' x $N;    # Standard pattern for a whole line
    my $prefix = 'BQ * ';
    
    my $whole_lines = int( $len / $N );

    for (my $l = 0; $l < $whole_lines; $l++) {
        my $offset = $l * $N;
        # Print a slice of the array on one line
        $bq .= 'BQ * '. pack($pat, unpack('C*', substr($qual, $offset, $N))) ."\n"
    }

    if (my $r = $len % $N) {
        my $pat = 'A3' x $r;
        my $offset = $whole_lines * $N;
        $bq .= 'BQ * '. pack($pat, unpack('C*', substr($qual, $offset    ))) ."\n"
    }

    return $bq;    
}

1;

__END__

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>

