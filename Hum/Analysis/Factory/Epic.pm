
### Hum::Analysis::Factory::Epic

package Hum::Analysis::Factory::Epic;

use strict;
use warnings;
use Hum::Analysis::Parser::Epic;
use Hum::FastaFileIO;
use Hum::Conf qw(GRIT_SOFTWARE);
use Carp;
use Cwd;

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
    my $query_file   = $self->_get_file_path('query', $tmp, $query);
    my $subject_file = $self->_get_file_path('subject', $tmp, $subject);

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

sub _get_file_path {
    my ($self, $name, $dir, $thing) = @_;

    my $type = ref($thing);

    my ($file);

    unless ($type) {
        $file = $thing;
        if (-f $file) {

            # Make path absolute if not
            if ($file !~ m{^/}) {
                $file = cwd() . '/' . $file;
            }
            return $file;
        }
        else {
            confess "No such file '$file'";
        }
    }

    my ($seq_list);
    if ($type eq 'ARRAY') {
        $seq_list = $thing;
    }
    else {
        $seq_list = [$thing];
    }

    if (grep !$_->isa('Hum::Sequence'), @$seq_list) {
        confess "Non Hum::Sequence in '@$seq_list'";
    }

    $file = "$dir/$name.seq";
    my $seq_out = Hum::FastaFileIO->new_DNA_IO("> $file");
    $seq_out->write_sequences(@$seq_list);
    return $file;
}

{
    my $counter = 0;

    sub make_tmp_dir {
        my ($self) = @_;

        $counter++;
        my $tmp_dir_name = "/tmp/cm_tmp.$$.$counter";
        mkdir($tmp_dir_name, 0777) or confess "Can't mkdir '$tmp_dir_name' : $!";

        #warn "Made '$tmp_dir_name'";
        return $tmp_dir_name;
    }
}

1;

__END__

=head1 NAME - Hum::Analysis::Factory::Epci

=head1 AUTHOR

Kim Brugger B<email> kb8@sanger.ac.uk

