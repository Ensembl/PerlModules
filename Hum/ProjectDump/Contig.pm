
### Hum::ProjectDump::Contig

package Hum::ProjectDump::Contig;

use strict;
use vars '@ISA';

@ISA = 'Hum::Sequence::DNA';

sub contig_id {
    my( $seq_obj, $contig_id ) = @_;
    
    if ($contig_id) {
        $seq_obj->{'_contig_id'} = $contig_id;
    }
    return $seq_obj->{'_contig_id'};
}

1;

__END__

=head1 NAME - Hum::ProjectDump::Contig

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

