
### Hum::Ace::Locus

package Hum::Ace::Locus;

use strict;
use warnings;
use Carp qw{ confess cluck };

sub new {
    my( $pkg ) = shift;
    
    return bless {
        '_CloneSeq_list'    => [],
        '_exon_hash'        => {},
        }, $pkg;
}

sub new_from_ace {
    my( $pkg, $ace ) = @_;
    
    my $self = $pkg->new;
    $self->save_locus_info($ace);
    return $self;
}

sub new_from_ace_tag {
    my( $pkg, $ace ) = @_;
    
    my $self = $pkg->new;
    $self->save_locus_info($ace->fetch);
    return $self;
}

sub new_from_Locus {
    my ($old) = @_;

    my $new = ref($old)->new;

    $new->set_aliases( $old->list_aliases );
    $new->set_remarks( $old->list_remarks );
    
    foreach my $method (qw{
        name
        description
        gene_type_prefix
        is_truncated
        })
    {
        $new->$method( $old->$method() );
    }

    return $new;
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'} || confess "name not set";
}

sub previous_name {
    my( $self, $previous_name ) = @_;
    
    if ($previous_name) {
        $self->{'_previous_name'} = $previous_name;
    }
    return $self->{'_previous_name'};
}

sub drop_previous_name {
    my( $self ) = @_;
    
    if (my $prev = $self->{'_previous_name'}) {
        $self->{'_previous_name'} = undef;
        return $prev;
    } else {
        return;
    }
}

sub description {
    my( $self, $description ) = @_;
    
    if ($description) {
        $self->{'_description'} = $description;
    }
    return $self->{'_description'};
}

sub otter_id {
    my( $self, $otter_id ) = @_;
    
    if ($otter_id) {
        $self->{'_otter_id'} = $otter_id;
    }
    return $self->{'_otter_id'};
}

sub drop_otter_id {
    my( $self, $otter_id ) = @_;
    
    if (my $ott = $self->{'_otter_id'}) {
        $self->{'_otter_id'} = undef;
        return $ott;
    } else {
        return;
    }
}

sub author_name {
    my ($self, $name) = @_;
    
    if ($name) {
        $self->{'_author_name'} = $name;
    }
    return $self->{'_author_name'};
}


sub gene_type_prefix {
    my( $self, $gene_type_prefix ) = @_;
    
    # Can unset with empty string
    if (defined $gene_type_prefix) {
        $self->{'_gene_type_prefix'} = $gene_type_prefix;
    }
    return $self->{'_gene_type_prefix'} || '';
}

sub known {
    my ($self, $known_flag) = @_;
    
    if (defined $known_flag) {
        $self->{'_known_flag'} = $known_flag ? 1 : 0;
    }
    return $self->{'_known_flag'} || 0;
}

sub is_truncated {
    my( $self, $is_truncated ) = @_;
    
    #cluck "called is_truncated";
    
    if (defined $is_truncated) {
        $self->{'_is_truncated'} = $is_truncated ? 1 : 0;
    }
    return $self->{'_is_truncated'} || 0;
}

sub pre_otter_save_error {
    my ($self) = @_;

    my $err = '';
    $err .= $self->error_no_description;
    $err .= $self->error_alias_matches_name;
    return $err;
}

sub error_alias_matches_name {
    my ($self) = @_;

    my $name = $self->name;
    
    my $err = '';
    foreach my $alias ($self->list_aliases) {
        if ($alias eq $name) {
            $err .= qq{Alias '$alias' matches locus name\n};
        }
    }
    return $err;
}

sub error_no_description {
    my ($self) = @_;
    
    my $desc = $self->description;
    if ($desc and $desc =~ /\w{3,}/) {    # Potential to be more sophisticated
        return '';
    } else {
        return qq{No full name (description) in Locus\n};
    }    
}


sub save_locus_info {
    my( $self, $ace_locus ) = @_;

    #print STDERR $ace_locus->asString;
    $self->name($ace_locus->name);

    if (my $ott = $ace_locus->at('Otter.Locus_id[1]')) {
        $self->otter_id($ott->name);
    }

    if (my $aut = $ace_locus->at('Otter.Locus_author[1]')) {
        $self->author_name($aut->name);
    }

    if ($ace_locus->at('Otter.Truncated')) {
        $self->is_truncated(1);
        #warn $self->name, " is truncated";
    }

    if ($ace_locus->at('Type.Gene.Known')) {
        $self->known(1);
    }

    if (my $type = $ace_locus->at('Type_prefix[1]')) {
        $self->gene_type_prefix($type->name);
    }

    my( @aliases );
    foreach my $alias ($ace_locus->at('Alias[1]')) {
        my $alias_str = $alias->asString;
        chomp($alias_str);
        push(@aliases, $alias_str);
    }
    $self->set_aliases(@aliases);

    if (my $full = $ace_locus->at('Full_name[1]')) {
        my $txt = $full->name;
        $txt =~ s/\s+$//;
        $txt =~ s/\n/ /g;
        $self->description($txt);
    }

    my( @remarks );
    foreach my $rem ($ace_locus->at('Remark[1]')) {
        my $txt = $rem->name;
        $txt =~ s/\s+$//;
        $txt =~ s/\n/ /g;
        push(@remarks, $txt);
    }
    $self->set_remarks(@remarks);

    my( @annotation_remarks );
    foreach my $rem ($ace_locus->at('Annotation_remark[1]')) {
        my $txt = $rem->name;
        $txt =~ s/\s+$//;
        $txt =~ s/\n/ /g;
        push(@annotation_remarks, $txt);
    }
    $self->set_annotation_remarks(@annotation_remarks);
}

sub set_aliases {
    my( $self, @aliases ) = @_;
    
    $self->{'_Alias_name_list'} = [@aliases];
}

sub list_aliases {
    my( $self ) = @_;
    
    if (my $al = $self->{'_Alias_name_list'}) {
        return @$al;
    } else {
        return;
    }
}

sub set_remarks {
    my( $self, @remarks ) = @_;
    
    $self->{'_remark_list'} = [@remarks];
}

sub list_remarks {
    my( $self ) = @_;
    
    if (my $rl = $self->{'_remark_list'}) {
        return @$rl;
    } else {
        return;
    }
}

{
    my $aip = 'annotation in progress';

    sub annotation_in_progress {
        my ($self) = @_;

        my @rem = $self->list_remarks;
        foreach my $r (@rem) {
            if ($r eq $aip) {
                return 1;
            }
        }
        return 0;
    }

    sub set_annotation_in_progress {
        my ($self) = @_;

        my @rem = $self->list_remarks;
        foreach my $r (@rem) {
            if ($r eq $aip) {
                return 1;
            }
        }
        $self->set_remarks($aip, @rem);
        return 1;
    }

    sub unset_annotation_in_progress {
        my ($self) = @_;
        
        my @rem = $self->list_remarks;
        for (my $i = 0; $i < @rem; ) {
            if ($rem[$i] eq $aip) {
                splice(@rem, $i, 1);
            }
            else {
                $i++;
            }
        }
        $self->set_remarks(@rem);
        return 1;
    }
}

sub set_annotation_remarks {
    my( $self, @annotation_remarks ) = @_;
    
    $self->{'_annotation_remark_list'} = [@annotation_remarks];
}

sub list_annotation_remarks {
    my( $self ) = @_;
    
    if (my $rl = $self->{'_annotation_remark_list'}) {
        return @$rl;
    } else {
        return;
    }
}

sub ace_string {
    my( $self ) = @_;

    # Trap for $old_name parameter that we have removed in case anything still calls it
    if (@_ > 1) {
        confess "unexpected argument to ace_string";
    }

    my $ace = '';
    
    if ($self->otter_id and my $prev = $self->previous_name) {
        # Rename operation - we are taking the otter_id away
        # from the old locus.
        $ace .= qq{\nLocus : "$prev"\n}
            . qq{-D Locus_id\n};
    }

    my $name = $self->name;
    $ace .= qq{\nLocus : "$name"\n}
        . qq{-D Type_prefix\n}
        . qq{-D Type\n}
        . qq{-D Locus_author\n}
        . qq{-D Full_name\n}
        . qq{-D Remark\n}
        . qq{-D Annotation_remark\n}
        . qq{-D Alias\n}
        . qq{\n};

    my $txt = Hum::Ace::AceText->new;
    $txt->add_tag_values(['Locus', ':', $name]);

    ### Need to add locus type and positive sequences
    ### Are the ?Seqence tags pointing to Clone or SubSeqences?

    if (my $ott = $self->otter_id) {
        $txt->add_tag_values(['Locus_id', $ott]);
    }
    if (my $prefix = $self->gene_type_prefix) {
        $txt->add_tag_values(['Type_prefix', $prefix]);
    }
    if ($self->known) {
        $txt->add_tag_values(['Known']);
    }
    foreach my $alias ($self->list_aliases) {
        $txt->add_tag_values(['Alias', $alias]);
    }
    if (my $desc = $self->description) {
        $txt->add_tag_values(['Full_name', $desc]);
    }
    foreach my $remark ($self->list_remarks) {
        $txt->add_tag_values(['Remark', $remark]);
    }
    foreach my $remark ($self->list_annotation_remarks) {
        $txt->add_tag_values(['Annotation_remark', $remark]);
    }

    $ace .= $txt->ace_string . "\n";

    return $ace;
}

#sub DESTROY {
#    my( $self ) = @_;
#    
#    print STDERR "Locus ", $self->name, " is released\n";
#}


1;

__END__

=head1 NAME - Hum::Ace::Locus

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

