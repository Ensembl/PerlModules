
### Hum::TPF

package Hum::TPF;

use strict;
use Carp;
use Hum::TPF::Parser;
use Hum::TPF::Row::Clone;
use Hum::TPF::Row::Gap;
use Hum::Tracking qw{
    prepare_cached_track_statement
    prepare_track_statement };

sub new {
    my( $pkg ) = @_;
    
    return bless {
        '_rows' => [],
        }, $pkg;
}


sub species {
    my( $self, $species ) = @_;
    
    if ($species) {
        $self->{'_species'} = $species;
    }
    return $self->{'_species'};
}

sub chromosome {
    my( $self, $chromosome ) = @_;
    
    if ($chromosome) {
        $self->{'_chromosome'} = $chromosome;
    }
    return $self->{'_chromosome'};
}

sub subregion {
    my( $self, $subregion ) = @_;
    
    if ($subregion) {
        $self->{'_subregion'} = $subregion;
    }
    return $self->{'_subregion'};
}

sub entry_date {
    my( $self, $entry_date ) = @_;
    
    if ($entry_date) {
        $self->{'_entry_date'} = $entry_date;
    }
    return $self->{'_entry_date'};
}

sub program {
    my( $self, $program ) = @_;
    
    if ($program) {
        $self->{'_program'} = $program;
    }
    return $self->{'_program'} || $0 =~ m{([^/]+)$};
}

sub operator {
    my( $self, $operator ) = @_;
    
    if ($operator) {
        $self->{'_operator'} = $operator;
    }
    return $self->{'_operator'} || (getpwuid($<))[0];
}

sub new_from_db_id {
    my( $pkg, $db_id ) = @_;
    
    confess "missing db_id argument" unless $db_id;
    
    return $pkg->_fetch_generic(q{ AND t.id_tpf = ? }, $db_id);
}

sub new_current_from_species_chromsome {
    my( $pkg, $species, $chromsome ) = @_;
    
    return $pkg->_fetch_generic(q{
          AND t.iscurrent = 1
          AND c.speciesname = ?
          AND c.chromosome = ?
        },
        $species, $chromsome);
}

sub _fetch_generic {
    my( $pkg, $where_clause, @data ) = @_;

    my $sth = prepare_cached_track_statement(qq{
        SELECT t.id_tpf
          , t.entry_date
          , t.program
          , t.operator
          , g.subregion
          , c.speciesname
          , c.chromosome
        FROM tpf t
          , tpf_target g
          , chromosomedict c
        WHERE t.id_tpftarget = g.id_tpftarget
          AND g.chromosome = c.id_dict
          $where_clause
        });
    $sth->execute(@data);
    my ($db_id, $entry_date, $prog, $operator,
        $subregion, $species, $chr) = $sth->fetchrow;
    my $self = $pkg->new;
    $self->db_id($db_id);
    $self->entry_date($entry_date);
    $self->program($prog);
    $self->operator($operator);
    $self->subregion($subregion);
    $self->species($species);
    $self->chromosome($chr);
    
    $self->_express_fetch_Rows;
    
    return $self;
}

sub _express_fetch_Rows {
    my( $self ) = @_;

    my $db_id = $self->db_id;

    my $rank_gap = $self->_express_fetch_Gaps;

    my $sth = prepare_cached_track_statement(q{
        SELECT r.id_tpfrow
          , r.rank
          , r.clonename
          , r.contigname
          , l.internal_prefix
          , l.external_prefix
          , s.accession
        FROM tpf_row r
          , clone c
          , library l
          , clone_sequence cs
          , sequence s
        WHERE r.clonename = c.clonename
          AND c.libraryname = l.libraryname (+)
          AND c.clonename = cs.clonename (+)
          AND cs.id_sequence = s.id_sequence (+)
          AND r.id_tpf = ?
        ORDER BY r.rank ASC
        });
    $sth->execute($db_id);
    my( $clone_id, $clone_rank, $clonename, $contigname, $int_pre, $ext_pre, $acc );
    $sth->bind_columns(\$clone_id, \$clone_rank, \$clonename, \$contigname,
        \$int_pre, \$ext_pre, \$acc);
    
    my $rank = 1;
    while ($sth->fetch) {
        
        # Add any gaps before this position
        until ($clone_rank == $rank) {
            my $gap = $rank_gap->{$rank}
                or confess "No gap with rank '$rank'";
            $self->add_Row($gap);
            $rank++;
        }
        
        my $clone = Hum::TPF::Row::Clone->new;
        $clone->db_id($clone_id);
        $clone->contig_name($contigname);
        $clone->sanger_clone_name($clonename);
        $clone->set_intl_clone_name_from_sanger_int_ext($clonename, $int_pre, $ext_pre);
        $clone->accession($acc);
        $self->add_Row($clone);
        $rank++;
    }
    
    # Add any gaps onto the end
    while (my $gap = $rank_gap->{++$rank}) {
        $self->add_Row($gap);
    }
    
    return $self;
}

sub _express_fetch_Gaps {
    my( $self ) = @_;
    
    my $sth = prepare_cached_track_statement(q{
        SELECT r.id_tpfrow
          , r.rank
          , g.length
          , g.id_gaptype
        FROM tpf_row r
          , tpf_gap g
        WHERE r.id_tpfrow = g.id_tpfrow
          AND r.id_tpf = ?
        ORDER BY r.rank ASC
        });
    $sth->execute($self->db_id);
    my( $gap_id, $gap_rank, $gap_length, $gap_type );
    $sth->bind_columns(\$gap_id, \$gap_rank, \$gap_length, \$gap_type);
    
    my $rank_gap = {};
    while ($sth->fetch) {
        my $gap = Hum::TPF::Row::Gap->new;
        $gap->db_id($gap_id);
        $gap->gap_length($gap_length);
        $gap->type($gap_type);
        $rank_gap->{$gap_rank} = $gap;
    }
    return $rank_gap;
}

sub db_id {
    my( $self, $db_id ) = @_;
    
    if ($db_id) {
        $self->{'_db_id'} = $db_id;
    }
    return $self->{'_db_id'};
}

sub add_Row {
    my( $self, $row ) = @_;
    
    push @{$self->{'_rows'}}, $row;
}

sub fetch_all_Rows {
    my( $self ) = @_;
    
    return @{$self->{'_rows'}};
}

sub string {
    my( $self ) = @_;
    
    my $str = '';
    foreach my $row ($self->fetch_all_Rows) {
        $str .= $row->string;
    }
    return $str;
}

1;

__END__

=head1 NAME - Hum::TPF

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

