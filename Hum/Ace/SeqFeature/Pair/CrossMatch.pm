
### Hum::Ace::SeqFeature::Pair::CrossMatch

package Hum::Ace::SeqFeature::Pair::CrossMatch;

use strict;
use Hum::Ace::SeqFeature::Pair;
use vars '@ISA';

@ISA = ('Hum::Ace::SeqFeature::Pair');


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

sub percent_identity {
    my( $self ) = @_;
    
    return 100
        - $self->percent_substitution
        - $self->percent_insertion
        - $self->percent_deletion;
}

sub alignment_string {
    my( $self, $string ) = @_;
    
    if ($string) {
        $self->{'_alignment_string'} = $string;
    }
    return $self->{'_alignment_string'};
}

1;

__END__

=head1 NAME - Hum::Ace::SeqFeature::Pair::CrossMatch

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

