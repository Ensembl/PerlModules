
### Hum::Ace::Colors

package Hum::Ace::Colors;

use strict;
use Exporter;
use Carp;

use vars '@EXPORT_OK';
@EXPORT_OK = ('acename_to_webhex');

my %color_rgb = (
    'WHITE'        => [ 255, 255, 255 ],
    'BLACK'        => [   0,   0,   0 ],
    'LIGHTGRAY'    => [ 200, 200, 200 ],
    'DARKGRAY'     => [ 100, 100, 100 ],
    'RED'          => [ 255,   0,   0 ],
    'GREEN'        => [   0, 255,   0 ],
    'BLUE'         => [   0,   0, 255 ],
    'YELLOW'       => [ 255, 255,   0 ],
    'CYAN'         => [   0, 255, 255 ],
    'MAGENTA'      => [ 255,   0, 255 ],
    'LIGHTRED'     => [ 255, 160, 160 ],
    'LIGHTGREEN'   => [ 160, 255, 160 ],
    'LIGHTBLUE'    => [ 160, 200, 255 ],
    'DARKRED'      => [ 175,   0,   0 ],
    'DARKGREEN'    => [   0, 175,   0 ],
    'DARKBLUE'     => [   0,   0, 175 ],
    'PALERED'      => [ 255, 230, 210 ],
    'PALEGREEN'    => [ 210, 255, 210 ],
    'PALEBLUE'     => [ 210, 235, 255 ],
    'PALEYELLOW'   => [ 255, 255, 200 ],
    'PALECYAN'     => [ 200, 255, 255 ],
    'PALEMAGENTA'  => [ 255, 200, 255 ],
    'BROWN'        => [ 160,  80,   0 ],
    'ORANGE'       => [ 255, 128,   0 ],
    'PALEORANGE'   => [ 255, 220, 110 ],
    'PURPLE'       => [ 192,   0, 255 ],
    'VIOLET'       => [ 200, 170, 255 ],
    'PALEVIOLET'   => [ 235, 215, 255 ],
    'GRAY'         => [ 150, 150, 150 ],
    'PALEGRAY'     => [ 235, 235, 235 ],
    'CERISE'       => [ 255,   0, 128 ],
    'MIDBLUE'      => [  86, 178, 222 ],
    );

my( %color_hex );
while (my ($name, $rgb) = each %color_rgb) {
    my $hex = sprintf "#%02x%02x%02x", @$rgb;
    warn "$name = $hex\n";
    $color_hex{$name} = $hex;
}

sub acename_to_webhex {
    my( $name ) = @_;
    
    return $color_hex{$name} || confess "No such acedb color '$name'";
}
1;

__END__

=head1 NAME - Hum::Ace::Colors

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

