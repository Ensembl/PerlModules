
### Hum::TPF::Row::Clone

package Hum::TPF::Row::Clone;

use strict;
use Carp;
use base 'Hum::TPF::Row';
use Hum::Tracking qw{
    prepare_track_statement
    prepare_cached_track_statement
    };
use Hum::Submission 'prepare_statement';
use Hum::SequenceInfo;
use Hum::FastaFileIO;
use Hum::Pfetch 'get_EMBL_entries';

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
    return $self->{'_intl_clone_name'};
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
    $ext_pre ||= 'XX';
    if ($ext_pre =~ /^XX/) {
        $clonename = "$ext_pre-$clonename";
    } else {
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
            if (my $intl = $self->intl_clone_name) {
                my ($intl_prefix, $body) = $intl =~ /^([^-]+)-(.+)$/;
                $intl_prefix ||= '';
                $body        ||= $intl;
                if (my $sang_prefix = $self->get_sanger_prefix($intl_prefix)) {
                    $self->{'_sanger_clone_name'} = $clone = $sang_prefix . $body;
                } else {
                    $self->{'_sanger_clone_name'} = $clone = $body;
                }
            } else {
                # We use the accession as the clone name where intl = '?'
                return $self->accession;
            }
        }
        return $clone;
    }
}

{
    my( %intl_sanger );
    my $init_flag = 0;
    
    sub _init_prefix_hashes {
        my $sth = prepare_track_statement(q{
            SELECT internal_prefix, external_prefix
            FROM library
            });
        $sth->execute;
        my( $sang, $intl );
        $sth->bind_columns(\$sang, \$intl);
        while ($sth->fetch) {
            next unless $sang and $intl;
            next if $intl eq 'XX';
            $intl_sanger{$intl} = $sang;
        }
        $init_flag = 1;
    }
    
    sub get_sanger_prefix {
        my( $self, $intl ) = @_;
        
        _init_prefix_hashes() unless $init_flag;
        return $intl_sanger{$intl};
    }
}

sub contig_name {
    my( $self, $contig_name ) = @_;
    
    if ($contig_name) {
        $self->{'_contig_name'} = $contig_name;
    }
    return $self->{'_contig_name'};
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
    
    return join("\t",
        $self->accession       || '?',
        $self->intl_clone_name || '?',
        $self->contig_name     || '?')
        . "\n";
}

sub store {
    my( $self, $tpf, $rank ) = @_;
    
    confess("row is already stored with id_tpfrow=", $self->db_id)
        if $self->db_id;
    
    $self->store_clone_if_missing($tpf);
    $self->store_SequenceInfo_and_link;
    
    my $db_id = $self->get_next_id_tpfrow;
    my $insert = prepare_cached_track_statement(q{
        INSERT INTO tpf_row(id_tpfrow
              , id_tpf
              , rank
              , clonename
              , contigname)
        VALUES(?,?,?,?,?)
        });
    $insert->execute(
        $self->db_id,
        $tpf->db_id,
        $rank,
        $self->sanger_clone_name,
        $self->contig_name,
        );
}

sub store_clone_if_missing {
    my( $self, $tpf ) = @_;
    
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
    
    # Insert into clone table
    my $insert = prepare_cached_track_statement(q{
        INSERT INTO clone(clonename
              , speciesname
              , sequenced_by
              , funded_by
              , seq_reason
              , is_hsm
              , remark
              , clone_type)
        VALUES(?,?
              , 0,0,1,1
              , 'added by ChromoView'
              , 1)
        });
    $insert->execute(
        $self->sanger_clone_name,
        $tpf->species,
        );
    
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
    unless ($seq_id = $seq->db_id) {
        $seq->store;
        $seq_id = $seq->db_id;
    }
    
    my $check_link = prepare_cached_track_statement(q{
        SELECT 1
        FROM clone_sequence
        WHERE is_current = 1
          AND clonename = ?
          AND id_sequence = ?
        });
    $check_link->execute($clone, $seq->db_id);
    my ($link_ok) = $check_link->fetchrow;
    $check_link->finish;
    
    unless ($link_ok) {
        my $set_not_current = prepare_cached_track_statement(q{
            UPDATE clone_sequence
            SET is_current = 0
            WHERE clonename = ?
            });
        $set_not_current->execute($clone);
        
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


sub get_latest_Sequence_and_SequenceInfo {
    my( $self ) = @_;
    
    # First get from our ftp site, which will be
    # the most recent version.
    $self->_sanger_sequence_get

        # If the ftp site get fails, then get it from our
        # online copy of EMBL in the pfetch server.
        or $self->_embl_sequence_get
        
        # else produce a fatal error
        or confess sprintf("Couldn't get any EMBL entries for '%s'", $self->accession);
}

sub _embl_sequence_get {
    my( $self ) = @_;
    
    my $acc = $self->accession;
    my ($embl) = get_EMBL_entries($acc);
    return unless $embl;

    my $seq = $embl->hum_sequence;
    my $sv  = $embl->SV->version;
    
    my( $seq_inf );
    unless ($seq_inf = Hum::SequenceInfo->fetch_by_accession_sv($acc, $sv)) {
        $seq_inf = Hum::SequenceInfo->new;
        $seq_inf->accession($acc);
        $seq_inf->sequence_version($sv);

        my( $htgs_phase );
        foreach my $word ($embl->KW->list) {
            #warn "KW: $word\n";
            if ($word =~ /HTGS_PHASE(\d)/) {
                $htgs_phase = $1;
                last;
            }
        }
        unless ($htgs_phase) {
            if ($embl->ID->division eq 'HTG') {
                $htgs_phase = 1;
            } else {
                $htgs_phase = 3;
            }
        }

        $seq_inf->htgs_phase($htgs_phase);
    }
    $seq->name("$acc.$sv");
    $seq_inf->Sequence($seq);
    $self->SequenceInfo($seq_inf);
    return 1;
}

{
    my( $sth );

    sub _sanger_sequence_get {
        my( $self ) = @_;

        my $acc = $self->accession;

        my $sth ||= prepare_statement(q{
            SELECT s.sequence_name
              , s.sequence_version
              , s.embl_checksum
              , s.file_path
              , d.htgs_phase
              , a.project_name
            FROM project_acc a
              , project_dump d
              , sequence s
            WHERE a.sanger_id = d.sanger_id
              AND d.seq_id = s.seq_id
              AND d.is_current = 'Y'
              AND a.accession = ?
            });
        $sth->execute($acc);

        my( @seq );
        while (my ($name, $sv, $cksum, $path, $htgs_phase, $proj) = $sth->fetchrow) {
            unless ($sv) {
                warn "sv not set for '$acc' ($name)\n";
                return;
            }

            my $fasta = Hum::FastaFileIO->new_DNA_IO("$path/$name");
            my ($seq) = $fasta->read_one_sequence;

            my( $seq_inf );
            unless ($seq_inf = Hum::SequenceInfo->fetch_by_accession_sv($acc, $sv)) {
                $seq_inf = Hum::SequenceInfo->new;
                $seq_inf->accession($acc);
                $seq_inf->sequence_version($sv);
                $seq_inf->htgs_phase($htgs_phase);
                $seq_inf->projectname($proj);
            }
            
            $seq->name("$acc.$sv");
            $seq_inf->Sequence($seq);

            push(@seq, $seq_inf);
        }

        if (@seq == 1) {
            $self->SequenceInfo($seq[0]);
            return 1;
        }
        elsif (@seq) {
            confess "got ", scalar(@seq), " sequences for accession '$acc'\n";
        }
        else {
            return;
        }
    }
}



1;

__END__

=head1 NAME - Hum::TPF::Row::Clone

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

