
### Hum::AlignmentExchange

package Hum::AlignmentExchange;


use strict;
use warnings;
use Carp;
use LWP::UserAgent;
use HTTP::Request::Common qw(POST);

sub new {
    my( $class) = @_;

	my $self =  bless({}, $class);
	$self->{api_url} = 'http://www.ncbi.nlm.nih.gov/projects/genome/assembly/grc/CuratDat/grcapi.cgi';
	$self->_create_ua;

  	return $self;
}

sub get_xml_by_accession_pair {
	my ($self, $accession_a, $accession_b) = @_;

	my $response = $self->{ua}->get($self->{api_url} . "?acc1=${accession_a}&acc2=${accession_b}");
	my $xml = $response->decoded_content;

	return $xml;
	
}

sub get_xml_by_accession_pair_list {
	my ($self, @accession_pair_list) = @_;

	my $list_request;
	foreach my $accession_pair (@accession_pair_list) {
		$list_request .= "$accession_pair->[0]\t$accession_pair->[1]\n";
	}
	
	my $temp_file = "/tmp/temp_accession_pair_list.$$";
	open(my $temp_file_handle, '>', $temp_file) or die "Cannot open temporary file $temp_file: $!\n";
	print {$temp_file_handle} $list_request;
	close $temp_file_handle;

	my $request = (POST $self->{api_url},
    	Content_Type => 'multipart/form-data',
    	Content => [batch =>  [$temp_file]]);

	my $response = $self->{ua}->request($request);
	
	system("rm $temp_file");
	
	my $xml = $response->decoded_content;

	return $xml;
	
}

sub _create_ua {
	my ($self) = @_;
	
	$self->{ua} = LWP::UserAgent->new(keep_alive=>1);
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

