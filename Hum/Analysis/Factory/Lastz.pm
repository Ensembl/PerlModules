
### Hum::Analysis::Factory::Lastz

package Hum::Analysis::Factory::Lastz;

use strict;
use warnings;
use Carp;

use Hum::Analysis::Parser::AXT;

use base 'Hum::Analysis::Factory';

sub run {
    my ($self, $query, $subject) = @_;

    my $tmp = $self->make_tmp_dir;
    my   $query_file = $self->get_file_path('query',   $tmp, $query);
    my $subject_file = $self->get_file_path('subject', $tmp, $subject);

    my $cmd_pipe = $self->make_command_pipe($tmp, $query_file, $subject_file);
    open my $fh, $cmd_pipe or confess "Can't open pipe '$cmd_pipe' : $!";

    my $parser = Hum::Analysis::Parser::AXT->new;
    $parser->results_filehandle($fh);
    $parser->temporary_directory($tmp);
    return $parser;
}

sub chain {
    my ($self, $flag) = @_;

    if (defined $flag) {
        $self->{'_chain'} = $flag ? 1 : 0;
    }
    return $self->{'_chain'} || 0;
}

sub make_command_pipe {
    my ($self, $dir, $query_file, $subject_file) = @_;

    my @args = ('--format=axt', '--identity=95', '--step=20', '--match=1,5');
    if ($self->chain) {
        push(@args, '--chain');
    }
    my $cmd_pipe = "cd $dir; lastz $query_file $subject_file @args |";
    return $cmd_pipe;
}


1;

__END__

=head1 NAME - Hum::Analysis::Factory::Lastz

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

