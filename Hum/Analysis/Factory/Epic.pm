=head1 LICENSE

Copyright [2018-2021] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


### Hum::Analysis::Factory::Epic

package Hum::Analysis::Factory::Epic;

use strict;
use warnings;
use Hum::Analysis::Parser::Epic;
use Hum::Conf qw(GRIT_SOFTWARE);
use Carp;
use Cwd;

use base 'Hum::Analysis::Factory';


sub new {
    my ($pkg) = @_;

	my $self = {
		'_dovetail_threshold' => 400,
	};

    return bless $self, $pkg;
}

sub set_contained_mode {
	my ($self) = @_;	
	
	$self->{'_dovetail_threshold'} = 1000000;
	
	return;
}

sub run {
    my ($self, $query, $subject) = @_;

    my $tmp          = $self->make_tmp_dir;
    my $query_file   = $self->get_file_path('query', $tmp, $query);
    my $subject_file = $self->get_file_path('subject', $tmp, $subject);

    my $cmd_pipe = $self->make_command_pipe($tmp, $query_file, $subject_file);

    open my $fh, $cmd_pipe or confess "Can't open pipe '$cmd_pipe' : $!";

    my $parser = Hum::Analysis::Parser::Epic->new;
    $parser->results_filehandle($fh);
    $parser->temporary_directory($tmp);

    return $parser;
}

sub make_command_pipe {
    my ($self, $dir, $query_file, $subject_file) = @_;

    my $cmd_pipe = "cd $dir; $GRIT_SOFTWARE/epic.pl -Bac -D $self->{_dovetail_threshold} $query_file $subject_file |";
    # warn "Running: $cmd_pipe";
    return $cmd_pipe;
}


1;

__END__

=head1 NAME - Hum::Analysis::Factory::Epci

=head1 AUTHOR

Kim Brugger B<email> kb8@sanger.ac.uk

