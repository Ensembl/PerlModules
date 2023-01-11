=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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


### Hum::GapTags

package Hum::GapTags::Local;

use strict;
use warnings;
use Carp;
use Hum::GapTags;
use Hum::AssemblyTag::Local;

use vars qw( @ISA );

@ISA = 'Hum::GapTags';

sub new {
	my $type = shift;
	my $class = ref $type || $type;
	my $self = $class->SUPER::new(@_);
	$self->{ASSEMBLY_TAG_SUBCLASS} = 'Hum::AssemblyTag::Local';
	return $self;
}

sub component_for_assembly_tag {
	my ($self) = @_;
	return $self->accession;
}

sub save {
    my ($self) = @_;

	if(!$self->{SAVED}) {
		my $save_sql = "INSERT INTO project (project, species, accession, run_id, result, errors, comments) VALUES (?,?,?,?,?,?,?);";
		my $save_dbh = $self->{DBI}->prepare($save_sql);
		my $result = $save_dbh->execute(
			$self->{PROJECT},
			$self->species,
			$self->accession,
			$self->{RUN_ID},
			$self->{RESULT},
			$self->{ERROR_STRING},
			$self->{COMMENT_STRING},
		);
		$self->{SAVED} = 1;
		
		foreach my $assembly_tag (@{$self->{ASSEMBLY_TAG_OBJECTS}}) {
			$assembly_tag->save;
		}
		
		if($result != 1) {
			warn "Problem saving row for $self->{PROJECT}\n";
		}
	}

    return;
}

sub load {
    my ($self) = @_;

	my $load_sql = "SELECT species, accession, run_id, result, errors, comments FROM project WHERE project=?;";
	my $load_dbh = $self->{DBI}->prepare($load_sql);
	$load_dbh->execute($self->{PROJECT});
	my $load_result_ref = $load_dbh->fetchall_arrayref();
	
	if(ref($load_result_ref) eq 'ARRAY' and scalar(@$load_result_ref) == 1 ) {
		$self->{SAVED} = 1; 
		(
			$self->{SPECIES},
			$self->{ACCESSION},
			$self->{RUN_ID},
			$self->{RESULT},
			$self->{ERROR_STRING},
			$self->{COMMENT_STRING},	
		) = @{ $load_result_ref->[0] };
		
		my $load_assembly_tags_sql = "SELECT start, end, type, comment FROM tag WHERE accession = ?;";
		my $load_assembly_tags_dbh = $self->{DBI}->prepare($load_assembly_tags_sql);
		$load_assembly_tags_dbh->execute($self->{ACCESSION});
		my $load_assembly_tags_result_ref = $load_assembly_tags_dbh->fetchall_arrayref();
	
		if(ref($load_assembly_tags_result_ref) eq 'ARRAY') { 
			foreach my $tag_row (@$load_assembly_tags_result_ref) {
	
				my ($saved_start, $saved_end, $saved_type, $saved_comment) = @$tag_row;
	
				my $assembly_tag_object = Hum::AssemblyTag->new({
					component => 	$self->{ACCESSION},
					start => 		$saved_start,
					end => 			$saved_end,
					type => 		$saved_type,
					comment => 		$saved_comment,
					dbi => 			$self->{DBI},
				});
				push(@{$self->{ASSEMBLY_TAG_OBJECTS}}, $assembly_tag_object);
			}
		}
		return 1;
	}
	else {
		return 0;
	}
}

1;

__END__

=head1 NAME - Hum::GapTags::Local

=head1 AUTHOR

James Torrance B<email> jt8@sanger.ac.uk

