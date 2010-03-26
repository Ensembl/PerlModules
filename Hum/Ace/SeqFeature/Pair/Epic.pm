
### Hum::Ace::SeqFeature::Pair::Epic

package Hum::Ace::SeqFeature::Pair::Epic;

use strict;
use warnings;
use Hum::Ace::SeqFeature::Pair;
use vars '@ISA';

@ISA = ('Hum::Ace::SeqFeature::Pair');


sub algorithm {
  return "epic";
}


sub cigar_string {
    my( $self, $cigar_string ) = @_;
    
    if ($cigar_string) {
        $self->{'_cigar_string'} = $cigar_string;
    }
    return $self->{'_cigar_string'};
}

sub alignment_length {
    my( $self, $alignment_length ) = @_;
    
    if ($alignment_length) {
        $self->{'_alignment_length'} = $alignment_length;
    }
    return $self->{'_alignment_length'};
}

sub percent_substitution {
  my( $self, $percent_sub ) = @_;
    
  if (defined $percent_sub ) {
    $self->{'_percent_id'} = $percent_sub;
  }
  return $self->{'_percent_id'};
}

sub percent_insertion {
  my( $self, $percent_ins ) = @_;
    
  if (defined $percent_ins ) {
    $self->{'_percent_insertion'} = $percent_ins;
  }
  return $self->{'_percent_insertion'};
}

sub percent_deletion {
  my( $self, $percent_deletion ) = @_;
    
  if (defined $percent_deletion ) {
    $self->{'_percent_deletion'} = $percent_deletion;
  }
  return $self->{'_percent_deletion'};
}


1;

__END__

=head1 NAME - Hum::Ace::SeqFeature::Pair::Epic

=head1 AUTHOR

Kim Brugger B<email> kb8@sanger.ac.uk

