### Hum::EMBL::ExonCollection
#
# Copyright 2004 Genome Research Limited (GRL)
#
# Maintained by Mike Croning <mdr@sanger.ac.uk>
#
# You may distribute this file/module under the terms of the perl artistic
# licence
#
# POD documentation main docs before the code. Internal methods are usually
# preceded with a _
#

=head1 NAME Hum::EMBL::ExonCollection
 
=head2 Constructor:

 ??

=cut

package Hum::EMBL::ExonCollection;

use Carp;
use strict;

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}    

# Storage methods
#sub strand {
#    my( $loc, $value ) = @_;
#    
#    if ($value) {
#        $loc->{'strand'} = $value;;
#    } else {
#        return $loc->{'strand'};
#    }
#}

sub missing_5_prime {
    my( $loc, $value ) = @_;
    
    if (defined $value) {
        $loc->{'missing_5_prime'} = $value;
    } else {
        return $loc->{'missing_5_prime'};
    }
}
sub missing_3_prime {
    my( $loc, $value ) = @_;
    
    if (defined $value) {
        $loc->{'missing_3_prime'} = $value;
    } else {
        return $loc->{'missing_3_prime'};
    }
}

=head2 exons

Get/set method for the list of 
Hum::EMBL::Location::Exon objects.

=cut

sub exons {
    my( $loc, @exons ) = @_;
    
    if (@exons) {
        $loc->{'exons'} = [@exons];
    } else {
        return @{$loc->{'exons'}};
    }
}

sub start_not_found {
    my( $loc ) = @_;
    
    if ($loc->strand eq 'W') {
        $loc->missing_5_prime(1);
    } elsif ($loc->strand eq 'C') {
        $loc->missing_3_prime(1);
    } else {
        confess "Direction not specified";
    }
}
sub end_not_found {
    my( $loc ) = @_;
    
    if ($loc->strand eq 'W') {
        $loc->missing_3_prime(1);
    } elsif ($loc->strand eq 'C') {
        $loc->missing_5_prime(1);
    } else {
        confess "Direction not specified";
    }
}

sub start {
    my( $loc ) = @_;
    
    return $loc->strand eq 'W' ? $loc->five_prime : $loc->three_prime;
}
sub end {
    my( $loc ) = @_;
    
    return $loc->strand eq 'W' ? $loc->three_prime : $loc->five_prime;
}

sub length {
    my( $loc ) = @_;
    
    return $loc->three_prime - $loc->five_prime + 1;
}

=head2 five_prime

Return the start of the first Hum::EMBL::Location::Exon
object, or confess should none exist

=cut

sub five_prime {
    my( $loc ) = @_;
    
    if (my $exon = $loc->{'exons'}[0]) {
        return $exon->start;
    } else {
        confess "No start position";
    }
}

=head2 three_prime

Return the end of the first Hum::EMBL::Location::Exon
object, or confess should none exist

=cut

sub three_prime {
    my( $loc ) = @_;
    
    if (my $exon = $loc->{'exons'}[-1]) {
        return $exon->end;
    } else {
        confess "No end position";
    }
}

sub parse {
    my( $loc, $s ) = @_;
    
    # If the location contains multiple complement
    # tags, then the order of the exons will need
    # to be reversed
    my $C_count = 0;
    while ($$s =~ /complement/g) {
        $C_count++;
    }
    if ($C_count) {
        $loc->strand('C');
    } else {
        $loc->strand('W');
    }
    
    $loc->missing_5_prime(1) if $$s =~ /</;
    $loc->missing_3_prime(1) if $$s =~ />/;
    
    my( @exons );
    while ($$s =~ /(\d+)\.\.>?(\d+)/g) {
        push( @exons, [$1, $2] );
    }
    if (@exons) {
        if ($C_count > 1) {
            @exons = reverse @exons;
        }
        $loc->exons(@exons);
    } elsif (my ($i) = $$s =~ /(\d+)/) {
        # Single base pair
        $loc->exons($i);
    } else {
        confess "Can't parse location string '$$s'";
    }
}

# Generates a unique string for a location
sub hash_key {
    my( $loc ) = @_;

    warn "This needs to be changed\n";
    my @exons = $loc->exons;
    my @key;
        
    my( @key );
    if (ref($loc->{'exons'}[0])) {
        @key = map @$_, @{$loc->{'exons'}};
    } else {
        @key = @{$loc->{'exons'}};
    }
    
    return join '_', ($loc->{'strand'}, @key,
        $loc->{'missing_5_prime'},
        $loc->{'missing_3_prime'});
}

BEGIN {
    my $joiner = "\nFT". ' ' x 19;

    sub compose {
        my( $loc ) = @_;

        my( @exons ) = $loc->exons;

        my( $text );
        if (ref $exons[0]) {
            if ($loc->missing_5_prime) {
                my $i = $exons[0][0];
                $exons[0][0] = "<$i";
            }
            if ($loc->missing_3_prime) {
                my $i = $exons[$#exons][1];
                $exons[$#exons][1] = ">$i";
            }
            
            if (@exons == 1) {
                $text = "$exons[0][0]..$exons[0][1]";
            } else {
                $text = 'join('. join(',', map "$_->[0]..$_->[1]", @exons) .')';
            }
        } else {
            $text = $exons[0];
            if ($loc->missing_5_prime) {
                $text = "<$text";
            } elsif ($loc->missing_3_prime) {
                $text = ">$text";
            }
        }

        my $strand = $loc->strand;
        if ($strand eq 'C') {
            $text = "complement($text)";
        } else {
            confess "Strand='$strand'"
                unless $strand eq 'W';
        }

        my( @lines );
        while ($text =~ /(.{1,58}(,|$))/g) {
            push(@lines, $1);
        }

        return join($joiner, @lines) ."\n";
    }
}

sub add_location_qualifier {
    my( $loc, $qualifier ) = @_;
    
    $loc->{'_location_qualifers'} ||= [];
    push(@{$loc->{'_location_qualifers'}}, $qualifier);
}

sub location_qualifiers {
    my( $loc ) = @_;
    
    if (my $q = $loc->{'_location_qualifers'}) {
        return @$q;
    } else {
        return;
    }
}

1;

__END__

