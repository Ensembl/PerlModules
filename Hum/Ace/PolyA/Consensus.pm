
### Hum::Ace::PolyA::Consensus

package Hum::Ace::PolyA::Consensus;

use strict;
use warnings;
use Carp;
use POSIX qw{ ceil };
use Statistics::Distributions 'uprob';

sub signal  { shift->[0] };
sub count   { shift->[1] };
sub mean    { shift->[2] };
sub sd      { shift->[3] };

{
    my @cons = map { bless $_, 'Hum::Ace::PolyA::Consensus' } (
        [qw{  aataaa    3286    16  4.7  }],
        [qw{  attaaa     843    17  5.3  }],
        [qw{  agtaaa     156    16  5.9  }],
        [qw{  tataaa     180    18  7.8  }],
        [qw{  cataaa      76    17  5.9  }],
        [qw{  gataaa      72    18  6.9  }],
        [qw{  aatata      96    18  6.9  }],
        [qw{  aataca      70    18  8.7  }],
        [qw{  aataga      43    18  6.3  }],
        [qw{  aaaaag      49    18  8.9  }],
        [qw{  actaaa      36    17  8.1  }],
    );

    my( %signal_cons );
    foreach my $c (@cons) {
        $signal_cons{$c->signal} = $c;
    }

    sub fetch_all {
        return @cons;
    }
    
    sub fetch_by_signal {
        my( $pkg, $signal ) = @_;
        
        return $signal_cons{$signal};
            #confess "No such consensus '$signal'\n",
            #    " -- remember all signal consensi are lower case and use 't' not 'u'";
    }
}

sub population_fraction {
    my( $self ) = @_;

    return $self->count / 5646;
}

sub scan_range_length {
    my( $self ) = @_;

    my $mean = $self->mean;
    my $half_range = ceil($self->sd * 3);
    
    # Only go as far downsteam from the mean as the exon end
    my $downstream = $half_range > $mean ? $mean : $half_range;
    return $half_range + $downstream;
}

sub score_for_position {
    my( $self, $pos ) = @_;
    
    my $Z = (abs($pos) - $self->mean) / $self->sd;

    # Find the area in the two tails of the
    # normal distribution bounded by -Z to +Z
    my $factor = 1 - (2 * (0.5 - uprob(abs $Z)));
    
    return $factor * $self->population_fraction;
}

1;

__END__



=head1 NAME - Hum::Ace::PolyA::Consensus

=head1 DESCRIPTION

This class contains a set of static objects which
implement access to the data described in
B<Beaudoing et al, Genome Research, 10:1001-1010,
(2000)>.

=head1 CLASS METHODS

=over 4

=item fetch_all

Returns a list of all the Consensus objects in
the database.

=item fetch_by_signal

    my $std_polyA = Hum::Ace::PolyA::Consensus
        ->fetch_by_signal("aataaa");

Fetches a particular consensus, given its signal
sequence (which has to be all lower case, and use
"t" not "u").

=back

=head1 INSTANCE PROPERTIES

These are all read-only.

=over 4

=item signal

The consensus sequence for the Consensus, eg:
"attaaa".  It is always all lower case, and uses
"t" not "u".

=item count

The number of times this signal was found in the
5646 UTRs examined.

=item mean

Mean position in the data for this signal of the
last base of the hexamer, counting back from the
last base of the UTR.  For example this is
position B<16>:

        -35  -30  -25  -20  -15  -10   -5    0
          *    *    *    *    *    *    *    *
    B:  ################AAUAAA################AAAAAAAAAAAAAA

This has been rounded to the nearest whole position.

=item sd

The standard deviation of the mean in the data
set for this consensus.

=item population_fraction

This is the fraction of the putative poly(A)
signals found in the data that have this
consensus.

=item scan_range_length

The length of the sequence to scan for signals,
centred around the mean.  This is guaranteed to
include 3 standard deviations on either side of
the mean, and will thus include 99.97% of
signals, but is trimmed to the end of the exon.

=back

=head2 score_for_position( INT )

Returns the fraction of the population that are
this distance or further away from the mean for
this consensus.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

