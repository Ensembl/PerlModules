
### Hum::SequenceOverlap

package Hum::SequenceOverlap;
use Hum::SequenceOverlap::Position;

use strict;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
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


1;

__END__

=head1 NAME - Hum::SequenceOverlap

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

