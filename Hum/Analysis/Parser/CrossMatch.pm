
### Hum::Analysis::Parser::CrossMatch

package Hum::Analysis::Parser::CrossMatch;

use strict;
use Carp;
use File::Path 'rmtree';

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub next_Feature {
    my( $self ) = @_;
    
    my $fh = $self->results_filehandle
        or confess "No filehandle to parse";
    while (<$fh>) {
        print;
    }
}

sub _current_feature {
    my( $self, $_current_feature ) = @_;
    
    if ($_current_feature) {
        $self->{'__current_feature'} = $_current_feature;
    }
    return $self->{'__current_feature'};
}

sub results_filehandle {
    my( $self, $results_filehandle ) = @_;
    
    if ($results_filehandle) {
        $self->{'_results_filehandle'} = $results_filehandle;
    }
    return $self->{'_results_filehandle'};
}

sub temporary_directory {
    my( $self, $temporary_directory ) = @_;
    
    if ($temporary_directory) {
        $self->{'_temporary_directory'} = $temporary_directory;
    }
    return $self->{'_temporary_directory'};
}

sub DESTROY {
    my( $self ) = @_;
    
    if (my $dir = $self->temporary_directory) {
        rmtree($dir);
    }
}

1;

__END__

=head1 NAME - Hum::Analysis::Parser::CrossMatch

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

