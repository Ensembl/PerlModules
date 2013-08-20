package Hum::NcbiFetch;

use strict;
use warnings;
use Carp;
use Exporter;
use vars qw( @EXPORT_OK @ISA );
use LWP::UserAgent;

use Hum::Conf qw( HUMPUB_ROOT );
use Hum::Lock;
use Hum::EMBL;
use Hum::NetFetch qw(wwwfetch_EMBL_object);
use Hum::NcbiFetch qw();
use Bio::SeqIO;

@ISA = qw( Exporter );
@EXPORT_OK = qw( wwwfetch_EMBL_object_using_NCBI_fallback ncbi_genbank_fetch ncbi_embl_fetch ncbi_embl_object_fetch);

my $ncbi_base_url = 'http://eutils.ncbi.nlm.nih.gov/entrez/eutils/';
my $ncbi_fetch = 'efetch.fcgi';
my $ncbi_parameters = 'db=nucleotide&rettype=gbwithparts&retmode=text&id=';

sub ncbi_genbank_fetch {
    my( $ac ) = @_;
    my $get = "$ncbi_base_url$ncbi_fetch?$ncbi_parameters$ac";

    my $ua = LWP::UserAgent->new;
    $ua->env_proxy;
    #$ua->proxy(http  => 'http://webcache.sanger.ac.uk:3128');
    my $req = HTTP::Request->new(GET => $get);        
    my $ncbi =  $ua->request($req)->content;

    unless (defined $ncbi) {
        die "No response from '$get'";
    }
    elsif (substr($ncbi, 0, 5) ne 'LOCUS') {
        die "Entry for '$ac' not found by request '$get'"
    } else {
        return $ncbi;
    }
}

sub ncbi_embl_fetch {
    my( $ac ) = @_;
    my $genbank = ncbi_genbank_fetch($ac);
    return genbank_to_embl($genbank);
}

sub ncbi_embl_object_fetch {
    my ($acc) = @_;
    
    my $txt;
    eval {
        $txt = ncbi_embl_fetch($acc);
    };
    if ($@) {
        warn $@;
        return;
    }
    else {
        my $parser = Hum::EMBL->new;
        my $embl = $parser->parse(\$txt)  
            or confess "nothing returned from parsing '$txt'";
        return $embl;        
    }
}


sub genbank_to_embl {
	my ($genbank) = @_;

	open(my $genbank_handle, '<', \$genbank);
	my $embl = '';
    open(my $embl_handle, '>', \$embl);

    my $input_stream  = Bio::SeqIO->new(-fh => $genbank_handle,
                                        -format => 'Genbank');
    my $output_stream = Bio::SeqIO->new(-fh => $embl_handle,
	                                    -format => 'EMBL');
	
	while ( my $seq = $input_stream->next_seq() ) {
        $output_stream->write_seq($seq);
    }
	close $genbank_handle;
	close $embl_handle;
	
	return $embl;
}

sub wwwfetch_EMBL_object_using_NCBI_fallback {
    my ($acc) = @_;
    
    my $embl = wwwfetch_EMBL_object($acc);
    if(!defined($embl)) {
        $embl = ncbi_embl_object_fetch($acc);
    } 
    return $embl;
}

1;

__END__

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>

