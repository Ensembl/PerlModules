
### Hum::TPF::Row::Gap

package Hum::TPF::Row::Gap;

use strict;
use Carp;
use base 'Hum::TPF::Row';
use Hum::Tracking 'prepare_cached_track_statement';


sub is_gap { return 1; }

sub type {
    my( $self, $type ) = @_;
    
    if ($type) {
        confess "Bad type '$type'" unless $type =~ /^[12345]$/;
        $self->{'_type'} = $type;
    }
    return $self->{'_type'};
}

sub type_string {
    my( $self ) = @_;
    
    my $type = $self->type or confess "type not set";
    if ($type == 5) {
        return 'CENTROMERE';
    } else {
        return "type-$type";
    }
}

sub gap_length {
    my( $self, $gap_length ) = @_;
    
    if ($gap_length) {
        $self->{'_gap_length'} = $gap_length;
    }
    return $self->{'_gap_length'};
}

sub string {
    my( $self ) = @_;
    
    return join("\t",
        'GAP',
        $self->type_string,
        $self->gap_length || '?')
        . "\n";
}


sub store {
    my( $self, $tpf, $rank ) = @_;
    
    confess("row is already stored with id_tpfrow=", $self->db_id)
        if $self->db_id;
    
    my $db_id = $self->get_next_id_tpfrow;
    my $insert = prepare_cached_track_statement(q{
        INSERT INTO tpf_row(id_tpfrow
              , id_tpf
              , rank)
        VALUES(?,?,?)
        });
    $insert->execute(
        $db_id,
        $tpf->db_id,
        $rank,
        );
    
    my $gap_insert = prepare_cached_track_statement(q{
        INSERT INTO tpf_gap(id_tpfrow
              , length
              , id_gaptype)
        VALUES(?,?,?)
        });
    $gap_insert->execute(
        $db_id,
        $self->gap_length,
        $self->type,
        );
    
    $self->db_id($db_id);
}

1;

__END__

=head1 NAME - Hum::TPF::Row::Gap

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

