=head1 LICENSE

Copyright [2018-2020] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


package Hum::EMBL::Qualifier;

use strict;
use warnings;
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

    my $prefix = 'FT'. ' ' x 19;    # All lines start with this
    my $max = 59;                   # Max length for rest of line

    sub compose {
        my( $qual ) = @_;

        my $name = $qual->name;
        my $value = $qual->value;

        if ($value) {
            quotify(\$value) unless $no_quote{$name};

            my $text = "/$name=$value";

            my( @lines );
            if (substr($text, 0, $max) =~ /\s/) {
                # First line has spaces, so wrap on words
                my $limit = $max - 1;
                while ($text =~ /(.{0,$limit}\S)(\s+|$)/og) {
                    push( @lines, "$prefix$1\n" );
                }
            } else {
                # Need to do hard wrapping
                my $total = length($text);
                for (my $i = 0; $i < $total; $i += $max) {
                    push( @lines, $prefix . (substr $text, $i, $max) ."\n" );
                }
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

__END__

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>

