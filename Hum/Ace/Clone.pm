
### Hum::Ace::Clone

package Hum::Ace::Clone;

use strict;
use warnings;
use Carp;
use Hum::Sort 'ace_sort';

sub new {
    my ($pkg) = @_;
    
    return bless {}, $pkg;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub clone_name {
    my( $self, $clone_name ) = @_;
    
    if ($clone_name) {
        $self->{'_clone_name'} = $clone_name;
    }
    return $self->{'_clone_name'};
}

sub sequence_length {
    my( $self, $sequence_length ) = @_;
    
    if (defined $sequence_length) {
        $self->{'_sequence_length'} = $sequence_length;
    }
    return $self->{'_sequence_length'};
}

sub accession {
    my( $self, $accession ) = @_;
    
    if ($accession) {
        $self->{'_accession'} = $accession;
    }
    return $self->{'_accession'} || confess "accession not set";
}

sub sequence_version {
    my( $self, $sequence_version ) = @_;
    
    if ($sequence_version) {
        $self->{'_sequence_version'} = $sequence_version;
    }
    return $self->{'_sequence_version'};
}

sub accession_version {
    my $self = shift;
    
    if (@_) {
        confess "read-only method - got arguments: @_";
    }
    return $self->accession . "." . $self->sequence_version;
}

sub assembly_start {
    my( $self, $assembly_start ) = @_;
    
    if ($assembly_start) {
        $self->{'_assembly_start'} = $assembly_start;
    }
    return $self->{'_assembly_start'};
}

sub assembly_end {
    my( $self, $assembly_end ) = @_;
    
    if ($assembly_end) {
        $self->{'_assembly_end'} = $assembly_end;
    }
    return $self->{'_assembly_end'};
}

sub assembly_strand {
    my( $self, $assembly_strand ) = @_;
    
    if (defined $assembly_strand) {
        confess "Illegal assembly_strand '$assembly_strand'; must be '1', '-1' or '0'"
            unless $assembly_strand =~ /^(-?1|0)$/;
        $self->{'_assembly_strand'} = $assembly_strand
    }
    $self->{'_assembly_strand'};
}

sub display_assembly_strand {
    my $self = shift;
    
    if (@_) {
        confess "read-only method - got arguments: @_";
    }
    my $strand = $self->assembly_strand;
    if ($strand == 1) {
        return 'Fwd';
    }
    elsif ($strand == -1) {
        return 'Rev';
    }
    elsif ($strand == 0) {
        return 'Both';
    }
    else {
        return;
    }
}

sub golden_start {
    my( $self, $golden_start ) = @_;
    
    if ($golden_start) {
        $self->{'_golden_start'} = $golden_start;
    }
    return $self->{'_golden_start'} || confess "golden_start not set";
}

sub golden_end {
    my( $self, $golden_end ) = @_;
    
    if ($golden_end) {
        $self->{'_golden_end'} = $golden_end;
    }
    return $self->{'_golden_end'} || confess "golden_end not set";
}

sub description {
    my( $self, $description ) = @_;
    
    if ($description) {
        $self->{'_description'} = $description;
    }
    return $self->{'_description'};
}

sub drop_description {
    my ($self) = @_;
    
    $self->{'_description'} = undef;
}

sub add_keyword {
    my ($self, $keyword) = @_;

    $self->{'_keywords_are_sorted'} = 0;
    push(@{ $self->{'_keywords'} }, $keyword);
}

sub get_all_keywords {
    my ($self) = @_;

    if ($self->{'_keywords'}) {
        my $key = $self->{'_keywords'};
        unless ($self->{'_keywords_are_sorted'}) {
            @$key = sort { ace_sort($a, $b) } @$key;
            $self->{'_keywords_are_sorted'} = 1;
        }
        return @$key;
    }
    else {
        return;
    }
}

sub drop_all_keywords {
    my ($self) = @_;
    
    $self->{'_keywords'} = undef;
}

sub add_remark {
    my ($self, $remark) = @_;

    $self->{'_remarks_are_sorted'} = 0;
    push(@{ $self->{'_remarks'} }, $remark);
}

sub get_all_remarks {
    my ($self) = @_;

    if ($self->{'_remarks'}) {
        my $rem = $self->{'_remarks'};
        unless ($self->{'_remarks_are_sorted'}) {
            @$rem = sort { ace_sort($a, $b) } @$rem;
            $self->{'_remarks_are_sorted'} = 1;
        }
        return @$rem;
    }
    else {
        return;
    }
}

sub drop_all_remarks {
    my ($self) = @_;
    
    $self->{'_remarks'} = undef;
}

sub clone {
    my ($self) = @_;
    
    my $new = ref($self)->new;
    foreach my $method (qw{
        name
        clone_name
        sequence_length
        accession
        sequence_version
        assembly_start
        assembly_end
        assembly_strand
        golden_start
        golden_end
        description
        })
    {
        $new->$method($self->$method());
    }
    
    foreach my $keyword ($self->get_all_keywords) {
        $new->add_keyword($keyword);
    }
    foreach my $remark ($self->get_all_remarks) {
        $new->add_remark($remark);
    }
    
    return $new;
}

sub ace_string {
    my ($self) = @_;
    
    my $name = $self->name;
    my $obj_start = qq{\nSequence "$name"\n};
    
    my $str = $obj_start;
    foreach my $tag (qw{
        keyword
        Annotation_remark
        EMBL_dump_info
        })
    {
        $str .= qq{-D $tag\n};
    }
    
    $str .= $obj_start;
    foreach my $kw ($self->get_all_keywords) {
    	$str .= qq{keyword "$kw"\n};
    }
    if (my $de = $self->description) {
        $str .= qq{EMBL_dump_info DE_line "$de"\n};
    }
    foreach my $rem ($self->get_all_remarks) {
        $str .= qq{Annotation_remark "$rem"\n};
    }
    
    return $str;
}

sub express_data_fetch {
    my( $self, $ace ) = @_;

    my $name = $self->name;
    
    # These raw_queries are much faster than
    # fetching the whole Genome_Sequence object!
    $ace->raw_query("find Sequence $name");

    # This is a clone component, so we only store the sequence length
    my ($dna_txt) = $ace->values_from_tag('DNA');
    my $length;
    if ($dna_txt) {
        $length = $dna_txt->[1]
            or confess "No length next to DNA in Sequence '$name'";
    }
    elsif (my ($lt) = $ace->values_from_tag('Length')) {
        $length = $lt->[0];
    }
    $self->sequence_length($length);
    warn "Clone sequence '$name' is '$length' bp long\n";

    # But we also record the accession and sv
    if (my ($acc) = $ace->values_from_tag('Accession')) {
        $self->accession($acc->[0]);
    }
    if (my ($sv) = $ace->values_from_tag('Sequence_version')) {
        $self->sequence_version($sv->[0]);
    }
    # And the value of the clone tag
    if (my ($cl) = $ace->values_from_tag('Clone')) {
        $self->clone_name($cl->[0]);
    }

    # Get start and end on golden path
    $self->set_golden_start_end_from_NonGolden_Features($ace);

    foreach my $keyword ($ace->values_from_tag('Keyword')) {
        if (defined($keyword->[0])) {
            $self->add_keyword($keyword->[0]);
        }
    }

    foreach my $remark ($ace->values_from_tag('Annotation_remark')) {
        if (defined($remark->[0])) {
            $self->add_remark($remark->[0]);
        }
    }

    my $dumptxt = $ace->AceText_from_tag('EMBL_dump_info');
    if (my ($embldump) = $dumptxt->get_values('EMBL_dump_info.DE_line')) {
        $self->description($embldump->[0]);
    }
}

# Could get this information from the AGP_Fragment Align
# tags in the Assembly object, but it is simpler to use
# these "NonGolden" features.
sub set_golden_start_end_from_NonGolden_Features {
    my( $self, $ace ) = @_;
    
    my $length = $self->sequence_length
      or confess "sequence length not set";
    
    my $clone_name = $self->name;
    $ace->raw_query("find Sequence $clone_name");
    my $txt = $ace->AceText_from_tag('Feature');
    my( $g_start, $g_end );
    foreach my $f ($txt->get_values('Feature."?NonGolden')) {
        my ($start, $end) = @$f;
        if ($start == 1) {
            $g_start = $end + 1;
            $self->golden_start($g_start);
        }
        elsif ($end == $length) {
            $g_end = $start - 1;
            $self->golden_end($g_end);
        }
    }
    $self->golden_start(1) unless $g_start;
    $self->golden_end($length) unless $g_end;
}


1;

__END__

=head1 NAME - Hum::Ace::Clone

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

