
### Hum::TPF::Row::Clone

package Hum::TPF::Row::Clone;

use strict;
use warnings;
use Carp;
use base 'Hum::TPF::Row';
use Hum::Tracking qw{
    prepare_track_statement
    prepare_cached_track_statement
    };
use Hum::Submission 'prepare_statement';
use Hum::SequenceInfo;

sub container_clone {
	my ($self, $container_clone) = @_;
	
    if ($container_clone) {
    	$self->{'_container_clone'} = $container_clone;
    }
	if(exists($self->{'_container_clone'})) {
	    return $self->{'_container_clone'};
	}
	else {
		return undef;
	}
}

sub add_contained_clone {
	my ($self, $contained_clone) = @_;
	
	push(@{$self->{'_contained_clones'}}, $contained_clone);
	
	return;
}

sub get_contained_clones {
	my ($self) = @_;
		
	if(exists($self->{'_contained_clones'}) and ref($self->{'_contained_clones'}) eq 'ARRAY') {
	    return @{$self->{'_contained_clones'}};
	}
	else {
		return ();
	}
}

sub accession {
    my( $self, $accession ) = @_;
    
    if ($accession) {
        if ($accession eq '?') {
            $self->{'_accession'} = undef;
        } else {
            $self->{'_accession'} = $accession;
        }
    }
    return $self->{'_accession'};
}

sub intl_clone_name {
    my( $self, $intl ) = @_;
    
    if ($intl) {
        if ($intl eq '?') {
            $self->{'_intl_clone_name'} = undef;
        } else {
            $self->{'_intl_clone_name'} = $intl;
        }
    }
    if ($self->is_multi_clone) {
        return "Multiple";
    } else {
        return $self->{'_intl_clone_name'};
    }
}

sub current_seq_id {
    my( $self, $current_seq_id ) = @_;
    
    if ($current_seq_id) {
        $self->{'_current_seq_id'} = $current_seq_id;
    }
    return $self->{'_current_seq_id'};
}

sub set_intl_clone_name_from_sanger_int_ext {
    my( $self, $clonename, $int_pre, $ext_pre ) = @_;

    $clonename = uc $clonename;
    $int_pre ||= '';
    $ext_pre ||= '';
    if (
        $ext_pre =~ /^XX/
        or (
            $int_pre eq 'NONE'
            and length($ext_pre) > 0
        )
    ) {
        $clonename = "$ext_pre-$clonename";
    }
    elsif ($ext_pre) {
        substr($clonename, 0, length($int_pre)) = "$ext_pre-";
    }
    $self->intl_clone_name($clonename);
}

sub sanger_clone_name {
    my( $self, $clone ) = @_;
    
    if ($clone) {
        $self->{'_sanger_clone_name'} = $clone;
    } else {
        unless ($clone = $self->{'_sanger_clone_name'}) {
            my $intl = $self->intl_clone_name;
            if (! $intl or $intl =~ /Multiple/i) {
                # We use the accession as the clone name where
                # intl = '?' or where it is "Multiple"
                return $self->accession;
            } else {
                my( $lib );
                ($clone, $lib) = $self->get_sanger_clone_and_libraryname_from_intl_name($intl);
                $self->{'_sanger_clone_name'} = $clone;
                $self->sanger_library_name($lib);
            }
        }
        return $clone;
    }
}

sub sanger_library_name {
    my( $self, $lib_name ) = @_;
    
    if ($lib_name) {
        $self->{'_sanger_library_name'} = $lib_name;
    }
    return $self->{'_sanger_library_name'};
}

{
    my( %intl_sanger, %sanger_info );
    my $init_flag = 0;
    
    sub _init_prefix_hash {
        my $sth = prepare_track_statement(q{
            SELECT libraryname
              , internal_prefix
              , external_prefix
              , first_plate
              , last_plate
            FROM library
            ORDER BY libraryname
              , first_plate
            });
        $sth->execute;
        my( $libname, $sang, $intl, $first, $last );
        $sth->bind_columns(\$libname, \$sang, \$intl, \$first, \$last);
        while ($sth->fetch) {
            next unless $sang and $intl;
			if($sang eq 'NONE') {$sang = ''}
            if ($intl =~ /^XX/) {
                my $uc_sang = uc $sang;
                if ($sanger_info{$uc_sang}) {
                    # If more than one XX* library shares a Sanger prefix, we can't use it.
                    delete($sanger_info{$uc_sang});
                } else {
                    $sanger_info{$uc_sang} = [$sang, $libname];
                }
            } else {
                my $lib_info = $intl_sanger{$intl} ||= [];
                push(@$lib_info, [$sang, $libname, $first, $last]);
            }
        }
        $init_flag = 1;
    }
    
    sub get_sanger_clone_and_libraryname_from_intl_name {
        my( $self, $intl ) = @_;
        
        _init_prefix_hash() unless $init_flag;
        
        ### Tread XX* clones differently - should be able
        ### to just knock off the XX- prefix, but make an
        ### attempt to identify the library from the start
        ### of the remaining name.
        if (defined($intl) and $intl =~ /^XX.*-(.+)/) {
            my $rest = $1;
            if (my ($prefix) = $rest =~ /^([A-Za-z]+)/) {
                if (my $info = $sanger_info{uc $prefix}) {
                    my ($sanger, $libname) = @$info;
                    substr($rest, 0, length($sanger)) = $sanger;
                    return($rest, $libname);
                }
            }
            return $rest;
        } else {

            my ($intl_prefix, $plate, $rest);
            if(defined($intl)) {($intl_prefix, $plate, $rest) = $intl =~ /^([^-]+)-(\d*)(.+)$/;}
            $intl_prefix ||= '';
            $plate       ||= '';
            if(!defined($intl)) {$intl = ''};
            if(!defined($rest)) {$rest = $intl};
            if (my $lib_info = $intl_sanger{$intl_prefix}) {
                if ($plate) {
                    foreach my $inf (@$lib_info) {
                        my ($sang, $libname, $first, $last) = @$inf;
                        if ($plate >= $first and $plate <= $last) {
                            return($sang . $plate . $rest, $libname);
                        }
                    }
                    warn "Couldn't place plate from '$intl' in any of:\n",
                        map "  [@$_]\n", @$lib_info;
                }
                # Just take the first
                my ($sang, $libname) = @{$lib_info->[0]};
                return($sang . $plate . $rest, $libname);
            } else {
                return($plate . $rest);
            }
        }
    }
}

sub project_status_history_includes {
    my ($self, @accept_status) = @_;
    # Joined through clone_project.  Used for QC status check.

    my $placeholders = # e.g. '?,?,?'
      join ',', ('?') x @accept_status;
    my $sth = prepare_cached_track_statement(qq{
        SELECT cp.*, statusdate
        FROM project_status ps, clone_project cp
        WHERE ps.projectname = cp.projectname
        AND cp.clonename = ?
        AND status in ($placeholders)
        /* nb. no test for ps.iscurrent=1 */
    });
    $sth->execute(scalar $self->sanger_clone_name, @accept_status);
    my $rows = $sth->fetchall_arrayref;
# use YAML; warn Dump({ scalar $self->sanger_clone_name, $rows });
    return @$rows ? 1 : 0;
}


sub contig_name {
    my( $self, $contig_name ) = @_;
    
    if ($contig_name) {
        $self->{'_contig_name'} = $contig_name;
    }
    return $self->{'_contig_name'};
}

sub is_multi_clone {
    my( $self, $flag ) = @_;
    
    if (defined $flag) {
        $self->{'_is_multi_clone'} = $flag ? 1 : 0;
    }
    return $self->{'_is_multi_clone'} || 0;
}


sub SequenceInfo {
    my( $self, $seq ) = @_;
    
    if ($seq) {
        confess "empty SequenceInfo" unless keys %$seq;
        $self->{'_SequenceInfo'} = $seq;
    } else {
        $seq = $self->{'_SequenceInfo'};
        unless ($seq) {
            if (my $inf_db_id = $self->current_seq_id) {
                $seq = $self->{'_SequenceInfo'} =
                    Hum::SequenceInfo->fetch_by_db_id($inf_db_id);
            }
        }
    }
    return $seq;
}

sub string {
    my( $self ) = @_;

    my @fields = (
                  $self->accession       || '?',
                  $self->intl_clone_name || '?',
                  $self->contig_name     || '?',
        );
    if (my $txt = $self->remark) {
        push(@fields, $txt);
    }
    return join("\t", @fields) . "\n";
}

sub store {
    my( $self, $tpf, $rank ) = @_;
    
    confess("row is already stored with id_tpfrow=", $self->db_id)
        if $self->db_id;
    
    $self->store_clone_if_missing($tpf->species);
    $self->store_SequenceInfo_and_link;
    
    my $db_id = $self->get_next_id_tpfrow;
    my $insert = prepare_cached_track_statement(q{
        INSERT INTO tpf_row(id_tpfrow
              , id_tpf
              , rank
              , clonename
              , contigname
              , remark)
        VALUES(?,?,?,?,?,?)
        });
    $insert->execute(
        $self->db_id,
        $tpf->db_id,
        $rank,
        $self->sanger_clone_name,
        $self->contig_name,
        $self->remark,
        );
}

sub store_clone_if_missing {
    my( $self, $species ) = @_;
    
    my $upper = uc $self->sanger_clone_name;
    my $get_clone = prepare_cached_track_statement(q{
        SELECT clonename
        FROM clone
        WHERE upper(clonename) = ?
        });
    $get_clone->execute($upper);
    my ($db_clonename) = $get_clone->fetchrow;
    $get_clone->finish;
    
    if ($db_clonename) {
        $self->sanger_clone_name($db_clonename);
        return;
    }
    
    my $remark = 'added by ChromoView';
    if ($self->is_multi_clone) {
        $remark = 'MULTIPLE: placeholder for sequence from multiple clones';
    }
    elsif (! $self->intl_clone_name) {
        $remark = 'UNKNOWN: placeholder for sequence from unknown clone';
    }
    elsif (my ($actual, $part) = $self->intl_clone_name =~ /(.+)__([^_])$/) {
        $remark = "SUFFIX: placeholder for sequence '$part' from clone '$actual'";
    }
    
    # Insert into clone table
    my $insert = prepare_cached_track_statement(q{
        INSERT INTO clone(clonename
              , libraryname
              , speciesname
              , remark
              , sequenced_by
              , funded_by
              , seq_reason
              , is_hsm
              , clone_type)
        VALUES(?,?,?,?,0,0,1,1,1)
        });
    $insert->execute(
        $self->sanger_clone_name,
        $self->sanger_library_name,
        $species,
        $remark,
        );
    
    printf STDERR "Added clone  %14s  %s\n",
        $self->sanger_clone_name,
        $remark;
    
    # and into clone status
    my $status_insert = prepare_cached_track_statement(q{
        INSERT INTO clone_status(clonename
              , status)
        VALUES(?,1)
        });
    $status_insert->execute($self->sanger_clone_name);
}

sub store_SequenceInfo_and_link {
    my( $self ) = @_;
    
    my $clone     = $self->sanger_clone_name;
    my $accession = $self->accession;
    
    my $seq = $self->SequenceInfo;
    unless ($seq) {
        return unless $accession;
        
        $seq = Hum::SequenceInfo->fetch_latest_by_accession($accession)
            or confess "No SequenceInfo for accession '$accession'";
        $self->SequenceInfo($seq);
    }
    
    my( $seq_id );
    if ($seq_id = $seq->db_id) {
        $seq->update_htgs_phase;
    } else {
        $seq->store;
        $seq_id = $seq->db_id;
    }
    
    my $check_link = prepare_cached_track_statement(q{
        SELECT is_current
        FROM clone_sequence
        WHERE clonename = ?
          AND id_sequence = ?
        });
    $check_link->execute($clone, $seq_id);
    my ($current) = $check_link->fetchrow;
    $check_link->finish;
    
    unless ($current) {
        my $set_not_current = prepare_cached_track_statement(q{
            UPDATE clone_sequence
            SET is_current = 0
            WHERE clonename = ?
            });
        $set_not_current->execute($clone);
        
        if (defined($current) and $current == 0) {
            # There is already a row in the table, so just set it to current
            my $set_current = prepare_cached_track_statement(q{
                UPDATE clone_sequence
                SET is_current = 1
                WHERE clonename = ?
                  AND id_sequence = ?
                });
            $set_current->execute($clone, $seq_id);
        } else {
            # Put a new row in the table
            my $insert = prepare_cached_track_statement(q{
                INSERT INTO clone_sequence( clonename
                      , id_sequence
                      , entrydate
                      , is_current )
                VALUES (?,?,sysdate,1)
                });
            $insert->execute($clone, $seq_id);
        }
    }
}

sub get_latest_Sequence_and_SequenceInfo {
    my( $self ) = @_;
    
    my $inf = Hum::SequenceInfo
        ->fetch_latest_with_Sequence($self->accession);
    unless ($inf) {
        confess sprintf("Couldn't get any EMBL entries for '%s'", $self->accession);
    } else {
        $self->SequenceInfo($inf);
    }
}

1;

__END__

=head1 NAME - Hum::TPF::Row::Clone

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

