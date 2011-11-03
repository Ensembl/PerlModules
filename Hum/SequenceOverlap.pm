
### Hum::SequenceOverlap

package Hum::SequenceOverlap;

use strict;
use warnings;
use Carp;
use Hum::Tracking qw{ track_db prepare_track_statement };
use Hum::SequenceOverlap::Position;

sub new {
    my ($pkg) = @_;

    return bless {}, $pkg;
}

sub fetch_contained_by_SequenceInfo_pair {
    my ($pkg, $seq_a, $seq_b) = @_;

    return $pkg->_generic_fetch_contained($seq_a, $seq_b, ' AND s.id_status != 3 ');
}

sub fetch_by_SequenceInfo_pair {
    my ($pkg, $seq_a, $seq_b) = @_;

    return $pkg->_generic_fetch($seq_a, $seq_b, ' AND s.id_status != 3 ');
}

sub fetch_by_SequenceInfo_pair_including_refuted {
    my ($pkg, $seq_a, $seq_b) = @_;

    return $pkg->_generic_fetch($seq_a, $seq_b, '');
}

sub _generic_fetch {
    my ($pkg, $seq_a, $seq_b, $where_clause) = @_;

    confess "Need two SequenceInfo objects, but got '$seq_a' and '$seq_b'"
      unless $seq_a and $seq_b;

    my $sth = track_db->prepare_cached(
        qq{
        SELECT oa.position
          , oa.is_3prime
          , oa.dovetail_length
          , ob.position
          , ob.is_3prime
          , ob.dovetail_length
          , o.id_overlap
          , o.length
          , o.id_source
          , o.pct_substitutions
          , o.pct_insertions
          , o.pct_deletions
          , s.id_status
          , s.remark
          , s.program
          , s.operator
          , to_char(s.statusdate, 'yyyy-mm-dd')
        FROM sequence_overlap oa
          , overlap o
          , sequence_overlap ob
          , overlap_status s
        WHERE oa.id_overlap = o.id_overlap
          AND o.id_overlap = ob.id_overlap
          AND o.id_overlap = s.id_overlap
          AND s.iscurrent = 1
          AND oa.id_sequence = ?
          AND ob.id_sequence = ?
          $where_clause
        }
    );
    $sth->execute($seq_a->db_id, $seq_b->db_id);

    my (
        $a_pos,      $a_is3prime, $a_dovetail, $b_pos,    $b_is3prime, $b_dovetail,
        $overlap_id, $length,     $source_id,  $sub,      $ins,        $del,
        $status,     $remark,     $program,    $operator, $statusdate
    ) = $sth->fetchrow;
    $sth->finish;

    return unless $overlap_id;

    my $self = $pkg->new;
    $self->db_id($overlap_id);
    $self->overlap_length($length);
    $self->source_name($self->name_from_source_id($source_id));
    $self->percent_substitution($sub);
    $self->percent_insertion($ins);
    $self->percent_deletion($del);
    $self->status_id($status);
    $self->remark($remark);
    $self->program($program       || '');
    $self->operator($operator     || '');
    $self->statusdate($statusdate || '');

    my ($pa, $pb) = $self->make_new_Position_objects;
    $pa->position($a_pos);
    $pa->is_3prime($a_is3prime);
    $pa->dovetail_length($a_dovetail);
    $pa->SequenceInfo($seq_a);
    $pb->position($b_pos);
    $pb->is_3prime($b_is3prime);
    $pb->dovetail_length($b_dovetail);
    $pb->SequenceInfo($seq_b);

    return $self;
}

sub _generic_fetch_contained {
    my ($pkg, $seq_a, $seq_b, $where_clause) = @_;

    confess "Need two SequenceInfo objects, but got '$seq_a' and '$seq_b'"
      unless $seq_a and $seq_b;

    my $sth = track_db->prepare_cached(
        qq{
        SELECT oa.position
          , oa.is_3prime
          , oa.dovetail_length
          , ob.position
          , ob.is_3prime
          , ob.dovetail_length
          , o.id_overlap
          , o.length
          , o.id_source
          , o.pct_substitutions
          , o.pct_insertions
          , o.pct_deletions
          , s.id_status
          , s.remark
          , s.program
          , s.operator
          , to_char(s.statusdate, 'yyyy-mm-dd')
        FROM sequence_overlap oa
          , overlap o
          , sequence_overlap ob
          , overlap_status s
        WHERE oa.id_overlap = o.id_overlap
          AND o.id_overlap = ob.id_overlap
          AND o.id_overlap = s.id_overlap
          AND s.iscurrent = 1
          AND oa.id_sequence = ?
          AND ob.id_sequence = ?
          $where_clause
        }
    );
    $sth->execute($seq_a->db_id, $seq_b->db_id);

	my @overlaps;
	while(
	    my (
	        $a_pos,      $a_is3prime, $a_dovetail, $b_pos,    $b_is3prime, $b_dovetail,
	        $overlap_id, $length,     $source_id,  $sub,      $ins,        $del,
	        $status,     $remark,     $program,    $operator, $statusdate
	    ) = $sth->fetchrow
	) {

    	return unless $overlap_id;

	    my $self = $pkg->new;
	    $self->db_id($overlap_id);
	    $self->overlap_length($length);
	    $self->source_name($self->name_from_source_id($source_id));
	    $self->percent_substitution($sub);
	    $self->percent_insertion($ins);
	    $self->percent_deletion($del);
	    $self->status_id($status);
	    $self->remark($remark);
	    $self->program($program       || '');
	    $self->operator($operator     || '');
	    $self->statusdate($statusdate || '');
	
	    my ($pa, $pb) = $self->make_new_Position_objects;
	    $pa->position($a_pos);
	    $pa->is_3prime($a_is3prime);
	    $pa->dovetail_length($a_dovetail);
	    $pa->SequenceInfo($seq_a);
	    $pb->position($b_pos);
	    $pb->is_3prime($b_is3prime);
	    $pb->dovetail_length($b_dovetail);
	    $pb->SequenceInfo($seq_b);
	    push(@overlaps, $self);
	}

    $sth->finish;

    return @overlaps;
}


# This doesn't fetch the Overlap::Position objects, so is it any use?
sub fetch_by_db_id {
    my ($pkg, $id) = @_;

    my $sth = track_db->prepare_cached(
        q{
        SELECT length
          , id_source
          , pct_substitutions
          , pct_insertions
          , pct_deletions
        FROM overlap
        WHERE id_overlap = ?
        }
    );
    $sth->execute($id);
    my ($length, $source, $sub, $ins, $del) = $sth->fetchrow;
    $sth->finish;
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
    my ($self, $db_id) = @_;

    if ($db_id) {
        $self->{'_db_id'} = $db_id;
    }
    return $self->{'_db_id'};
}

sub a_Position {
    my ($self, $a_Position) = @_;

    if ($a_Position) {
        $self->{'_a_Position'} = $a_Position;
    }
    return $self->{'_a_Position'};
}

sub b_Position {
    my ($self, $b_Position) = @_;

    if ($b_Position) {
        $self->{'_b_Position'} = $b_Position;
    }
    return $self->{'_b_Position'};
}

sub overlap_length {
    my ($self, $overlap_length) = @_;

    # overlap length is zero for abutting sequences
    if (defined $overlap_length) {
        $self->{'_overlap_length'} = $overlap_length;
    }
    return $self->{'_overlap_length'};
}

sub percent_substitution {
    my ($self, $percent_substitution) = @_;

    if (defined $percent_substitution) {
        $self->{'_percent_substitution'} = $percent_substitution;
    }
    return $self->{'_percent_substitution'};
}

sub percent_insertion {
    my ($self, $percent_insertion) = @_;

    if (defined $percent_insertion) {
        $self->{'_percent_insertion'} = $percent_insertion;
    }
    return $self->{'_percent_insertion'};
}

sub percent_deletion {
    my ($self, $percent_deletion) = @_;

    if (defined $percent_deletion) {
        $self->{'_percent_deletion'} = $percent_deletion;
    }
    return $self->{'_percent_deletion'};
}

sub matches {
    my ($self, $othr) = @_;

    confess "Missing SequenceOverlap argument" unless $othr;
    my $self_a = $self->a_Position;
    my $self_b = $self->b_Position;
    my $othr_a = $othr->a_Position;
    my $othr_b = $othr->b_Position;

    # Are the Position objects the other way around?
    if ($self_a->SequenceInfo->accession eq $othr_a->SequenceInfo->accession) {
        return 0 unless $self_a->matches($othr_a);
        return 0 unless $self_b->matches($othr_b);
    }
    else {
        return 0 unless $self_a->matches($othr_b);
        return 0 unless $self_b->matches($othr_a);
    }

    return 1;
}

sub best_match_pair {
    my ($self, $best_match_pair) = @_;

    if ($best_match_pair) {
        $self->{'_best_match_pair'} = $best_match_pair;
    }
    return $self->{'_best_match_pair'};

}

sub other_match_pairs {

    # a list of crossmatch matches other than the best one
    my ($self, $other_match_pairs) = @_;

    if ($other_match_pairs) {
        $self->{'_other_match_pairs'} = $other_match_pairs;
    }
    return $self->{'_other_match_pairs'};

}

sub source_name {
    my ($self, $source_name) = @_;

    if ($source_name) {
        $self->{'_source_name'} = $source_name;
    }
    return $self->{'_source_name'};
}

sub status_id {
    my ($self, $status_id) = @_;

    if ($status_id) {
        $self->{'_status_id'} = $status_id;
    }

    # Default status is 1 ("Identified")
    return $self->{'_status_id'} || 1;
}

sub remark {
    my ($self, $remark) = @_;

    if (defined $remark) {
        $self->{'_remark'} = $remark;
    }
    return $self->{'_remark'};
}

sub program {
    my ($self, $program) = @_;

    if ($program) {
        $self->{'_program'} = $program;
    }
    return $self->{'_program'};
}

{
    my ($prog) = $0 =~ m{([^/]+)$};

    sub default_program {
        return $prog;
    }
}

sub operator {
    my ($self, $operator) = @_;

    if ($operator) {
        $self->{'_operator'} = $operator;
    }
    return $self->{'_operator'};
}

sub statusdate {
    my ($self, $statusdate) = @_;

    if ($statusdate) {
        $self->{'_statusdate'} = $statusdate;
    }
    return $self->{'_statusdate'};
}

{
    my $who = (getpwuid($<))[0];

    sub default_operator {
        return $who;
    }
}

{
    my (%id_desc);

    sub status_description {
        my ($self) = @_;

        my $id = $self->status_id or return;
        $self->_fetch_status_descriptions unless %id_desc;
        return $id_desc{$id} || confess "No description for id_status '$id'";
    }

    sub _fetch_status_descriptions {
        my $sth = prepare_track_statement(
            q{
            SELECT id_status
              , description
            FROM overlapstatusdict
            }
        );
        $sth->execute;
        while (my ($id, $desc) = $sth->fetchrow) {
            $id_desc{$id} = $desc;
        }
    }
}

{
    my (%id_name, %name_id);

    sub _fill_id_name_hashes {
        my $sth = prepare_track_statement(
            q{
            SELECT id_source
              , name
            FROM overlapsourcedict
            }
        );
        $sth->execute;
        while (my ($id, $name) = $sth->fetchrow) {
            $id_name{$id}   = $name;
            $name_id{$name} = $id;
        }
    }

    sub source_id {
        my ($self) = @_;

        my $name = $self->source_name
          or confess "source_name not set";
        unless (%name_id) {
            _fill_id_name_hashes();
        }
        if (my $id = $name_id{$name}) {
            return $id;
        }
        else {
            confess "No id for overlap source name '$name'";
        }
    }

    sub name_from_source_id {
        my ($self, $id) = @_;

        confess "Missing id argument" unless $id;

        unless (%id_name) {
            _fill_id_name_hashes();
        }
        if (my $name = $id_name{$id}) {
            return $name;
        }
        else {
            confess "No name for overlap source id '$id'";
        }
    }
}

sub make_new_Position_objects {
    my ($self) = @_;

    my $pa = Hum::SequenceOverlap::Position->new;
    $self->a_Position($pa);
    my $pb = Hum::SequenceOverlap::Position->new;
    $self->b_Position($pb);
    return ($pa, $pb);
}

sub validate_Positions {
    my ($self) = @_;

    $self->a_Position->validate;
    $self->b_Position->validate;
}

sub store {
    my ($self) = @_;

    my $db_id = $self->db_id;
    if ($db_id) {
        confess "Already stored with db_id $db_id";
    }
    $db_id = $self->get_next_id;

    my $sth = track_db->prepare_cached(
        q{
        INSERT INTO overlap(
            id_overlap
          , length
          , id_source
          , pct_substitutions
          , pct_insertions
          , pct_deletions )
        VALUES(?,?,?,?,?,?)
        }
    );
    $sth->execute($db_id, $self->overlap_length, $self->source_id, $self->percent_substitution,
        $self->percent_insertion, $self->percent_deletion,);

    $self->store_status;

    $self->a_Position->store($db_id);
    $self->b_Position->store($db_id);
}

sub store_status {
    my ($self) = @_;

    my $db_id = $self->db_id
      or confess "Can't store status without db_id";

    my $unset_status = track_db->prepare_cached(
        q{
        UPDATE overlap_status
        SET iscurrent = 0
        WHERE id_overlap = ?
        }
    );
    $unset_status->execute($db_id);

    #### Should populate SESSIONID column?
    my $store_status = track_db->prepare_cached(
        q{
        INSERT INTO overlap_status(
            id_overlap
          , id_status
          , remark
          , program
          , operator
          , statusdate
          , iscurrent )
        VALUES(?,?,?,?,?,sysdate,1)
        }
    );

    my $program = $self->program  || $self->default_program;
    my $who     = $self->operator || $self->default_operator;

    $store_status->bind_param(1, $db_id,           DBI::SQL_INTEGER);
    $store_status->bind_param(2, $self->status_id, DBI::SQL_INTEGER);
    $store_status->bind_param(3, $self->remark,    DBI::SQL_VARCHAR);
    $store_status->bind_param(4, $program,         DBI::SQL_VARCHAR);
    $store_status->bind_param(5, $who,             DBI::SQL_VARCHAR);
    $store_status->execute;
}

sub get_next_id {
    my ($self) = @_;

    my $sth = track_db()->prepare_cached(
        q{
        SELECT over_seq.nextval FROM dual
        }
    );
    $sth->execute;
    my ($id) = $sth->fetchrow;
    $sth->finish;
    $self->db_id($id);
    return $id;
}

# This only stores the overlap if it is different
# to the one in the database, or if there isn't
# one in the database.
sub store_if_new {
    my ($self) = @_;

    my $inf_a = $self->a_Position->SequenceInfo;
    my $inf_b = $self->b_Position->SequenceInfo;

    # If there is an existing overlap, is it
    # identical to the new coordinates?
    my $old = Hum::SequenceOverlap->fetch_by_SequenceInfo_pair($inf_a, $inf_b);

    if ($old) {
        if ($self->matches($old)) {

            # Coordinates are identical to existing overlap
            return 0;
        }
        else {
            $old->status_id(3);    # Refuted
            $old->program($old->default_program);
            ### Need to change to logged in user:
            $old->operator($old->default_operator);
            $old->remark('');
            $old->store_status;
        }
    }

    $self->store;
    return 1;
}

# This only stores the overlap if it is different
# to the one in the database, or if there isn't
# one in the database.
sub store_new_copy {
    my ($self) = @_;

	my $previous_status = $self->status_id;
	$self->status_id(3);    # Refuted

	# Make it clear that the current program has been responsible for the changes
	$self->program($self->default_program);
	$self->operator($self->default_operator);
	$self->remark('');
	$self->store_status;

	$self->{'_db_id'} = undef;

	# Now reset the status that you're about to store
	$self->status_id($previous_status);

    $self->store;
    
    return 1;
}

# This only stores the overlap if it is different
# to the one in the database, or if there isn't
# one in the database.
sub store_if_new_without_deletion {
    my ($self) = @_;

    my $inf_a = $self->a_Position->SequenceInfo;
    my $inf_b = $self->b_Position->SequenceInfo;

    # If there is an existing overlap, is it
    # identical to the new coordinates?
	# This will only be called where there are multiple overlaps,
	# so it's pertinent to look up on the assumption of contained clones
    my @old_overlaps = Hum::SequenceOverlap->fetch_contained_by_SequenceInfo_pair($inf_a, $inf_b);

    foreach my $old (@old_overlaps) {
        if ($self->matches($old)) {

            # Coordinates are identical to existing overlap
            return 0;
        }
    }

	print "Storing\n";
    $self->store;
    return 1;
}

sub remove {
    my ($self) = @_;

    my (@del_sth);
    foreach my $table (qw{ OVERLAP_STATUS SEQUENCE_OVERLAP OVERLAP }) {
        push(
            @del_sth,
            track_db()->prepare_cached(
                qq{
            DELETE from $table WHERE id_overlap = ?
            }
            )
        );
    }

    my $id = $self->db_id or confess "db_id not set - overlap not stored?";
    foreach my $sth (@del_sth) {
        $sth->execute($id);
    }
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

