
### Hum::ProjectDump::EMBL::Finished

package Hum::ProjectDump::EMBL::Finished;

use strict;

use Carp;
use Hum::ProjectDump::EMBL;

use vars qw{ @ISA };
@ISA = qw{ Hum::ProjectDump::EMBL };

sub add_Description {
    my( $pdmp, $embl ) = @_;
    
}

sub add_Keywords {
    my( $pdmp, $embl ) = @_;
    
}

=pod

=head2 EMBL Database Divisions

    Division                Code
    -----------------       ----
    ESTs                    EST
    Bacteriophage           PHG
    Fungi                   FUN
    Genome survey           GSS
    High Throughput cDNA    HTC
    High Throughput Genome  HTG
    Human                   HUM
    Invertebrates           INV
    Mus musculus            MUS
    Organelles              ORG
    Other Mammals           MAM
    Other Vertebrates       VRT
    Plants                  PLN
    Prokaryotes             PRO
    Rodents                 ROD
    STSs                    STS
    Synthetic               SYN
    Unclassified            UNC
    Viruses                 VRL

=cut

{
    my %species_division = (
        'Human'         => 'HUM',
        'Gibbon'        => 'PRI',
        'Mouse'         => 'MUS',
        'Dog'           => 'MAM',

        'Fugu'          => 'VRT',
        'Zebrafish'     => 'VRT',
        'B.floridae'    => 'VRT',

        'Drosophila'    => 'INV',
        );

    sub EMBL_division {
        my( $pdmp ) = @_;

        my $species = $pdmp->species;
        return $species_division{$species} || 'VRT';
    }
}

1;

__END__

=head1 NAME - Hum::ProjectDump::EMBL::Finished

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

