
### Hum::AnaStatus::SequenceSet

package Hum::AnaStatus::SequenceSet;

use strict;
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
          AND a.is_current = 'Y'
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
    $set_id = $insert_set->{'insertid'}
        or confess "Didn't get a set_id";

    my $insert_seq = prepare_statement(q{
        INSERT ana_sequence_set(ana_seq_id
              , set_id
              , rank)
        VALUES(?,?,?)
        });

    for (my $i = 0; $i < @seq_list; $i++) {
        my $rank = $i + 1;
        my $seq = $seq_list[$i];
        my $ana_seq_id = $seq->ana_seq_id
            or confess "No ana_seq_id";
        $insert_seq->execute($ana_seq_id, $set_id, $rank);
    }

    return 1;
}

1;

__END__

=head1 NAME - Hum::AnaStatus::SequenceSet

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

