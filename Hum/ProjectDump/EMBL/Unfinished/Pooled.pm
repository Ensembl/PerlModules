
### Hum::ProjectDump::EMBL::Unfinished::Pooled

package Hum::ProjectDump::EMBL::Unfinished::Pooled;

use strict;
use warnings;
use Carp;
use Hum::ProjectDump::EMBL;
use Hum::Submission qw{
    prepare_statement
    accession_from_sanger_name
};
use Hum::Tracking qw{
    prepare_track_statement
    parent_project
    is_shotgun_complete                    
};

use base qw{ Hum::ProjectDump::EMBL::Unfinished };

sub create_new_dump_object {
    my( $pkg, $project, $force_flag ) = @_;
    my $pdmp = $pkg->SUPER::create_new_dump_object($project, $force_flag);
    # get the parent project acc and set it as project secondary acc
    my $parent = parent_project($project);
    if(!$parent) {
        die "No parent project name associated with $project\n";
    }
    $pdmp->parentproject($parent);
    # the pooled project name is also the sequence name
    my $second_acc = accession_from_sanger_name($parent);
    if(!$second_acc){
        die "No parent project accession for $project\n";
    }
    my $seen;
    foreach my $sec ($pdmp->secondary){
        $seen = 1 if $sec eq $second_acc;
    }
    $pdmp->add_secondary($second_acc) unless $seen;


    return $pdmp;    
}


sub parentproject {
    my ( $pdmp, $parent ) = @_;
    $pdmp->{'_parent'} = $parent if $parent;


    return $pdmp->{'_parent'};
}

sub add_Headers {
    my( $pdmp, $embl, $contig_map ) = @_;

    $pdmp->add_external_draft_CC($embl);

    my $project = $pdmp->project_name;

    my $draft_or_unfinished = is_shotgun_complete($project)
        ? 'working draft'
        : 'unfinished';

    my @comment_lines = (
        $pdmp->seq_center_lines,
        '-------------- Project Information',
        "Center project name: $project",
        '-------------- Summary Statistics',
        'Assembly program: XGAP4; version 4.5',
        $pdmp->make_read_comments(),
        $pdmp->make_consensus_quality_summary(),
        $pdmp->make_consensus_length_report(),
        $pdmp->make_q20_depth_report(),
        '--------------',
        "* NOTE: This is a '$draft_or_unfinished' sequence. This currently".
        " represents a proportion of the complete clone insert.".
        " Sequence will be added, as appropriate, during the".
        " finishing process. It currently consists of ". scalar(@$contig_map) ." contigs.".
        " The true order of the pieces is".
        " not known and their order in this sequence record is".
        " arbitrary.  Where the contigs adjacent to the vector can".
        " be identified, they are labelled with 'clone_end' in the".
        " feature table.  Some order and orientation information".
        " can tentatively be deduced from paired sequencing reads".
        " which have been identified to span the gap between two".
        " contigs.  These are labelled as part of the same".
        " 'fragment_chain', and the order and relative orientation".
        " of the pieces within a fragment_chain is reflected in".
        " this file.  Gaps between the contigs are represented as".
        " runs of N, but the exact sizes of the gaps are unknown.".
        " This clone-specific sequence was deconvoluted from pooled".
        " multi-clone record ".join(",",$pdmp->secondary)."."
    );

    if ($pdmp->is_cancelled) {
        push(@comment_lines,
            "* ",
            "* The sequencing of this clone has been cancelled. The most",
            "* likely reason for this is that its sequence is redundant,",
            "* and therefore not needed to complete the finished genome.",
            "* ",
            );
    } else {
        push(@comment_lines,
            "* This record will be updated with the finished sequence as",
            "* soon as it is available and the accession number will be",
            "* preserved.",
            );
    }

    $embl->newCC->list(
        @comment_lines,
        $pdmp->make_fragment_summary($embl, $contig_map),
    );   

    $pdmp->add_extra_headers($embl, 'comment');
}


1;

__END__

=head1 NAME - Hum::ProjectDump::EMBL::Unfinished::Pooled

=head1 AUTHOR

Mustapha Larbaoui B<email> ml6@sanger.ac.uk
