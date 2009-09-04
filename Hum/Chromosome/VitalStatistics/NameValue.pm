
### Hum::Chromosome::VitalStatistics::NameValue

package Hum::Chromosome::VitalStatistics::NameValue;

use strict;
use warnings;
use Carp;

sub new {
    my( $pkg ) = @_;

    my $self = bless {}, $pkg;
    return $self;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub value {
    my( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_value'} = $value;
    }
    return $self->{'_value'};
}

sub label {
    my( $self, $label ) = @_;
    
    if ($label) {
        $self->{'_label'} = $label;
    }
    return $self->{'_label'};
}



1;

__END__

=head1 NAME - Hum::Chromosome::VitalStatistics::NameValue

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

