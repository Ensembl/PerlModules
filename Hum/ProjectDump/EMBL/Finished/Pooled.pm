
### Hum::ProjectDump::EMBL::Finished::Pooled

package Hum::ProjectDump::EMBL::Finished::Pooled;

use strict;
use warnings;
use Carp;

use Hum::Submission qw{
  accession_from_sanger_name
};
use Hum::Tracking qw{
  parent_project
};

use base qw{ Hum::ProjectDump::EMBL::Finished };

sub secondary {
    my ($self) = @_;

    unless ($self->{'_parent_acc_fetched'}) {
        my $parent = parent_project($self->project_name)
            or confess "No parent project";
        # the pooled project name will always be the sequence name
        my $second_acc = accession_from_sanger_name($parent);
        if (!$second_acc) {
            die "No accession for parent project $parent\n";
        }
        my $seen;
        foreach my $sec ($self->SUPER::secondary) {
            $seen = 1 if $sec eq $second_acc;
        }
        $self->add_secondary($second_acc) unless $seen;        
        $self->{'_parent_acc_fetched'} = 1;
    }

    return $self->SUPER::secondary;
}


1;

__END__

=head1 NAME - Hum::ProjectDump::EMBL::Finished::Pooled

=head1 AUTHOR

Mustapha Larbaoui B<email> ml6@sanger.ac.uk
