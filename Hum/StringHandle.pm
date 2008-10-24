
### Hum::StringHandle

package Hum::StringHandle;

use strict;
use warnings;
use Carp;
use Symbol 'gensym';

sub new {
    my ($pkg, $string_ref) = @_;

    # A bit of magic which makes a string
    # behave like a filehandle
    my $fh = gensym();
    tie( *{$fh}, $pkg, $string_ref );
    return $fh;
}

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

1;

__END__

=head1 NAME - Hum::StringHandle

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

