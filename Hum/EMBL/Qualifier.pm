
package Hum::EMBL::Qualifier;

use strict;
use Carp;

sub new {
    my( $pkg ) = @_;
    
    return bless {
        name  => undef,
        value => undef,
    }, $pkg;
}
sub name {
    my( $qual, $name ) = @_;
    
    if ($name) {
        $qual->{'name'} = $name;
    } else {
        return $qual->{'name'};
    }
}
sub value {
    my( $qual, $value ) = @_;
    
    if ($value) {
        $qual->{'value'} = $value;
    } else {
        return $qual->{'value'};
    }

}

sub parse {
    my( $qual, $s ) = @_;
    
    my( $name, $value ) = $$s =~ /^([^=]+)=?(.+)?\s*$/
        or confess "Can't parse '$$s'";
    $qual->name($name);
    if ($value) {
        $value =~ /^"/;
        unquotify( \$value );
        $qual->value($value);
    }
}

BEGIN {

    my $prefix = 'FT'. ' ' x 19;

    # List of qualifiers which always have unquoted values
    my %no_quote = map {$_, 1} qw(
                                  citation
                                  codon_start
                                  evidence
                                  label
                                  number
                                  transl_except
                                  usedin
                                  );

    sub compose {
        my( $qual ) = @_;

        my $name = $qual->name;
        my $value = $qual->value;

        if ($value) {
            quotify(\$value) unless $no_quote{$name};

            my $text = "/$name=$value";

            my( @lines );
            while ($text =~ /(.{0,58}\S)(\s+|$)/g) {
                push( @lines, "$prefix$1\n" );
            }
            
            return @lines;
        } else {
            return "$prefix/$name\n";
        }
    }
}

sub quotify {
    my( $s ) = @_;
    
    $$s =~ s/"/""/g;
    $$s = qq("$$s");
}

sub unquotify {
    my( $s ) = @_;
    
    $$s =~ s/(^"|"$)//g;
    $$s =~ s/""/"/g;
}

1;
