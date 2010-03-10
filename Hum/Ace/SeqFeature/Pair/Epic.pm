
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

sub cigar {
  my( $self, $cigar ) = @_;
    
  if (defined $cigar ) {
    $self->{'_cigar'} = $cigar;
  }
  return $self->{'_cigar'};
}

sub length {
  my( $self, $length ) = @_;
    
  if (defined $length ) {
    $self->{'_length'} = $length;
  }
  return $self->{'_length'};
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

