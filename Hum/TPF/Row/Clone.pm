
### Hum::TPF::Row::Clone

package Hum::TPF::Row::Clone;

use strict;
use base 'Hum::TPF::Row';
use Hum::Tracking qw{
    prepare_track_statement
    prepare_cached_track_statement
    };
use Carp;

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

sub set_intl_clone_name_from_sanger_int_ext {
    my( $self, $clonename, $int_pre, $ext_pre ) = @_;

    $int_pre ||= '';
    $ext_pre ||= 'XX';
    substr($clonename, 0, length($int_pre)) = "$ext_pre-";
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

1;

__END__

=head1 NAME - Hum::TPF::Row::Clone

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

