
### Hum::Ace::SeqFeature::Simple

package Hum::Ace::SeqFeature::Simple;

use strict;
use Carp;
use base 'Hum::Ace::SeqFeature';

sub Method {
    my ($self, $Method) = @_;

    if ($Method) {
        $self->{'_Method'} = $Method;
    }
    return $self->{'_Method'};
}

sub method_name {
    my $self = shift;

    confess "read-only method" if @_;

    my $meth = $self->Method or return;
    return $meth->name;
}

sub text {
    my ($self, $text) = @_;

    if ($text) {
        $self->{'_text'} = $text;
    }
    return $self->{'_text'};
}

sub ace_string {
    my ($self) = @_;

    my ($start, $end);
    if ($self->strand == 1) {
        $start = $self->start;
        $end   = $self->end;
    }
    else {
        $start = $self->end;
        $end   = $self->start;
    }

    return sprintf qq{Feature "%s" %d %d %.3f "%s"\n},
      $self->method_name,
      $start, $end,
      $self->score, $self->text;
}

1;

__END__

=head1 NAME - Hum::Ace::SeqFeature::Simple

=head1 DESCRIPTION

Subclass of C<Hum::Ace::SeqFeature> used to
represent simple features edited in otterlace,
such as polyA signals and sites.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

