
package Hum::EMBL::Utils;

use Carp;
use strict;
use Time::Local qw( timelocal );

use Exporter;
use vars qw( @ISA @EXPORT_OK );
@ISA = qw( Exporter );
@EXPORT_OK = qw( EMBLdate dateEMBL );

BEGIN {

    my @months = qw( JAN FEB MAR APR MAY JUN
                     JUL AUG SEP OCT NOV DEC );
    my @mDay = ('00'..'31');
    my( %months );
    {
        my $i = 0;
        %months = map { $_, $i++ } @months;
    }
    
    # Convert EMBL date to unix time int
    sub dateEMBL {
        my( $embl ) = @_;
        my( $mday, $mon, $year ) = split /-/, $embl;
        $year -= 1900;
        $mon = $months{ $mon };
        return timelocal( 0, 0, 0, $mday, $mon, $year );
    }

    # Convert unix time int to EMBL date
    sub EMBLdate {
        my $time = shift || time;
        my ($sec, $min, $hour, $mday, $mon, $year) = localtime($time);
        $year += 1900;
        $mon = $months[$mon];
        $mday = $mDay[$mday];
        return "$mday-$mon-$year";
    }
}



1;

__END__

