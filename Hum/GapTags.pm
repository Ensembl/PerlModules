
### Hum::GapTags

package Hum::GapTags;

use strict;
use warnings;
use Carp;
use Cwd;
use Hum::Tracking qw{prepare_track_statement find_project_directories project_type};
use Hum::AssemblyTag;
use Hum::FileUtils qw{system_with_separate_stdout_and_stderr_using_sed};
use Hum::Pfetch qw{get_EMBL_entries};
use Hum::CloneProject qw{fetch_clonename_from_projectname};

sub new {
    my ($pkg, $arg_ref) = @_;

    my @required_variables = qw(project);
	my @optional_variables = qw(dbi run_id clonename gap_type project_directory);
    
	foreach my $required_variable (@required_variables) {
		if(!exists($arg_ref->{$required_variable})) {
			die "$required_variable required for $pkg\n";
		}
	}

	my $self = {
		ASSEMBLY_TAG_OBJECTS=>[],
		ERROR_STRING=>'',
		COMMENT_STRING=>'',
		RESULT => undef,
		SAVED => 0,
	};
		
	foreach my $variable (@required_variables) {
		if(exists($arg_ref->{$variable})) {
			$self->{uc($variable)} = $arg_ref->{$variable};
		}
		else {
			$self->{uc($variable)} = '';
		}
	}
	
	foreach my $variable (@optional_variables) {
		if(exists($arg_ref->{$variable})) {
			$self->{uc($variable)} = $arg_ref->{$variable};
		}
		else {
			$self->{uc($variable)} = undef;
		}
	}

    bless($self, $pkg);

	# Load from database if it pre-exists
	if(exists($self->{DBI}) and defined($self->{DBI})) {
		$self->load;
	} 

	# Load accession, which will register an error if it's not a Sanger accession
	$self->accession;
    
    return $self;
}

sub new_from_db {
	my ($pkg, $arg_ref) = @_;
	
	my @required_variables = qw(project dbi);

	my $self = {
		ASSEMBLY_TAG_OBJECTS=>[],
		ERROR_STRING=>'',
		COMMENT_STRING=>'',
		RESULT => undef,
		SAVED => 0,
	};
		
	foreach my $variable (@required_variables) {
		if(exists($arg_ref->{$variable})) {
			$self->{uc($variable)} = $arg_ref->{$variable};
		}
		else {
			$self->{uc($variable)} = '';
		}
	}
	
	bless($self, $pkg);
	if($self->load) {
		return $self;
	}
	else {
		return undef;
	}
}

sub get_all_saved_project_names {
	my ($pkg, $dbi) = @_;

	my $project_sql = "SELECT distinct(project) FROM project;";
	my $project_dbh = $dbi->prepare($project_sql);
	$project_dbh->execute();
	my $project_result_ref = $project_dbh->fetchall_arrayref();
	my @project_names;
	foreach my $row (@$project_result_ref) {
		push(@project_names, $row->[0]);
	}
	
	return @project_names;
}

sub add_comment {
	my ($self, $comment) = @_;
	
	$self->{COMMENT_STRING} .= $comment . "\n";
	warn "$comment\n";
	
	return;
}

sub report_error {
	my ($self, $result, $error) = @_;
	
	# Only the first result is recorded
	if(!defined($self->{RESULT})) {
		$self->{RESULT} = $result;
	}
	
	$self->{ERROR_STRING} .= $error . "\n";
        my $proj = $self->{PROJECT};
	warn "project $proj: $error\n";
	
	return;
}

sub line_break_symbol {
	my ($self) = @_;
	
	my %symbol_for_gap_type = (
		'GAP4' => '\*',
		'GAP5' => '%0a',
	);
	
	my $symbol = $symbol_for_gap_type{$self->gap_type};
	return qr/(?<!\[)$symbol/;
}

sub process_coordinates {
	my ($self) = @_;
	
	if(
		scalar @{$self->{ASSEMBLY_TAG_OBJECTS}} > 0
		and (
			!defined($self->{LEFT_COORDINATE})
			or !defined($self->{RIGHT_COORDINATE})
		)
	) {
		# If we can't determine the coordinates, return no assembly tags
		$self->report_error('No end coordinates', 'No end coordinates');
		$self->{ASSEMBLY_TAG_OBJECTS} = [];
	}

	# If the coordinates are in the usual orientation, 	
	foreach my $assembly_tag_object (@{$self->{ASSEMBLY_TAG_OBJECTS}}) {
		if($self->{LEFT_COORDINATE} < $self->{RIGHT_COORDINATE}) {			
			$assembly_tag_object->offset($self->{LEFT_COORDINATE});
		}
		else {
			$assembly_tag_object->flip($self->{LEFT_COORDINATE});
		}
	}

	my $finished_length = abs($self->{RIGHT_COORDINATE} - $self->{LEFT_COORDINATE}) + 1;
	
	if(!defined($self->oracle_length)) {
		$self->report_error('No oracle clone length', "Length $finished_length from gap database not in agreement with Oracle length, undefined");
		$self->{ASSEMBLY_TAG_OBJECTS} = [];
	}
	elsif($finished_length != $self->oracle_length) {
		$self->report_error('Gap length wrong', "Length $finished_length from gap database not in agreement with Oracle length " . $self->oracle_length);
		$self->{ASSEMBLY_TAG_OBJECTS} = [];
	}
	
	@{$self->{ASSEMBLY_TAG_OBJECTS}} = grep {
		$_->start > 0 and $_->end <= $finished_length
	} @{$self->{ASSEMBLY_TAG_OBJECTS}};
	
	# Eliminate objects with redundant coordinates
	$self->eliminate_redundant_tags;
	
	return;
}

sub eliminate_redundant_tags {
	my ($self) = @_;
	
	my %used_locations;
	foreach my $tag_object ( @{$self->{ASSEMBLY_TAG_OBJECTS}}) {
		my $location_string = $tag_object->start . "-" . $tag_object->end;
		if(exists($used_locations{$location_string})) {
			my $longer_tag = length($tag_object->comment) > length($used_locations{$location_string}->comment) ? $tag_object :  $used_locations{$location_string};
			$used_locations{$location_string} = $longer_tag;
		}
		else {
			$used_locations{$location_string} = $tag_object;
		}
	}
	
	# Only disrupt the ordering if you've edited anything out
	if(scalar(values(%used_locations)) < scalar @{$self->{ASSEMBLY_TAG_OBJECTS}}) {
		@{$self->{ASSEMBLY_TAG_OBJECTS}} = sort {
			$a->start <=> $b->start
		} values %used_locations;
	}
	
	return;
}

sub flip_coordinates {
	my ($self) = @_;
	
	if(
		scalar @{$self->{ASSEMBLY_TAG_OBJECTS}} > 0
		and !defined($self->{LEFT_COORDINATE})
	) {
		die "No left coordinate determined\n";
	}
	
	foreach my $assembly_tag_object (@{$self->{ASSEMBLY_TAG_OBJECTS}}) {
		$assembly_tag_object->flip($self->{LEFT_COORDINATE});
	}
	
	return;
}

sub store_assembly_tag_object {
	my ($self, $assembly_tag) = @_;
	
	push(@{$self->{ASSEMBLY_TAG_OBJECTS}}, $assembly_tag);
	
	return;
}

sub get_assembly_tags {
	my ($self) = @_;

	if(!$self->{SAVED}) {
		return if(defined($self->{RESULT})); # If there's already an error, don't try to get the gap tag data
		
		my @embl_misc_features;
		foreach my $gap_tag ($self->raw_gap_tags) {
			$self->gap_tag_to_object($gap_tag);
		}
		
		$self->process_coordinates();
	}
	
	if(!defined($self->{RESULT})) {
		$self->{RESULT} = 'Ok';
	}
	
	if($self->{RESULT} eq 'Ok') {
		return @{$self->{ASSEMBLY_TAG_OBJECTS}};
	}
	else {
		return;
	}

}

sub gap_tag_to_object {
	my ($self, $gap_tag) = @_;

	# Skip header or empty lines
	if($gap_tag =~ /^CN:/ or $gap_tag =~ /^\s*$/) {
		return;
	}

	# If the line starts "ERROR", report an error!
	if($gap_tag =~ /^ERROR:?\s*(.*)$/i) {
		my $error_string = $1;
		$self->report_error('Error extracting data from gap', $error_string);
	}
	
	my ($type, $value, $start, $contig, $length, $unpadded_start, $in_cutoff, $undef_base, $unpadded_length, $wwraid) = split(/\^/, $gap_tag);

	if(
		defined($unpadded_start)
		and defined($unpadded_length)
		and $unpadded_start =~ /^\d+/
		and $unpadded_length =~ /^\d+/
	) {
		if($type eq 'ANNO') {
			my $end = $unpadded_start + $unpadded_length - 1;
			my ($embl_format_comment, $type) = $self->gap_tag_value_to_embl_comment_and_type($value);
			if($embl_format_comment or $type) {
				if(defined($self->component_for_assembly_tag)) {
					my $assembly_tag_object = $self->{ASSEMBLY_TAG_SUBCLASS}->new({
						start => $unpadded_start,
						end => $end,
						comment => $embl_format_comment,
						type => $type,
						component => $self->component_for_assembly_tag,
						dbi => $self->{DBI},
					});
					$self->store_assembly_tag_object($assembly_tag_object);
				}
				else {
					$self->report_error('No component for assembly tag', 'Cannot determine component identifier for assembly tag');
				}
			}
		}
		elsif ($type =~ /^FIN[LR]$/) {
			my ($tag_clonename) = split(/\s+/, $value);
			if ($type eq 'FINL' and $self->clonename =~ /^$tag_clonename$/i ) {	# Handle left ends
				$self->{LEFT_COORDINATE} = $unpadded_start;
			}
			elsif ($type eq 'FINR' and $self->clonename =~ /^$tag_clonename$/i ) {	# Handle right ends
				$self->{RIGHT_COORDINATE} = $unpadded_start;
			}
		}
	}
	else {
		$self->report_error('Cannot parse gap file', "Cannot parse $gap_tag");
	}

	return;
	
}

sub gap_tag_value_to_embl_comment_and_type {
	my ($self, $gap_tag_value) = @_;
	
	my %tick_box_labels_to_display = (
		 'Tandem repeat' => 1,
		 'Single clone region' => 1,
		 'Forced join' => 1,
	);
	
	my @gap_tag_lines = split($self->line_break_symbol, $gap_tag_value);
	my $embl_text;
	my $type;
	my $comment_flag = 0;
	my $comment_text;
	my $tick_box_flag;
	foreach my $gap_tag_line (@gap_tag_lines) {
		if($gap_tag_line =~ /\[\s*(.)\s*\]\s?(\S.*)/) {
			$tick_box_flag = 1;
			my $tick_box_contents = $1;
			my $tick_box_label = $2;
			
			if($tick_box_contents =~ /^(\*|x|\+)$/i) {
				if(exists($tick_box_labels_to_display{$tick_box_label})) {
					$embl_text .= "$tick_box_label. ";
				}
				if($tick_box_label eq 'Misc_feature') {
					$type = 'misc_feature';
				}
				elsif($tick_box_label eq 'Unsure') {
					$type = 'unsure';
				}
			}
			elsif($tick_box_contents !~ /^ $/) {
				$self->add_comment("Unusual tick box contents: $tick_box_contents");
			}
		}
		elsif($gap_tag_line =~ /Add a comment here( -)?\s*(.*)$/i) {
			if(length($2) > 0) {
				$comment_text = $2;
			}
			$comment_flag = 1;
		}
		elsif($comment_flag and length($gap_tag_line) > 0) {
			if(defined($comment_text)) {
				$comment_text .= " $gap_tag_line";
			}
			else {
				$comment_text = $gap_tag_line;
			}
		}
	}
	
	# If there are tick-boxes, but this is neither a misc-feature nor an "unsure", record an error
	if($tick_box_flag and !defined($type)) {
		$self->report_error('Bad tick box format', "No misc_feature or unsure ticked in $gap_tag_value");
	}
	
	# If there are no tick-boxes, parse things differently, assuming everything is a comment
	if(!$tick_box_flag) {
		$type = 'misc_feature';
		$comment_text = undef;
		foreach my $gap_tag_line (@gap_tag_lines) {
			if(defined($comment_text)) {
				$comment_text .= " $gap_tag_line";
			}
			else {
				$comment_text = $gap_tag_line;
			}
		}
	}
	
	if(defined($comment_text) and $comment_text !~ /^\s*\(?null\)?\s*$/) {
		$embl_text .= $comment_text;
	}

	# Process and (in some cases) throw warnings about odd comments
	if(defined($embl_text)) {
		# Correct double-spaces
		$embl_text =~ s/  / /g;
		# Eliminate tabs
		$embl_text =~ s/\t//g;
		
		if($embl_text =~ /unsure/i) {
			$self->add_comment("Possible unsure tag mislabelled as misc_feature: $embl_text");
		}
		#if($embl_text =~ /\W\d{2,}\W/) {
		if($embl_text =~ /(\d{2,}\.{2,}|(from|to)(\s+pos\S*)?|(from|to)?(\s*pos\S*))\s*\d+/) {
			$self->report_error('Possible coordinates in comment', $embl_text);
		}
	}
	elsif(defined($type)) {
		$embl_text = '';
	}

	# If the embl-text is empty and this is a misc-feature, comment on the issue and return nothing
	if($type eq 'misc_feature' and $embl_text =~ /^\s*$/) {
		$self->add_comment("No comment contained in the following misc_feature, so it is being ignored: $gap_tag_value");
		return undef;
	}

	# Return a value only if this was a misc-feature or "unsure" case. 
	if(defined($type)) {	
		return ($embl_text, $type);
	}
	else {
		return undef;
	}
}

our $accession_sth;
sub accession {
	my ($self) = @_;
	
	if(!exists($self->{ACCESSION})) {
		
		$self->{ACCESSION} = undef;
		$self->{LENGTH} = undef;
		
		if(!defined($accession_sth)) {
			my $sql = q{
				SELECT s.accession,
					s.sv,
					s.length
	        	FROM clone_sequence cs,
	        	  sequence s
	        	WHERE cs.id_sequence = s.id_sequence
	        	  AND cs.is_current = 1
	        	  AND s.projectname = ?
			};

	    	$accession_sth = prepare_track_statement($sql);
		}
	    $accession_sth->execute($self->{PROJECT});
	    my $accession_result_ref = $accession_sth->fetchall_arrayref;
	    if(
	    	defined($accession_result_ref)
	    	and ref($accession_result_ref) eq 'ARRAY'
	    	and scalar(@$accession_result_ref) == 1
	    	and scalar(@{$accession_result_ref->[0]}) == 3
	    ) {
	    	my($accession, $sv, $length) = @{$accession_result_ref->[0]};
	
			my @split_accessions = qw(
				AL591050	AL663122	AL663123
				AL358012	AL663120	AL663121
				AL357044	AL591291	AL591292
				AL451068	AL672237	AL672238
				AL355992	AL591897	AL591898
				AL390757	AL591343	AL591344
				AL135840	AL357412	AL357413
				AL589913	AL591183	AL591184
				AL139007	AL512564	AL512565
				AL161434	AL445568	AL445569
				AL445924	AL671966	AL671967
				AL132653	CR383701	CR383702
				AL139226	AL389874	AL389875
				AL022330	AL390209	AL390210
				AL009049	CR381707	CR381709
				AL022302	CR383703	CR383704
				AL590366	AL663118	AL663119
				AL391496	AL450448	AL450449
				AL121824	AL162911	AL162912
				AL050304	AL669904	AL645812
				AL035553	AL139228	AL139229
				AL512845	AL592159	AL592163
				AL138967	AL449183	AL449184
				AL590042	AL627209	AL627210
			);
			my %is_split_accession = map {$_=>1} @split_accessions;
			if(exists($is_split_accession{$accession})) {
				$self->report_error('Split accession', "Temporarily excluding split-finished accessions");
				$self->{ACCESSION} = undef;
				return;
			}
	
			# Is this the Sanger accession?
			if($self->is_sanger_accession($accession)) {
				$self->{ACCESSION} = "$accession.$sv";
				$self->{LENGTH} = $length;
			}
	    }
	    else {
	    	$self->report_error('No unique accession', "Cannot identify a unique accession from CASP.");
	    }
	} 

	return $self->{ACCESSION};	
}

sub clonename {
	my ($self) = @_;
	
	# Get clone name if not defined
	if(!exists($self->{CLONENAME}) or !defined($self->{CLONENAME})) {
		$self->{CLONENAME} = fetch_clonename_from_projectname($self->{PROJECT});
	}
	return $self->{CLONENAME};
}

our $organisation_sth;
sub organisation {
	my ($self) = @_;
	
	if(!exists($self->{ORGANISATION})) {
		$self->{ORGANISATION} = undef;
		$self->{SPECIES} = undef;
		
		if(!defined($organisation_sth)) {
			my $organisation_sql = q{
	        	SELECT 
	        	  O.orgtitle,
	        	  C.speciesname
	        	FROM
	        	  clone C,
	        	  organisation O,
	        	  clone_project CP
	        	WHERE
	        	  C.sequenced_by = O.id_org
	        	  AND C.clonename = CP.clonename
	        	  AND CP.projectname=?
	        	};
			$organisation_sth = prepare_track_statement($organisation_sql);
		}
	
	    $organisation_sth->execute($self->{PROJECT});
	    my $organisation_result_ref = $organisation_sth->fetchrow_arrayref;
		
		if(defined($organisation_result_ref) and ref($organisation_result_ref) eq 'ARRAY' and scalar(@$organisation_result_ref) == 2) {
	    	($self->{ORGANISATION}, $self->{SPECIES}) = @$organisation_result_ref; 
	    }
	} 
	
	return $self->{ORGANISATION};
}

sub is_sanger_accession {
	my ($self, $accession) = @_;
	
	# Check the "sequenced by" entry in the Clone table
	my $organisation = $self->organisation;
	unless(
		defined($organisation)
		and $organisation eq 'Sanger Centre'
	) {
		$self->report_error('Not a Sanger clone', "sequenced_by value in Clone table suggests that this is not a Sanger clone");
		return 0;
	}
		
	# Try EMBL entry
	my ($embl_entry) = get_EMBL_entries($accession);
	if(!defined($embl_entry)) {
		$self->report_error('Not a Sanger clone', "Cannot obtain ENA entry to confirm whether this is a Sanger clone");
		return 0;
	}

	foreach my $reference ($embl_entry->Reference) {
		foreach my $location ($reference->locations) {
			if($location =~ /Sanger/i) {
				return 1;
			}
		}
	}
	
	$self->report_error('Not a Sanger clone', "Cannot find reference to Sanger in RL lines of ENA entry");
		
	return 0;
}

sub oracle_length {
	my ($self) = @_;

	if(!exists($self->{LENGTH})) {
		$self->accession;
	}
	
	return $self->{LENGTH};
	
}

sub species {
	my ($self) = @_;

	if(!exists($self->{SPECIES})) {
		$self->organisation;
	}
	
	return $self->{SPECIES};
	
}

sub result {
	my ($self) = @_;

	return $self->{RESULT};
	
}

sub run_id {
	my ($self) = @_;

	return $self->{RUN_ID};
}


sub project_directory {
	my ($self, $new_value) = @_;

	if($new_value) {
		$self->{PROJECT_DIRECTORY} = $new_value;
	}
	elsif(!exists($self->{PROJECT_DIRECTORY}) or !defined($self->{PROJECT_DIRECTORY})) {
		my $dir_find = find_project_directories($self->{PROJECT});
    	$self->{PROJECT_DIRECTORY} = $dir_find->{$self->{PROJECT}};
    	if (!defined($self->{PROJECT_DIRECTORY})) {
    		$self->report_error("Cannot find project directory", "Cannot find project directory");
    	}
	}
		
	return $self->{PROJECT_DIRECTORY};
}

sub gap_type {
	my ($self, $new_value) = @_;

	if($new_value) {
		if($new_value !~ /^(GAP4|GAP5)$/) {
			$self->report_error('Cannot determine gap database type', "Gap type specified was $new_value");
			$self->{GAP_TYPE} = undef;
		}
		else {
			$self->{GAP_TYPE} = $new_value;
		}
	}
	elsif((!exists($self->{GAP_TYPE}) or !defined($self->{GAP_TYPE})) and defined($self->project_directory)) {
	    my $oracle_project_type = Hum::Tracking::project_type($self->{PROJECT});
 
	    my %oracle_project_type_to_gap_version = (
	    	'GAP4' => 'GAP4',
	    	'POOLED' => 'UNCERTAIN',
	    	'MULTIPLEXED' => 'GAP5',
	    );	
	
		if(exists($oracle_project_type_to_gap_version{$oracle_project_type})) {
			$self->{GAP_TYPE} = $oracle_project_type_to_gap_version{$oracle_project_type};
		}	
		else {
			$self->report_error('Cannot determine gap database type', "Cannot determine gap version for oracle project type $oracle_project_type");
		}
		
		# If this is uncertain, do a further check
		if($self->{GAP_TYPE} eq 'UNCERTAIN') {
			my $gap4_file = $self->project_directory . "/" . uc($self->{PROJECT}) . ".0";
			my $gap5_file = $self->project_directory . "/$self->{PROJECT}.0.g5d";
			if(-e $gap4_file and !-e $gap5_file) {
				$self->{GAP_TYPE} = 'GAP4';
			}
			elsif (!-e $gap4_file and -e $gap5_file) {
				$self->{GAP_TYPE} = 'GAP5';
			}
			else {
				$self->{GAP_TYPE} = undef;
				$self->report_error('Cannot determine gap database type', "Files in project directory are not purely gap4 or gap5");
			}
		}
	}

	return $self->{GAP_TYPE};
	
}

our $international_name_sth;
sub sanger_name_to_international_name {
	my ($self, $sanger_name) = @_;
	
	if(!defined($international_name_sth)) {
		my $sql = q{
        	SELECT 
        	  l.internal_prefix
        	  , l.external_prefix
        	FROM
        	  clone c
        	  , library l
        	WHERE
        	  c.libraryname = l.libraryname
        	  AND c.clonename=?
        	};
		$international_name_sth = prepare_track_statement($sql);
	}

	my $international_name;

    $international_name_sth->execute($sanger_name);
    my $library_result_ref = $international_name_sth->fetchrow_arrayref;
    if(defined($library_result_ref) and ref($library_result_ref) eq 'ARRAY' and scalar(@$library_result_ref) == 2) {
    	my($int_pre, $ext_pre) = @$library_result_ref;
		$international_name = $self->set_intl_clone_name_from_sanger_int_ext($sanger_name, $int_pre, $ext_pre);
    } 

	return $international_name;	
}

sub set_intl_clone_name_from_sanger_int_ext {
    my( $self, $clonename, $int_pre, $ext_pre ) = @_;

    $clonename = uc $clonename;
    $int_pre ||= '';
    $ext_pre ||= '';
    if ($ext_pre =~ /^XX/ or $int_pre eq 'NONE') {
        $clonename = "$ext_pre-$clonename";
    }
    elsif ($ext_pre) {
        substr($clonename, 0, length($int_pre)) = "$ext_pre-";
    }
    return $clonename;
}


sub raw_gap_tags {
	my ($self) = @_;
	
	if(!exists($self->{RAW_GAP_TAGS}) or !defined($self->{RAW_GAP_TAGS})) {
	
		$self->{RAW_GAP_TAGS} = [];
	
		my $gap_tag_listref;
		my $error_listref;
	
		if(defined($self->gap_type) and defined($self->project_directory)) {
			if($self->gap_type eq 'GAP4') {
				my $old_working_dir = cwd();
				chdir($self->project_directory);
				($gap_tag_listref, $error_listref) = system_with_separate_stdout_and_stderr_using_sed("/software/badger/bin/get_tag_data -anno -p $self->{PROJECT}");
				chdir($old_working_dir);
			}
			elsif($self->gap_type eq 'GAP5') {
				($gap_tag_listref, $error_listref) = system_with_separate_stdout_and_stderr_using_sed("/software/badger/bin/get_tag_data5 -anno " . $self->project_directory . "/$self->{PROJECT}.0");
			}
	
			# Eliminate lock file warnings.
			@$error_listref = grep(!/WARNING! Database has lock file, but is no longer in use./, @$error_listref);
	
			if(scalar @$error_listref > 0) {
				$self->report_error('Error extracting data from gap', join("", @$error_listref));
				 
			}
			else {
				chomp @$gap_tag_listref;	
				$self->{RAW_GAP_TAGS} = $gap_tag_listref;
			}
		}
	}  
	
	return @{$self->{RAW_GAP_TAGS}};
}

1;

__END__

=head1 NAME - Hum::GapTags

=head1 AUTHOR

James Torrance B<email> jt8@sanger.ac.uk

