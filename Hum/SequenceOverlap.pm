
### Hum::SequenceOverlap

package Hum::SequenceOverlap;
use Hum::SequenceOverlap::Position;

use strict;
use Carp;
use Hum::Tracking qw{ track_db prepare_track_statement };

### This is missing code to deal with statuses
### Probably need at least to add "Detected" status

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub fetch_by_SequenceInfo_pair {
    my( $pkg, $seq_a, $seq_b ) = @_;
    
    my $sth = track_db->prepare_cached(q{
        select oa.position, os.is_3prime,
        ob.position, ob.is_3prime,
        o.length, o.id_source, o.pct_substitutions, o.pct_insertions, o.pct_deletions
        from sequence_overlap oa
          , overlap o
          , sequence_overlap ob
        where oa.id_overlap = o.id_overlap
        and o.id_overlap = ob.id_overlap
        and oa.id_sequence = ?
        and ob.id_sequence = ?
        });
}

sub fetch_by_db_id {
    my( $pkg, $id ) = @_;
    
    my $sth = track_db->prepare_cached(q{
        SELECT length
          , id_source
          , pct_substitutions
          , pct_insertions
          , pct_deletions
        FROM overlap
        WHERE id_overlap = ?
        });
    $sth->execute($id);
    my( $length, $source, $sub, $ins, $del ) = $sth->fetchrow;
    confess "No overlap with id '$id'" unless $length;
    my $self = $pkg->new;
    $self->db_id($id);
    $self->overlap_length($length);
    $self->source_name($self->name_from_source_id($source));
    $self->percent_substitution($sub);
    $self->percent_insertion($ins);
    $self->percent_deletion($del);
    return $self;
}

sub db_id {
    my( $self, $db_id ) = @_;
    
    if ($db_id) {
        $self->{'_db_id'} = $db_id;
    }
    return $self->{'_db_id'};
}

sub a_Position {
    my( $self, $a_Position ) = @_;
    
    if ($a_Position) {
        $self->{'_a_Position'} = $a_Position;
    }
    return $self->{'_a_Position'};
}

sub b_Position {
    my( $self, $b_Position ) = @_;
    
    if ($b_Position) {
        $self->{'_b_Position'} = $b_Position;
    }
    return $self->{'_b_Position'};
}

sub overlap_length {
    my( $self, $overlap_length ) = @_;
    
    if ($overlap_length) {
        $self->{'_overlap_length'} = $overlap_length;
    }
    return $self->{'_overlap_length'};
}

sub percent_substitution {
    my( $self, $percent_substitution ) = @_;
    
    if ($percent_substitution) {
        $self->{'_percent_substitution'} = $percent_substitution;
    }
    return $self->{'_percent_substitution'};
}

sub percent_insertion {
    my( $self, $percent_insertion ) = @_;
    
    if ($percent_insertion) {
        $self->{'_percent_insertion'} = $percent_insertion;
    }
    return $self->{'_percent_insertion'};
}

sub percent_deletion {
    my( $self, $percent_deletion ) = @_;
    
    if ($percent_deletion) {
        $self->{'_percent_deletion'} = $percent_deletion;
    }
    return $self->{'_percent_deletion'};
}

sub source_name {
    my( $self, $source_name ) = @_;
    
    if ($source_name) {
        $self->{'_source_name'} = $source_name;
    }
    return $self->{'_source_name'};
}

{
    my( %id_name, %name_id );

    sub _fill_id_name_hashes {
        my $sth = prepare_track_statement(q{
            SELECT id_source
              , name
            FROM overlapsourcedict
            });
        $sth->execute;
        while (my ($id, $name) = $sth->fetchrow) {
            $id_name{$id} = $name;
            $name_id{$name} = $id;
        }
    }

    sub source_id {
        my( $self ) = @_;
        
        my $name = $self->source_name
            or confess "source_name not set";
        unless (%name_id) {
            _fill_id_name_hashes();
        }
        if (my $id = $name_id{$name}) {
            return $id;
        } else {
            confess "No id for overlap source name '$name'";
        }
    }
    
    sub name_from_source_id {
        my( $self, $id ) = @_;
        
        confess "Missing id argument" unless $id;
        
        unless (%id_name) {
            _fill_id_name_hashes();
        }
        if (my $name = $id_name{$id}) {
            return $name;
        } else {
            confess "No name for overlap source id '$id'";
        }
    }
}

sub make_new_Position_objects {
    my( $self ) = @_;
    
    my $pa = Hum::SequenceOverlap::Position->new;
    $self->a_Position($pa);
    my $pb = Hum::SequenceOverlap::Position->new;
    $self->b_Position($pb);
    return($pa, $pb);
}

sub validate_Positions {
    my( $self ) = @_;
    
    $self->a_Position->validate;
    $self->b_Position->validate;
}

sub store {
    my( $self ) = @_;
    
    # Warn here?
    return if $self->db_id;
    my $db_id = $self->get_next_id;
    
    my $sth = track_db->prepare_cached(q{
        INSERT INTO overlap(
            id_overlap
          , length
          , id_source
          , pct_substitutions
          , pct_insertions,
          , pct_deletions )
        VALUES(?,?,?,?,?,?)
        });
    $sth->execute(
        $self->db_id,
        $self->overlap_length,
        $self->source_id,
        $self->percent_substitution,
        $self->percent_insertion,
        $self->percent_deletion,
        );
    $self->a_Position->store($db_id);
    $self->b_Position->store($db_id);
}

sub get_next_id {
    my( $self ) = @_;
    
    my $sth = track_db()->prepare_cached(q{
        SELECT over_seq.nextval FROM dual
        });
    $sth->execute;
    my ($id) = $sth->fetchrow;
    $self->db_id($id);
    return $id;
}
1;

__END__

=head1 NAME - Hum::SequenceOverlap

=head1 STRATEGY

How to walk down the tpf.

For each contiguous stretch of clones down the
tpf, get a list of contiguous current ids, and
make a list of SequenceInfo objects.  (Deal
missing entries in the sequence table.)

For each pair of SequenceInfo objects, get the
overlap.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

