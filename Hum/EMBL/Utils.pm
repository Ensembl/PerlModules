
package Hum::EMBL::Utils;

use Carp;
use strict;
use warnings;
use POSIX ();

use Exporter;
use vars qw( @ISA @EXPORT_OK );
@ISA = qw( Exporter );
@EXPORT_OK = qw( EMBLdate dateEMBL crc32 );

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
        return POSIX::mktime( 0, 0, 0, $mday, $mon, $year );
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

{
    my( @crcTable );
    
    sub generateCRCTable {
        # 10001000001010010010001110000100
        # 32 
        my $poly = 0xEDB88320;
        
        foreach my $i (0..255) {
            my $crc = $i;
            for (my $j=8; $j > 0; $j--) {
                if ($crc & 1) {
                    $crc = ($crc >> 1) ^ $poly;
                }
                else {
                    $crc >>= 1;
                }
            }
            $crcTable[$i] = $crc;
        }
    }

    sub crc32 {
        my( $str ) = @_;

        confess "Argument to crc32() must be ref to scalar"
            unless ref($str) eq 'SCALAR';

        generateCRCTable() unless @crcTable;

        my $len = length($$str)
            or confess "Empty string";

        #warn "String is $len long\n";

        my $crc = 0xFFFFFFFF;
        for (my $i = 0; $i < $len; $i++) {
            # Get upper case value of each letter
            my $int = ord uc substr($$str, $i, 1);
            $crc = (($crc >> 8) & 0x00FFFFFF) ^ $crcTable[ ($crc ^ $int) & 0xFF ];
        }
        #return sprintf "%X", $crc; # SwissProt format
        
        return $crc;
    }
}


1;

__END__

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>

