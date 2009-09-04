
### Hum::Ace::SeqFeature::Simple

package Hum::Ace::SeqFeature::Simple;

use strict;
use warnings;
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
    if ($self->seq_strand == 1) {
        $start = $self->seq_start;
        $end   = $self->seq_end;
    }
    else {
        $start = $self->seq_end;
        $end   = $self->seq_start;
    }

    return sprintf qq{Feature "%s" %d %d %.3f "%s"\n},
      $self->method_name,
      $start, $end,
      $self->score, $self->text;
}

sub zmap_xml_feature_tag {
    my ($self) = @_;
    
    return sprintf qq{<feature name="%s" start="%d" end="%d" strand="%s" style="%s" score="%.3f"></feature>\n},
        $self->method_name,
        $self->seq_start,
        $self->seq_end,
        $self->seq_strand == -1 ? '-' : '+',
        $self->method_name,
        $self->score;

    # This will be how it works in the future:
    # return sprintf qq{<feature id="Sequence|%s|Feature" object_name="%s" start="%d" end="%d" strand="%s" score="%.3f" remark="%s" />\n},
    #     $self->seq_name,
    #     $self->seq_start,
    #     $self->seq_end,
    #     $self->seq_strand == -1 ? '-' : '+',
    #     $self->score,
    #     $self->text;
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

