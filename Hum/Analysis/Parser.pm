
### Hum::Analysis::Parser

package Hum::Analysis::Parser;

use strict;
use warnings;
use Carp;
use File::Path 'rmtree';

sub new {
    my ($pkg) = @_;

    return bless {}, $pkg;
}

sub get_all_Features {
    my ($self) = @_;

    my $all = [];
    while (my $f = $self->next_Feature) {
        push(@$all, $f);
    }
    return $all;
}

sub results_filehandle {
    my ($self, $results_filehandle) = @_;

    if ($results_filehandle) {
        $self->{'_results_filehandle'} = $results_filehandle;
    }
    return $self->{'_results_filehandle'};
}

sub close_results_filehandle {
    my ($self) = @_;

    if (my $fh = $self->{'_results_filehandle'}) {
        close($fh) or confess "Error from results filehandle exit($?)";
    }

    $self->{'_results_filehandle'} = undef;
}

sub temporary_directory {
    my ($self, $temporary_directory) = @_;

    if ($temporary_directory) {
        $self->{'_temporary_directory'} = $temporary_directory;
    }
    return $self->{'_temporary_directory'};
}

sub DESTROY {
    my ($self) = @_;

    if (my $dir = $self->temporary_directory) {
        # warn "Not removing '$dir'"; return;
        rmtree($dir);
    }
}

1;

__END__

=head1 NAME - Hum::Analysis::Parser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

