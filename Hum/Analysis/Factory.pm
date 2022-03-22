=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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


### Hum::Analysis::Factory

package Hum::Analysis::Factory;

use strict;
use warnings;
use Carp;

use Hum::FastaFileIO;

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}

sub get_file_path {
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
        my $tmp_dir_name = "/tmp/align_factory_tmp.$$.$counter";
        mkdir($tmp_dir_name, 0777) or confess "Can't mkdir '$tmp_dir_name' : $!";

        #warn "Made '$tmp_dir_name'";
        return $tmp_dir_name;
    }
}


1;

__END__

=head1 NAME - Hum::Analysis::Factory

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

