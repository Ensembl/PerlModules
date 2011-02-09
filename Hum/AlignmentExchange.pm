
### Hum::AlignmentExchange

package Hum::AlignmentExchange;

use strict;
use warnings;
use Carp;
use LWP::UserAgent;

sub new {
    my( $class) = @_;

	my $self =  bless({}, $class);
	$self->_create_ua;

  	return $self;
}

sub get_xml_by_accession_pair {
	my ($self, $accession_a, $accession_b) = @_;

	my $api_url = 'http://www.ncbi.nlm.nih.gov/genome/assembly/grc/CuratDat/grcapi.cgi';
	my $response = $self->{ua}->get("$api_url?acc1=${accession_a}&acc2=${accession_b}");
	my $xml = $response->decoded_content;

	return $xml;
	
}

sub _create_ua {
	my ($self) = @_;
	
	$self->{ua} = LWP::UserAgent->new;
	$self->{ua}->timeout(10);
	$self->{ua}->proxy('http','http://webcache.sanger.ac.uk:3128');
	
	$self->{ua}->credentials(
		'www.ncbi.nlm.nih.gov:80',
		'Contig Overlap Certificate Access Resources',
		'jt8', 'sc28_black6'
	);

	return;
	
}

1;

__END__

=head1 NAME - Hum::AlignmentExchange

=head1 AUTHOR

James Torrance B<email> jt8@sanger.ac.uk

