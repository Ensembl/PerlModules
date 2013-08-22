
### Hum::TPF::Row::Gap

package Hum::TPF::Row::Gap;

use strict;
use warnings;
use Carp;
use base 'Hum::TPF::Row';
use Hum::Tracking 'prepare_cached_track_statement';


sub is_gap { return 1; }

sub type {
    my( $self, $type ) = @_;

    my %is_type_permitted = map {$_=>1} 1..12;

    if ($type) {
        confess "Bad type '$type'" unless (exists($is_type_permitted{$type}));
        $self->{'_type'} = $type;
    }
    return $self->{'_type'};
}

sub type_string {
    my( $self ) = @_;

    my %bio_gap_type = (5 => 'CENTROMERE',
                        6 => 'HETEROCHROMATIN',
                        7 => 'SHORT-ARM',
                        8 => 'TELOMERE',
                        9 => 'CENTROMERE_DATA_START',
                       10 => 'CENTROMERE_DATA_END',
					   11 => 'HETEROCHROMATIN_DATA_START',
					   12 => 'HETEROCHROMATIN_DATA_END',
                       );

    my $type = $self->type or confess "type not set";
    if ($type < 5) {
      return "type-$type";
    } else {
      return $bio_gap_type{$type};
    }
  #  if ($type > 4) {
#      return 'type-4';
#    } else {
#      return "type-$type";
#    }
}

sub ncbi {
  # use as a flag that we want to modify
  # GAP data in string() for all types to match NCBI format
  # ie:
  # GAP     type-2/3
  # GAP     heterochromatin

  my( $self, $ncbi ) = @_;
  if ($ncbi) {
    $self->{'_ncbi'} = $ncbi;
  }
  return $self->{'_ncbi'};
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

    my @fields = (
                  'GAP',
                  $self->type_string,
                  $self->gap_length || '', # replace '?' as NCBI does not use unknown length
                 );

    my $txt = $self->remark;

    # for all gap-size given, method should be given (which is not always availabe)
    # for all gap types so skip size to simplify
    # for type-4, only the remark is needed (eg, centromere)
    if ( $self->ncbi ) {
      if ( $self->type_string eq 'type-4' ){
        $fields[1] = $txt; # replace type_string with control vocabulary
      }
    }
    else {
      push(@fields, $txt) if $txt;
    }
    return join("\t", @fields) . "\n";
}

sub store {
    my( $self, $tpf, $rank ) = @_;
    
    confess("row is already stored with id_tpfrow=", $self->db_id)
        if $self->db_id;
    
    my $db_id = $self->get_next_id_tpfrow;
    my $insert = prepare_cached_track_statement(q{
        INSERT INTO tpf_row(id_tpfrow
              , id_tpf
              , rank
              , remark)
        VALUES(?,?,?,?)
        });
    $insert->execute(
        $db_id,
        $tpf->db_id,
        $rank,
        $self->remark,
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

