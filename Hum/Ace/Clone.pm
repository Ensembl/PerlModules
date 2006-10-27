
### Hum::Ace::Clone

package Hum::Ace::Clone;

use strict;
use Carp;

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
        confess "Illegal assembly_strand '$assembly_strand'; must be '1' or '-1'"
            unless $assembly_strand =~ /^-?1$/;
        $self->{'_assembly_strand'} = $assembly_strand
    }
    return $self->{'_assembly_strand'} || confess "assembly_strand not set";
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

sub add_Keyword {
    my($self,$keyword)=@_;
    push(@{$self->{'_Keywords'}},$keyword);
}

sub get_all_Keywords {
    my($self)=@_;
    if($self->{'_Keywords'}){
        return @{$self->{'_Keywords'}};
    }else{
        return ();
    }
}

sub add_Remark {
    my($self,$remark)=@_;
    push(@{$self->{'_Remarks'}},$remark);
}
sub get_all_Remarks {
    my($self)=@_;
    if($self->{'_Remarks'}){
        return @{$self->{'_Remarks'}};
    }else{
        return ();
    }
}

sub description {
    my( $self, $description ) = @_;
    
    if ($description) {
        $self->{'_description'} = $description;
    }
    return $self->{'_description'};
}

sub ace_string {
    my ($self) = @_;
    
    my $name = $self->name;
    my $obj_start = qq{\nSequence "$name"\n};
    
    my $str = $obj_start;
    foreach my $tag (qw{
        Keyword
        Annotation_remark
        EMBL_dump_info
        })
    {
        $str .= qq{-D $tag\n};
    }
    
    $str .= $obj_start;
    foreach my $kw ($self->get_all_Keywords) {
    	$str .= qq{Keyword "$kw"\n};
    }
    if (my $de = $self->description) {
        $str .= qq{EMBL_dump_info DE_line "$de"\n};
    }
    foreach my $rem ($self->get_all_Remarks) {
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
    my $name = $self->name;
    my ($dna_txt) = $ace->values_from_tag('DNA');
    my $length = $dna_txt->[1];
    $self->sequence_length($length);

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
            $self->add_Keyword($keyword->[0]);
        }
    }

    foreach my $remark ($ace->values_from_tag('Annotation_remark')) {
        if (defined($remark->[0])) {
            $self->add_Remark("Annotation_remark- " . $remark->[0]);
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
