
### Hum::AnaStatus::Sequence

package Hum::AnaStatus::Sequence;

use strict;

sub new_from_sequence_name {

}

sub status {

}

sub set_status {

}


1;

__END__

=head1 NAME - Hum::AnaStatus::Sequence

=head1 MEHTHODS

=over 4

=item new_from_sequence_name

    my $ana_seq = Hum::AnaStatus::Sequence->new_from_sequence_name('dJ354B12');

Given a humace sequence name, returns a new
object, or throws an exception if it isn't found
in the database.

=item set_status

    $ana_seq->set_status(3);

=item set_annotator_uname

    $ana_seq->set_annotator_uname('ak1');

=item new_AceFile

    my $ace_file = $ana_seq->new_AceFile($acefile_name);

=item lock_sequence

=item unlock_sequence

=back

=head1 Read-only methods

The following methods just report the values of
their fields, they dont' allow you to set them.

=over 4

=item ana_seq_id

=item seq_id

=item current_status

The number of the status currently held

=item current_status_date

The date the current status was assigned.

=item current_status_description

The description of this status

=item analysis_directory

Analysis directory location

=item analysis_priority

Assigned analysis priority

=item annotator_uname

The user name of the annotator assigned to
annotate this sequence.

=item get_all_AceFiles

Returns a list of Hum::AnaStatus::AceFile objects
associated with this sequence.

=back

=head1 AUTHOR

Javier Santoyo-Lopez B<email> jsl@sanger.ac.uk

