
package Hum::EMBL::Handle;

use strict;
use Carp;

sub TIEHANDLE {
    my( $pkg, $string ) = @_;
    
    confess "Not a SCALAR ref '$string'"
        unless ref($string) eq 'SCALAR';
    return bless {
        _string => $string
    }, $pkg;
}

sub READLINE {
    my( $hand ) = @_;
    
    my $offset = $hand->{'_offset'} || 0;
    my $string = $hand->{'_string'};
    
    my $i = index( $$string, "\n", $offset );
    if ($i == -1) {
        $hand->{'_offset'} = undef;
        return undef;
    } else {
        $hand->{'_offset'} = $i + 1;
        return substr( $$string, $offset, $i - $offset + 1 );
    }
}

# 012345
# xxxxxn

1;

__END__

