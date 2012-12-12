
### Hum::GapTags

package Hum::GapTags::Submissions;

use strict;
use warnings;
use Carp;
use Hum::Submission qw{seq_id_from_project_name accession_from_project_name species_from_project_name};
use Hum::GapTags;
use Hum::AssemblyTag::Submissions;

use vars qw( @ISA );

@ISA = 'Hum::GapTags';

sub new {
	my $type = shift;
	my $class = ref $type || $type;
	my $self = $class->SUPER::new(@_);
	$self->{ASSEMBLY_TAG_SUBCLASS} = 'Hum::AssemblyTag::Submissions';
	return $self;
}

sub component_for_assembly_tag {
	my ($self) = @_;
	return $self->seq_id;
}

sub seq_id {
	my ($self) = @_;
	
	if(!exists($self->{SEQ_ID}) or !defined($self->{SEQ_ID})) {
		$self->{SEQ_ID} = seq_id_from_project_name($self->{PROJECT})
	}
	
	return $self->{SEQ_ID};
}

sub save {
    my ($self) = @_;

	if(!$self->{SAVED}) {
		if(defined($self->seq_id)) {
		
			my $save_sql = "INSERT INTO assembly_tag_processing (seq_id, result, errors, comments) VALUES (?,?,?,?);";
			my $save_dbh = $self->{DBI}->prepare($save_sql);
			my $result = $save_dbh->execute(
				$self->seq_id,
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
		else {
			warn "Cannot find seq ID for $self->{PROJECT}\n";
		}
	}

    return;
}

sub load {
    my ($self) = @_;

	my $load_sql = "SELECT result, errors, comments FROM assembly_tag_processing WHERE seq_id=?;";
	my $load_dbh = $self->{DBI}->prepare($load_sql);
	$load_dbh->execute($self->seq_id);
	my $load_result_ref = $load_dbh->fetchall_arrayref();
	
	if(ref($load_result_ref) eq 'ARRAY' and scalar(@$load_result_ref) == 1 ) {
		$self->{SAVED} = 1; 
		(
			$self->{RESULT},
			$self->{ERROR_STRING},
			$self->{COMMENT_STRING},	
		) = @{ $load_result_ref->[0] };
		
		$self->{ACCESSION} = accession_from_project_name($self->{PROJECT});
		$self->{SPECIES} = species_from_project_name($self->{PROJECT});
		
		my $load_assembly_tags_sql = "SELECT start, end, type, comment FROM assembly_tag WHERE seq_id = ?;";
		my $load_assembly_tags_dbh = $self->{DBI}->prepare($load_assembly_tags_sql);
		$load_assembly_tags_dbh->execute($self->seq_id);
		my $load_assembly_tags_result_ref = $load_assembly_tags_dbh->fetchall_arrayref();
	
		if(ref($load_assembly_tags_result_ref) eq 'ARRAY') { 
			foreach my $tag_row (@$load_assembly_tags_result_ref) {
	
				my ($saved_start, $saved_end, $saved_type, $saved_comment) = @$tag_row;
	
				my $assembly_tag_object = Hum::AssemblyTag->new({
					component => 	$self->seq_id,
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

=head1 NAME - Hum::GapTags::Submissions

=head1 AUTHOR

James Torrance B<email> jt8@sanger.ac.uk

