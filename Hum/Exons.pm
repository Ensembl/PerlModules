
=pod

=head1 NAME Hum::Exons

=head1 DESCRIPTION

B<Hum::Exons> 

=cut

package Hum::Exons;

use strict;
use warnings;
use Carp;

# START and stop are coordinates relative to the DNA
# part of the object

# Set up field accessors
BEGIN {
    my @Fields = qw( START STOP DNA TEXT );

    for (my $i = 0; $i < @Fields; $i++) {
        eval "sub $Fields[$i] () { $i }"; # An evil eval!
        warn $@ if $@; # So we get warnings if syntax error
    }
}

# Can optionally supply some text 
sub new {
    my( $pkg, $text ) = @_;

    my $ex = bless [], $pkg;
    $ex->[TEXT] = $text if $text;
    return $ex;
}

# Get or set the text
sub text {
    my $ex = shift;
    
    if (@_) {
        $ex->[TEXT] = shift;
    } else {
        return $ex->[TEXT];
    }
}

# Get or set the start
sub start {
    my $ex = shift;
    
    if (@_) {
        $ex->[START] = shift;
    } else {
        return $ex->[START];
    }
}

# Get or set the stop
sub stop {
    my $ex = shift;
    
    if (@_) {
        $ex->[STOP] = shift;
    } else {
        return $ex->[STOP];
    }
}

# Get or set start and stop in one go - UNUSED
sub range {
    my $ex = shift;
    
    if (@_) {
        $ex->[START] = shift;
        $ex->[STOP] = shift;
    } else {
        return ($ex->[START], $ex->[STOP]);
    }
}   

# Get or set the nucleotide string
sub dna {
    my $ex = shift;
    
    if (@_) {
        my $type = ref($_[0]);
        unless ($type) {
            confess "Argument to dna() must be ref to SCALAR or list of objects";
        } elsif ($type eq 'SCALAR') {
            $ex->[DNA] = shift;
        } else {
            $ex->[DNA] = [@_];
        }
    } else {
        my $nuc = $ex->[DNA];
        my $ref = ref($nuc);

        if ($ref eq 'ARRAY') {
            my $dna = join('', map { $_->dna() } @$nuc);
            return $ex->_dna(\$dna);
        } elsif ($ref eq 'SCALAR') {
            return $ex->_dna();
        } else {
            confess "DNA field is '$ref', not 'SCALAR' or 'ARRAY'";
        }
    }
}

# Returns an actual dna string
sub _dna {
    my( $ex, $dnaRef ) = @_;
    my( $revComp,   # Set if sequence needs to be rev-comped
        $start,     # Start point in the sequence
        $length,    # Length of subsequence
        );
    
    $dnaRef = $ex->[DNA] unless $dnaRef;
    my $x = $ex->start();
    my $y = $ex->stop();
    
    # If either START or STOP aren't filled in, then they are
    # set to the beginning or end of the string respectively
    $x = 0                    unless defined $x;
    $y = length($$dnaRef) - 1 unless defined $y;
    
    # Could add special case where one of the coordinates
    # is empty string - use to specify a single base on
    # the forward or reverse strand.
    
    # Could also return strings of dashes for overhangs off
    # left or right of the string
    
    if ($x < $y) {
        $start = $x;
        $length = $y - $x + 1;
    } elsif ($x > $y) {
        $revComp = 1;
        $start = $y;
        $length = $x - $y + 1;
    } else {
        confess "Coordinates ('$x', '$y') in exons object are equal!";
    }
    
    
    my $dna = substr($$dnaRef, $start, $length);
    return $revComp ? revcomp( $dna ) : $dna;
}

# Reverse-complements a dna sequence
sub revcomp {
    my( $dna ) = @_;
    
    $dna = reverse($dna);
    $dna =~ tr[acgtrymkswhbvdn\-ACGTRYMKSWHBVDN]
              [tgcayrkmswdvbhn\-TGCAYRKMSWDVBHN];
    return $dna;
}

sub toTrue {
    foreach (@_) {
        if (/^\+?\d+$/ and $_ > 0) {
            $_--;
        } elsif ($_ == 0) {
            $_ = 'ZERO';
        }
    }
}

sub fromTrue {
    foreach (@_) {
        if (/^\+?\d+$/ and $_ > -1) {
            $_++;
        }
    }
}

sub dir {
    my( $ex ) = @_;
    
    my $x = $ex->[START];
    my $y = $ex->[STOP];
    
    if ($x == $y) {
        confess( "Exon starts('$x') and stops('$y') at same point!" );
    } elsif ($x < $y) {
        return 'W';
    } else {
        return 'C';
    }
}

### HIGHER LEVEL METHODS ###

# Returns a new Exons object with the range specified
sub segment {
    my($ex, $start, $stop) = @_;
        
    my $new = [];
    bless $new, ref($ex);
    $new->[DNA] = $ex->[DNA];
    $new->start($start);
    $new->stop($stop);
    
    return $new;
}



1;

__END__

=head1 SYNOPSIS


=head1 METHODS

=over 4

=item new

Make a new B<Hum::Exons> object.

=back

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>

