
### Hum::AssemblyTag

package Hum::AssemblyTag::Local;

use strict;
use warnings;
use Carp;
use Hum::AssemblyTag;

use vars qw( @ISA );

@ISA = 'Hum::AssemblyTag';

sub save {
	my ($self) = @_;
	
	my $save_sql = "INSERT INTO tag (accession, start, end, type, comment) VALUES (?,?,?,?,?);";
	my $save_dbh = $self->{DBI}->prepare($save_sql);
	my $result = $save_dbh->execute(
		$self->{COMPONENT},
		$self->{START},
		$self->{END},
		$self->{TYPE},
		$self->{COMMENT},
	);
	
	if($result != 1) {
		warn "Problem saving row for $self->{COMPONENT}\n";
	}
	
	return;
}

1;

__END__

=head1 NAME - Hum::AssemblyTag::Local

=head1 AUTHOR

James Torrance B<email> jt8@sanger.ac.uk

