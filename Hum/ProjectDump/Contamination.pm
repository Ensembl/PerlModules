
### Hum::ProjectDump::Contamination

package Hum::ProjectDump::Contamination;

use strict;
use Carp;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub contamination_db_location {
    my( $cont, $location ) = @_;
    
    if ($location) {
        $cont->{'_contamination_db_location'} = $location;
    }
    return $cont->{'_contamination_db_location'};
}

sub screen_ProjectDump {
    my( $cont, $dump ) = @_;
    
    confess("'$dump' isn't a Hum::ProjectDump") unless 
        ref($dump) and $dump->isa('Hum::ProjectDump');
    my $contam_db_path = $cont->contamination_db_location
        or confess "contamination_db_location not set";
    confess "Contamination db '$contam_db_path' doesn't exist"
        unless -e $contam_db_path;
    
}

1;

__END__

=head1 NAME - Hum::ProjectDump::Contamination

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

