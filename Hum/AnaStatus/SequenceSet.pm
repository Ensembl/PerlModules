
### Hum::AnaStatus::SequenceSet

package Hum::AnaStatus::SequenceSet;

use strict;
use warnings;
use Carp;
use Hum::AnaStatus::Sequence;
use Hum::Submission 'prepare_statement';

sub new {
    my( $pkg ) = @_;

    return bless {
        _sequence_list  => [],
        }, $pkg;
}

sub new_from_set_name {
    my( $pkg, $set_name ) = @_;

    if ($set_name =~ /=/) {
        return $pkg->_new_from_soft_set_name($set_name);
    } else {
        return $pkg->_new_from_hard_set_name($set_name, " and a.is_current = 'Y' ");
    }
}

# Also inclues the non-current seuqences
sub new_archival_from_set_name {
    my( $pkg, $set_name ) = @_;
    
    return $pkg->_new_from_hard_set_name($set_name, "");
}

{
    my %tag_sprintf_pat = (
        'species'   => ' AND sc.species_name = "%s" ',
        'chr'       => ' AND sc.chr_name = "%s" ',
        );

    sub _new_from_soft_set_name {
        my( $pkg, $set_query ) = @_;
        
        my $sql = q{
            SELECT s.sequence_name
            FROM species_chromosome sc
              , sequence s
              , ana_sequence a
            WHERE sc.chromosome_id = s.chromosome_id
              AND s.seq_id = a.seq_id
              AND a.is_current = 'Y'
            };

        foreach my $tv (split /,/, $set_query) {
            my ($tag, @val) = split /=/, $tv;
            confess "Bad tag-value pair '$tv' in '$set_query'"
                unless @val == 1;
            if (my $pat = $tag_sprintf_pat{$tag}) {
                $sql .= sprintf($pat, $val[0]);
            } else {
                confess "Tag '$tag' in '$set_query' is unknown.  Known tags:\n",
                    map("  $_\n", keys %tag_sprintf_pat);
            }
        }
        
        $sql .= q{ ORDER BY s.sequence_name };
        
        warn $sql;
        
        my $sth = prepare_statement($sql);
        $sth->execute;
        my( @seq_name );
        while (my ($s) = $sth->fetchrow) {
            push(@seq_name, $s);
        }
        
        my $self = $pkg->new;
        $self->set_name($set_query);
        $self->set_description("Soft set built from '$set_query'");
        $self->add_sequence_by_name(@seq_name);

        return $self;
    }
}

sub _new_from_hard_set_name {
    my( $pkg, $set_name, $clause ) = @_;

    my $sth = prepare_statement(qq{
        SELECT aset.set_id
           , aset.set_description
	   , s.sequence_name
        FROM ana_set aset
          , ana_sequence_set ss
          , ana_sequence a
          , sequence s
        WHERE aset.set_id = ss.set_id
          AND ss.ana_seq_id = a.ana_seq_id
          AND a.seq_id = s.seq_id
          $clause
          AND aset.set_name = '$set_name'
        ORDER BY ss.rank ASC
        });
    $sth->execute;

    my( $set_id, $set_description, @seq_name );
    while (my ($id, $desc, $name) = $sth->fetchrow) {
        $set_id          = $id;
        $set_description = $desc;
        push(@seq_name, $name);
    }

    confess "No such set '$set_name'" unless $set_id;

    my $self = $pkg->new;
    $self->set_id($set_id);
    $self->set_name($set_name);
    $self->set_description($set_description);
    $self->add_sequence_by_name(@seq_name);

    return $self;
}

sub set_id {
    my ( $self, $set_id ) = @_;
    
    if ($set_id) {
        confess "Can't modify set_id"
            if $self->{'_set_id'};
        $self->{'_set_id'} = $set_id;
    }
    return $self->{'_set_id'};
}

sub set_name {
    my ( $self, $set_name ) = @_;
    
    if ($set_name) {
        confess "Can't modify set_name"
            if $self->{'_set_name'};
        $self->{'_set_name'} = $set_name;
    }
    return $self->{'_set_name'};
}

sub set_description {
    my ( $self, $set_description ) = @_;
    
    if ($set_description) {
        confess "Can't modify set_description"
            if $self->{'_set_description'};
        $self->{'_set_description'} = $set_description;
    }
    return $self->{'_set_description'};
}

{
    my $obj_type = 'Hum::AnaStatus::Sequence';

    sub add_sequence {
        my( $self, @seq ) = @_;

        foreach my $ana_seq (@seq) {
            unless (ref($ana_seq) and $ana_seq->isa($obj_type)) {
                confess("Not a '$obj_type' : '$ana_seq'");
            }
            push @{$self->{'_sequence_list'}}, $ana_seq;
        }
    }
}

sub add_sequence_by_name {
    my( $self, @names ) = @_;

    my( @seq_list );
    foreach my $n (@names) {
        my $ana_seq = Hum::AnaStatus::Sequence
            ->new_from_sequence_name($n);
        push(@seq_list, $ana_seq);
    }
    $self->add_sequence(@seq_list);
}

sub sequence_list {
    my( $self ) = @_;
    
    return @{$self->{'_sequence_list'}};
}

sub store {
    my( $self ) = @_;

    my $set_id = $self->set_id;
    confess "Set already stored under ID '$set_id'"
        if $set_id;
    my $set_name = $self->set_name
        or confess "set_name not set";
    my @seq_list = $self->sequence_list
        or confess "empty set";
    my $set_description = $self->set_description || '';

    my $insert_set = prepare_statement(qq{
        INSERT ana_set(set_id
              , set_name
              , set_description)
        VALUES(NULL,'$set_name', '$set_description')
        });
    $insert_set->execute;
    $set_id = $insert_set->{'mysql_insertid'}
        or confess "Didn't get a set_id";

    my $insert_seq = prepare_statement(q{
        INSERT ana_sequence_set(ana_seq_id
              , set_id
              , rank)
        VALUES(?,?,?)
        });

    my $last_rank = 0;
    for (my $i = 0; $i < @seq_list; $i++) {
        my $seq = $seq_list[$i];
        my $rank = $seq->rank || $last_rank + 1;
        my $ana_seq_id = $seq->ana_seq_id
            or confess "No ana_seq_id";
        $insert_seq->execute($ana_seq_id, $set_id, $rank);
        $last_rank = $rank;
    }

    return 1;
}

sub delete_from_db {
    my( $self ) = @_;
    
    my $set_id = $self->set_id
        or confess "Set not stored in database";
    
    my $delete_sequences = prepare_statement(qq{
        DELETE FROM ana_sequence_set WHERE set_id = $set_id
        });
    $delete_sequences->execute;
    confess "Nothing deleted from ana_sequence_set"
        unless $delete_sequences->rows;
    
    my $delete_set = prepare_statement(qq{
        DELETE FROM ana_set WHERE set_id = $set_id
        });
    $delete_set->execute;
    confess "Nothing deleted from ana_set"
        unless $delete_set->rows;
    
    $self->{'_set_name'} = undef;
}

1;

__END__

=head1 NAME - Hum::AnaStatus::SequenceSet

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

