
### Hum::Blast::AceFormatter

package Hum::Blast::AceFormatter;

use strict;
use warnings;
use Carp;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub acedb_method_name {
    my( $self, $method_name ) = @_;
    
    if ($method_name) {
        $self->{'_acedb_method_name'} = $method_name;
    }
    return $self->{'_acedb_method_name'};
}

sub acedb_homol_tag {
    my( $self, $homol_tag ) = @_;
    
    if ($homol_tag) {
        $self->{'_acedb_homol_tag'} = $homol_tag;
    }
    return $self->{'_acedb_homol_tag'};
}

sub db_prefix {
    my( $self, $prefix ) = @_;
    
    if ($prefix) {
        $self->{'_db_prefix'} = $prefix;
    }
    return $self->{'_db_prefix'};
}

sub query_name {
    my( $self, $query ) = @_;
    
    if ($query) {
        $self->{'_query_name'} = $query;
    }
    return $self->{'_query_name'};
}

sub format_Subject {
    my( $self, $subject ) = @_;
    
    my( $isa_subject );
    eval{ $isa_subject = $subject->isa('Hum::Blast::Subject') };
    unless ($isa_subject) {
        confess("Argument '$subject' is not a 'Hum::Blast::Subject' object");
    }
    
    # Get essential parameters from object
    my $query_name = $self->query_name
        or confess "query_name not defined";
    my $acedb_homol_tag = $self->acedb_homol_tag
        or confess "acedb_homol_tag not defined";
    my $acedb_method_name = $self->acedb_method_name
        or confess "acedb_method_name not defined";
    
    my $prefix = $self->db_prefix;
    my $subject_name = $subject->subject_name
        or confess "subject_name not defined";
    $subject_name = "$prefix$subject_name" if $prefix;

    my $query_format   = qq{\nSequence "$query_name"\n};
    my $subject_format = qq{\nSequence "$subject_name"\n-D $acedb_homol_tag "$query_name"\n};
    foreach my $hsp ($subject->get_all_HSPs) {
        my $score = $hsp->score or confess "No score in HSP";
        my(@coords) = map $hsp->$_(), qw{ query_start query_end subject_start subject_end };
        
        # Check for bad coordinates
        foreach my $c (@coords) {
            if ($c < 1) {
                confess "Bad coordinate in [@coords]\n(query_start query_end subject_start subject_end)";
            }
        }
        
        $query_format   .= qq{$acedb_homol_tag  "$subject_name"  "$acedb_method_name"  $score  @coords\n};
        $subject_format .= qq{$acedb_homol_tag  "$query_name"  "$acedb_method_name"  $score  @coords[2,3,0,1]\n};
    }
    
    return $query_format . $subject_format;
}

1;

__END__

=head1 NAME - Hum::Blast::AceFormatter

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

