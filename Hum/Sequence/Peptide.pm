
### Hum::Sequence::Peptide

package Hum::Sequence::Peptide;

use strict;
use warnings;
use vars '@ISA';
use Carp;
use Hum::Sequence;

@ISA = 'Hum::Sequence';


sub ace_string {
    my( $seq_obj ) = @_;
    
    my $name = $seq_obj->name
        or confess "No name";
    my $seq  = $seq_obj->sequence_string
        or confess "No sequence";
    my $ace_string = qq{\nProtein : "$name"\n\nPeptide : "$name"\n};
    while ($seq =~ /(.{1,60})/g) {
        $ace_string .= $1 . "\n";
    }
    return $ace_string;
}


1;

__END__

=head1 NAME - Hum::Sequence::Peptide

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

