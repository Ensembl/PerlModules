=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


### Hum::AssemblyTag

package Hum::AssemblyTag::Submissions;

use strict;
use warnings;
use Carp;

use Hum::AssemblyTag;

use vars qw( @ISA );

@ISA = 'Hum::AssemblyTag';

sub save {
	my ($self) = @_;
	
	my $save_sql = "INSERT INTO assembly_tag (seq_id, start, end, type, comment) VALUES (?,?,?,?,?);";
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

=head1 NAME - Hum::AssemblyTag::Submissions

=head1 AUTHOR

James Torrance B<email> jt8@sanger.ac.uk

