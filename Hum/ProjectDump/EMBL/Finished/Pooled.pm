
### Hum::ProjectDump::EMBL::Finished::Pooled

package Hum::ProjectDump::EMBL::Finished::Pooled;

use strict;
use warnings;
use Carp;

use Hum::Submission qw{
  prepare_statement
  accession_from_sanger_name
};
use Hum::Tracking qw{
  prepare_track_statement
  parent_project
  is_shotgun_complete
};

use base qw{ Hum::ProjectDump::EMBL::Finished };

sub new {
    my ($pkg, $parent) = @_;

    my $pdmp = bless {}, $pkg;
    $pdmp->add_parent($parent) if $parent;

    return $pdmp;
}

sub new_from_sanger_id {
    my ($pkg, $sanger_id) = @_;

    my $pdmp = $pkg->SUPER::new_from_sanger_id($sanger_id);
 
    my $project = $pdmp->project_name;

    # set parent accession as secondary id
    my $parent = parent_project($project);
    $pdmp->add_parent($parent);

    return $pdmp;
}

sub add_parent {
    my ($pdmp, $parent) = @_;

    if (!$parent) {
        die "No parent project name provided\n";
    }
    $pdmp->parentproject($parent);

    # the pooled project name is also the sequence name
    my $second_acc = accession_from_sanger_name($parent);
    if (!$second_acc) {
        die "No accession for parent project $parent\n";
    }
    my $seen;
    foreach my $sec ($pdmp->secondary) {
        $seen = 1 if $sec eq $second_acc;
    }
    $pdmp->add_secondary($second_acc) unless $seen;
}

sub parentproject {
    my ($pdmp, $parent) = @_;
    $pdmp->{'_parent'} = $parent if $parent;

    return $pdmp->{'_parent'};
}

sub is_pool {
    return 1;
}

1;

__END__

=head1 NAME - Hum::ProjectDump::EMBL::Finished::Pooled

=head1 AUTHOR

Mustapha Larbaoui B<email> ml6@sanger.ac.uk
