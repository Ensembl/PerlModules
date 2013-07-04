
### Hum::Sort

package Hum::Sort;

use strict;
use warnings;
use base 'Exporter';

our @EXPORT_OK = qw{ ace_sort array_ace_sort };

sub ace_sort {
    my $A = [ split(/(\d+)/, lc shift) ];
    my $B = [ split(/(\d+)/, lc shift) ];
    
    return _ace_array_sort($A, $B);
}

sub _ace_array_sort {
    my( $A, $B ) = @_;
    
    my $x = shift @$A;
    my $y = shift @$B;
    
    # $x or $y will be undef once we are off
    # the end of either array.
    # undef (shorter) sorts first.
    if (! defined $x) {
        return defined $y ? -1 : 0;
    }
    elsif (! defined $y) {
        # $x must be defined, or condition
        # above would have matched.
        return 1;
    }
    # Next two conditions recursively call _ace_array_sort
    # if the comparison operators return 0 (equal).
    elsif ($x =~ /\d/ and $y =~ /\d/) {
        # Compare numerically if both elements are numeric
        return $x <=> $y || _ace_array_sort($A, $B);
    }
    else {
        # cmp does the right thing otherwise
        # (numbers are sorted before letters).
        return $x cmp $y || _ace_array_sort($A, $B);
    }
}

sub array_ace_sort {
    my ($array_A, $array_B) = @_;

    # Sort copies of the two arrays so that we can eat them away
    # with shift operations in recursive calls:
    return _array_copies_ace_sort([@$array_A], [@$array_B]);
}

sub _array_copies_ace_sort {
    my ($copy_A, $copy_B) = @_;

    my $x = shift @$copy_A;
    my $y = shift @$copy_B;

    # First check to see if we are off the end of either array
    # (or either element is undef, which should sort first)
    if (! defined $x) {
        return defined $y ? -1 : 0;
    }
    elsif (! defined $y) {
        # Then $x must be defined, due to first test.
        return 1;
    }
    # The first elements of both arrays are defined, so we sort on them
    else {
        return ace_sort($x, $y)
        # The first elements of the two arrays don't sort with ace_sort
        # so we go onto the next.
          || _array_copies_ace_sort($copy_A, $copy_B);
    }
}


1;

__END__

=head1 NAME - Hum::Sort

=head1 SYNOPSIS

    use Hum::Sort 'ace_sort';
    
    # Sorting strings
    @sorted = sort { ace_sort($a, $b) } @un_sorted;
    
    # Sorting objects
    @sorted_obj = sort { ace_sort($a->name, $b->name) } @objects;

=head2 ace_sort

Sorts objects in a case insensitive and human intuitive way. This is
especially nice for sorting things like clone names, and is copied from
how acedb sorts data in its displays.

=head2 array_ace_sort

Sorts two array references, sorting using C<ace_sort> on each pair of
elements.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

