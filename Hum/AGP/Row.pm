
### Hum::AGP::Row

package Hum::AGP::Row;

use strict;
use Carp;
use warnings;

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}

sub is_gap {
    my( $self ) = @_;

    return ref($self) =~ /gap/i ? 1 : 0;
}

sub remark {
    my( $self, $remark ) = @_;
    
    if ($remark) {
        $remark =~ s/^\s*#\s*//;
        $self->{'_remark'} = $remark;
    }
    return $self->{'_remark'};
}

sub check_positive_integer {
    my( $self, $int ) = @_;
    
    confess "Not my kind of integer '$int'"
        unless $int =~ /^[1-9]\d*$/;
}

sub chr_start {
    my( $self, $chr_start ) = @_;
    
    if (defined $chr_start) {
        $self->check_positive_integer($chr_start);
        $self->{'_chr_start'} = $chr_start;
    }
    return $self->{'_chr_start'};
}

sub chr_end {
    my( $self, $chr_end ) = @_;
    
    if (defined $chr_end) {
        $self->check_positive_integer($chr_end);
        $self->{'_chr_end'} = $chr_end;
    }
    return $self->{'_chr_end'};
}

sub join_error {
  my ( $self, $join_err) = @_;

  if ($join_err) {
    $self->{'_join_error'} = $join_err;
  }
  return $self->{'_join_error'};

}
sub error_message {
  my ( $self, $error_msg) = @_;

  if ($error_msg) {
    $self->{'_error_message'} = $error_msg;
  }
  return $self->{'_error_message'};
}

1;

__END__

=head1 NAME - Hum::AGP::Row

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

