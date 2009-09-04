
### Hum::Ace::Colors

package Hum::Ace::Colors;

use strict;
use warnings;
use base 'Exporter';
use Carp;

use vars '@EXPORT_OK';
@EXPORT_OK = qw{
    acename_to_rgb
    acename_to_webhex
    webhex_to_acename
    list_all_color_names
    };

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

my( %color_hex, %hex_color );
while (my ($name, $rgb) = each %color_rgb) {
    my $hex = sprintf "#%02x%02x%02x", @$rgb;
    #warn "$name = $hex\n";
    $color_hex{$name} = $hex;
    $hex_color{$hex} = $name;
}

sub acename_to_rgb {
    my( $name ) = @_;
    
    if (my $rgb = $color_rgb{$name}) {
        return @$rgb;
    } else {
        confess "No such acedb color '$name'";
    }
}

sub webhex_to_acename {
    my( $hex ) = @_;
    
    return $hex_color{$hex};
}

sub acename_to_webhex {
    my( $name ) = @_;
    
    if (my $hex = $color_hex{$name}) {
        return $hex;
    } else {
        confess "No such acedb color '$name'";
    }
}

sub list_all_color_names {
    return sort keys %color_rgb;
}

sub list_all_color_names_by_value {
    return sort {
        $color_rgb{$a}[0] <=> $color_rgb{$b}[0] ||
        $color_rgb{$a}[1] <=> $color_rgb{$b}[1] ||
        $color_rgb{$a}[2] <=> $color_rgb{$b}[2]
        } keys %color_rgb;
}

1;

__END__

=head1 NAME - Hum::Ace::Colors

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

