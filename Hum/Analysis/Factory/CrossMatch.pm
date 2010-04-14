
### Hum::Analysis::Factory::CrossMatch

package Hum::Analysis::Factory::CrossMatch;

use strict;
use warnings;
use Hum::Analysis::Parser::CrossMatch;
use Hum::FastaFileIO;
use Carp;
use Cwd;

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}

sub min_match_length {
    my( $self, $min_match_length ) = @_;
    
    if ($min_match_length) {
        $self->{'_min_match_length'} = $min_match_length;
    }
    return $self->{'_min_match_length'} || 30;
}

sub bandwidth {
    my( $self, $bandwidth ) = @_;
    
    if ($bandwidth) {
        $self->{'_bandwidth'} = $bandwidth;
    }
    return $self->{'_bandwidth'} || 14;
}

sub gap_extension_penalty {
    my( $self, $gap_extension_penalty ) = @_;
    
    if (defined $gap_extension_penalty) {
        $self->{'_gap_extension_penalty'} = $gap_extension_penalty;
    }
    return $self->{'_gap_extension_penalty'} || -3;
}

sub show_all_matches {
    my( $self, $show_all_matches ) = @_;
    
    if (defined $show_all_matches) {
        $self->{'_show_all_matches'} = $show_all_matches ? 1 : 0;
    }
    return $self->{'_show_all_matches'} || 0;
}

sub show_alignments {
    my( $self, $show_alignments ) = @_;
    
    if (defined $show_alignments) {
        $self->{'_show_alignments'} = $show_alignments ? 1 : 0;
    }
    return $self->{'_show_alignments'} || 0;
}

sub run {
    my( $self, $query, $subject ) = @_;

    my $tmp = $self->make_tmp_dir;
    my   $query_file = $self->_get_file_path('query',   $tmp, $query);
    my $subject_file = $self->_get_file_path('subject', $tmp, $subject);

    my $cmd_pipe = $self->make_command_pipe($tmp, $query_file, $subject_file);
    open my $fh, $cmd_pipe or confess "Can't open pipe '$cmd_pipe' : $!";

    my $parser = Hum::Analysis::Parser::CrossMatch->new;
    $parser->results_filehandle($fh);
    $parser->temporary_directory($tmp);
    $parser->crossmatch_log_file("$query_file.log");
    return $parser;
}

sub make_command_pipe {
    my( $self, $dir, $query_file, $subject_file ) = @_;

    my $min_match = $self->min_match_length;
    my $bandwidth = $self->bandwidth;
    my $gap_ext   = $self->gap_extension_penalty;

    my $cmd_pipe = "cd $dir;  ulimit -v 1800000; cross_match -gap_ext $gap_ext -minmatch $min_match -bandwidth $bandwidth";

    if ($self->show_alignments) {
        $cmd_pipe .= ' -alignments';
    }
    if ($self->show_all_matches) {
        $cmd_pipe .= ' -masklevel 101';
    }
    $cmd_pipe .= " $query_file $subject_file 2>/dev/null |";
    # $cmd_pipe .= " $query_file $subject_file |";
    #warn "PIPE = $cmd_pipe";
    return $cmd_pipe;
}

sub _get_file_path {
    my( $self, $name, $dir, $thing ) = @_;
    
    my $type = ref($thing);
    
    my( $file );
    
    unless ($type) {
        $file = $thing;
        if (-f $file) {
            # Make path absolute if not
            if ($file !~ m{^/}) {
                $file = cwd() . '/' . $file;
            }
            return $file;
        } else {
            confess "No such file '$file'";
        }
    }
    
    my( $seq_list );
    if ($type eq 'ARRAY') {
        $seq_list = $thing;
    } else {
        $seq_list = [$thing];
    }
    
    if (grep ! $_->isa('Hum::Sequence'), @$seq_list) {
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
        my( $self ) = @_;

        $counter++;
        my $tmp_dir_name = "/tmp/cm_tmp.$$.$counter";
        mkdir($tmp_dir_name, 0777) or confess "Can't mkdir '$tmp_dir_name' : $!";
        #warn "Made '$tmp_dir_name'";
        return $tmp_dir_name;
    }
}


1;

__END__

=head1 NAME - Hum::Analysis::Factory::CrossMatch

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

