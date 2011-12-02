
### Hum::ProjectDump::EMBL::Pool

package Hum::ProjectDump::EMBL::Pool;

use strict;
use warnings;
use Carp;
use YAML;

# use Hum::ProjectDump::EMBL::Unfinished;   ### Why was this here?
use base qw{ Hum::ProjectDump::EMBL };

use Hum::Submission qw{
    prepare_statement
    acc_data
};
use Hum::Tracking qw{
    prepare_track_statement
    library_and_vector_from_parent_project
};
use Hum::EmblUtils qw{
    add_source_FT
    add_Organism
};


my $number_Ns = 100;

sub process_repository_data {
    my ($pdmp) = @_;

    my $db_name = uc $pdmp->project_name;
    my $db_dir  = $pdmp->online_path || confess "No online path";
    my $db_file = $db_dir . "/FILECTGS.yaml";

    confess "YAML file $db_file doesn't exist" unless (-e $db_file);

    $pdmp->dump_time(time);    # Record the time of the dump

    my ($yaml_array) = YAML::LoadFile($db_file);

    $pdmp->{_yaml} = $yaml_array;
    $pdmp->_process_yaml;
}

{
    my $padding_Ns = 'n' x $number_Ns;

    sub _process_yaml {
        my ($pdmp) = @_;
        my ($clone_cnt, $supcontig_cnt, $contig_cnt);
        my ($clone_names);

        # Make the sequence
        my $dna          = "";
        my $unpadded_dna = "";
        my $pos          = 0;

        my @assembly_map;    # [class, name, start pos, end pos, type]
                             # type is used for sorting the array (1=Clone,2=SuperContig,3=Contig)

        my $parse_supercontig = sub {
            my ($hash) = @_;
            $supcontig_cnt++;
            foreach my $h3 (@{ $hash->{'assembly'} }) {
                if ($h3->{'Contig'}) {
                    $contig_cnt++;
                    my $ctg_start  = $pos + 1;
                    my $contig_dna = $h3->{'dna'};
                    $contig_dna =~ s/\n//g;
                    $dna          .= lc($contig_dna);
                    $unpadded_dna .= lc($contig_dna);
                    $pos += length($contig_dna);
                    push @assembly_map, [ 'Contig', $h3->{'Contig'}, $ctg_start, $pos, 3 ];
                }
                else {    # then its a Gap
                    $dna .= ('n' x $h3->{'Gap'});
                    $pos += $h3->{'Gap'};
                }
            }
        };

        foreach my $h1 (@{ $pdmp->{_yaml} }) {

            # Clone , pieces, SuperContig, assembly
            if ($dna) {
                $dna .= $padding_Ns;
                $pos += $number_Ns;
            }
            my ($class, $name);
            my $start = $pos + 1;
            foreach my $k1 (keys %$h1) {
                if ($k1 eq 'Clone') {
                    ($class, $name) = ($k1, $h1->{$k1});
                    my $padding = 0;
                    $clone_cnt++;
                    push @$clone_names, $h1->{$k1};
                    foreach my $h2 (@{ $h1->{'pieces'} }) {
                        if ($dna && $padding) {    # don't add padding before 1st supcontig
                            $dna .= $padding_Ns;
                            $pos += $number_Ns;
                        }
                        my $spctg_start = $pos + 1;
                        $parse_supercontig->($h2);
                        push @assembly_map, [ 'SuperContig', $h2->{'SuperContig'}, $spctg_start, $pos, 2 ];
                        $padding = 1;
                    }

                }
                elsif ($k1 eq 'SuperContig') {
                    ($class, $name) = ($k1, $h1->{$k1});
                    $parse_supercontig->($h1);
                }
            }
            push @assembly_map, [ $class, $name, $start, $pos, ($class eq 'SuperContig') ? 2 : 1 ];
        }
        $pdmp->clone_count($clone_cnt);
        $pdmp->supercontig_count($supcontig_cnt);
        $pdmp->contig_count($contig_cnt);
        $pdmp->clone_names($clone_names);
        $pdmp->assembly_map(\@assembly_map);
        $pdmp->dna($dna);
        $pdmp->unpadded_dna($unpadded_dna);
    }
}

sub assembly_map {
    my ($pdmp, $map) = @_;

    if ($map) {
        $pdmp->{_asssembly_map} = $map;
    }

    return $pdmp->{_asssembly_map};
}

sub dna {
    my ($pdmp, $dna) = @_;

    if ($dna) {
        $pdmp->{_dna} = $dna;
    }

    return $pdmp->{_dna};
}

sub unpadded_dna {
    my ($pdmp, $dna) = @_;

    if ($dna) {
        $pdmp->{_unpadded_dna} = $dna;
    }

    return $pdmp->{_unpadded_dna};
}

sub unpadded_length {
    my ($pdmp) = @_;

    return length($pdmp->unpadded_dna);
}

sub clone_names {
    my ($pdmp, $array) = @_;

    if ($array) {
        $pdmp->{_clone_names} = $array;
    }

    return $pdmp->{_clone_names};
}

sub clone_count {
    my ($pdmp, $count) = @_;
    if ($count) {
        $pdmp->{clone_count} = $count;
    }

    return $pdmp->{clone_count};
}

sub supercontig_count {
    my ($pdmp, $count) = @_;
    if ($count) {
        $pdmp->{sc_count} = $count;
    }

    return $pdmp->{sc_count};
}

sub contig_count {
    my ($pdmp, $count) = @_;
    if ($count) {
        $pdmp->{contig_count} = $count;
    }

    return $pdmp->{contig_count};
}

sub get_length {
    my ($pdmp, $class, $name) = @_;

    my ($e) = grep { $_->[0] eq $class and $_->[1] eq $name } @{ $pdmp->assembly_map };

    return $e ? $e->[3] - $e->[2] + 1 : undef;
}

### Too much code in make_embl() duplicated from Hum::ProjectDump::EMBL
sub make_embl {
    my ($pdmp) = @_;

    my $project = $pdmp->project_name;
    my $acc     = $pdmp->accession || '';    # null
    my @sec     = $pdmp->secondary;          # null
    my $species = $pdmp->species;

    # Believe it or not a pooled project can be multi-species
    # But this is not handled at the moment !!!
    confess "Pooled project $project contains more than 1 species ($species)"
      if $species =~ /,/;

    my $chr       = $pdmp->chromosome;
    my $binomial  = $pdmp->species_binomial;
    my $dataclass = $pdmp->EMBL_dataclass;
    my $division  = $pdmp->EMBL_division;

    # Get the DNA and map of clone/supercontig/contig positions.
    my $assembly_map = $pdmp->assembly_map;
    my $dna          = $pdmp->dna;
    my $seqlength    = length($dna);

    # New embl file object
    my $embl = Hum::EMBL->new();

    # ID line
    my $id = $embl->newID;
    $id->accession($acc);
    $id->molecule('genomic DNA');
    $id->dataclass($dataclass);
    $id->division($division);
    $id->seqlength($seqlength);
    $embl->newXX;

    # AC line
    my $ac = $embl->newAC;
    $ac->primary($acc);
    $ac->secondaries(@sec);
    $embl->newXX;

    # AC * line
    my $ac_star = $embl->newAC_star;
    $ac_star->identifier($pdmp->sanger_id);
    $embl->newXX;

    # ST * line (was HD * line)
    if ($pdmp->is_private(1)) {

        # Hold date of half a year from now
        my $hold_date = time + (0.5 * 365 * 24 * 60 * 60);
        my $hd = $embl->newST_star;
        $hd->hold_date($hold_date);
        $embl->newXX;
    }

    # DE line
    $pdmp->add_Description($embl);

    # KW line
    $pdmp->add_Keywords($embl);

    # Organism
    add_Organism($embl, $species);
    $embl->newXX;

    # Reference
    $pdmp->add_Reference($embl, $seqlength);

    # CC lines
    $pdmp->add_Headers($embl);
    $embl->newXX;

    # Feature table header
    $embl->newFH;

    # Feature table source and assembly feature
    my $libraryname = library_and_vector_from_parent_project($project);
    $pdmp->add_FT($embl, $seqlength, $binomial, $chr, $libraryname);
    $embl->newXX;

    # Sequence
    $embl->newSequence->seq($dna);

    $embl->newEnd;

    return $embl;
}

sub author {
    my ($pdmp) = @_;

    unless ($pdmp->{'_author'}) {
        $pdmp->{'_author'} = "Auger K.";
    }
    return $pdmp->{'_author'};
}

sub sequence_name {
    my ($pdmp) = @_;

    return $pdmp->project_name;
}

sub add_FT {
    my ($pdmp, $embl, $length, $binomial, $chr, $libraryname) = @_;

    my @fts;

    my $ft = $embl->newFT;
    $ft->key('source');

    my $loc = $ft->newLocation;
    $loc->exons([ 1, $length ]);
    $loc->strand('W');

    $ft->addQualifierStrings('mol_type', 'genomic DNA');
    if ($binomial) {
        $ft->addQualifierStrings('organism', $binomial);
        if ($binomial eq 'Solanum lycopersicum') {
            $ft->addQualifierStrings('cultivar', 'Heinz 1706');
        }
    }
    my $clone_list = join(';', sort @{ $pdmp->clone_names });
    $ft->addQualifierStrings('clone', $clone_list) if $clone_list;

    push @fts, $ft;
    my ($sstart, $send) = (0, 0);

    foreach
      my $element (sort { $a->[2] <=> $b->[2] || $b->[3] <=> $a->[3] || $a->[4] <=> $b->[4] } @{ $pdmp->assembly_map })
    {

        my $ft;
        my ($class, $name, $start, $end, $group) = @{$element};

        if ($class eq 'Clone') {
            $ft = $embl->newFT;
            $ft->key('source');

            my $loc = $ft->newLocation;
            $loc->exons([ $start, $end ]);
            $loc->strand('W');
            $ft->addQualifierStrings('mol_type', 'genomic DNA');
            if ($binomial) {
                $ft->addQualifierStrings('organism', $binomial);
                if ($binomial eq 'Solanum lycopersicum') {
                    $ft->addQualifierStrings('cultivar', 'Heinz 1706');
                }
            }
            $ft->addQualifierStrings('clone', $name);
            my $library_name = $libraryname->{$name}->[0] if $libraryname->{$name};
            $ft->addQualifierStrings('clone_lib', $library_name) if $library_name;
            my $clone_chr = $chr->{$name};
            unless (!$clone_chr or $clone_chr =~ /u/i) {
                $ft->addQualifierStrings('chromosome', $clone_chr);
            }
        }
        else {
            if (   $start eq $sstart
                && $end   eq $send
                && $class eq 'Contig')
            {

                # this will avoid duplicates of misc-features
                $fts[-1]->addQualifierStrings('note', lc($class) . ":$name");
            }
            else {
                $ft = $embl->newFT;
                $ft->key('misc_feature');
                my $loc = $ft->newLocation;
                $loc->exons([ $start, $end ]);
                $loc->strand('W');
                $ft->addQualifierStrings('note', lc($class) . ":$name");
            }
        }

        ($sstart, $send) = ($start, $end);

        push @fts, $ft if $ft;
    }

    return \@fts;
}

sub add_Description {
    my ($pdmp, $embl) = @_;

    my $species = $pdmp->species;

    #my $clone_list = join(', ',sort @{$pdmp->clone_names});
    my $clones_nb = scalar @{ $pdmp->clone_names };
    my $de        = $embl->newDE;
    $de->list("$species DNA sequence HIGH QUALITY DRAFT from $clones_nb pooled clone" . ($clones_nb > 1 ? "s" : ""));
    $embl->newXX;
}

sub add_Headers {
    my ($pdmp, $embl) = @_;

    $pdmp->add_external_draft_CC($embl);

    my $project = $pdmp->project_name;

    my @comment_lines = (
        $pdmp->seq_center_lines,
        '-------------- Project Information',
        "Center project name: $project",
        '--------------',
        "* NOTE: This is a 'high quality draft' sequence. It currently "
          . "consists of "
          . $pdmp->supercontig_count
          . " supercontigs. Sequence "
          . "has been generated by pooling "
          . "genomic clones for sequencing on an Illumina Genome Analyzer instrument. "
          . "An assembly is then combined with capillary whole genome shotgun data. "
          . "Some order and orientation information can tentatively be deduced "
          . "from paired sequencing reads which have been identified to span the gap "
          . "between two contigs within the same supercontig. Gaps between the contigs "
          . "are based on paired end information from the capillary reads. "
          . "Supercontigs are associated with a clone name where there are "
          . "clone end sequence matches."
    );

    $embl->newCC->list(@comment_lines);

    $pdmp->add_extra_headers($embl, 'comment');
}

sub is_private {
    my ($pdmp) = @_;

    return Hum::Tracking::is_private($pdmp->project_name, 1);
}

sub species {
    my ($pdmp) = @_;

    unless (exists $pdmp->{'_species'}) {
        $pdmp->{'_species'} = Hum::Tracking::species_from_parent_project($pdmp->project_name);
    }
    return $pdmp->{'_species'};
}

sub chromosome {
    my ($pdmp) = @_;

    unless ($pdmp->{'_chromosome'}) {
        $pdmp->{'_chromosome'} = Hum::Tracking::clone_to_chromosome_from_parent_project($pdmp->project_name);
    }

    return $pdmp->{'_chromosome'};
}

sub create_new_dump_object {
    my ($pkg, $project) = @_;

    my $pdmp = $pkg->new;
    $pdmp->project_name($project);
    $pdmp->sanger_id("_\U$project");

    return $pdmp;
}

sub read_accession_data {
    my ($pdmp) = @_;

    my ($accession, $embl_name, @secondaries) = acc_data($pdmp->sanger_id);
    $pdmp->accession($accession);
    $pdmp->embl_name($embl_name);

    my $project_name = $pdmp->project_name
      or confess "project_name not set";

    if (my ($ext_sec, $institute) = Hum::Tracking::external_draft_info($pdmp->project_name, 1)) {
        $pdmp->draft_institute($institute);
        my $seen = 0;
        foreach my $sec (@secondaries) {
            $seen = 1 if $sec eq $ext_sec;
        }
        push(@secondaries, $ext_sec) unless $seen;
    }
    $pdmp->secondary(@secondaries) if @secondaries;
}

sub get_seqby_and_fundby {
    my ($pdmp) = @_;

    my $proj = $pdmp->project_name
      or confess "project_name not set";
    my $sth = prepare_track_statement(
        q{
    SELECT DISTINCT c.funded_by,
                    c.sequenced_by
    FROM   clone_project cp,
                project p,
                clone c
    WHERE   cp.clonename = c.clonename
    AND     cp.projectname = p.projectname
    AND     p.parent_project =  ?
            }
    );
    $sth->execute($proj);
    my ($fund_by, $seq_by) = $sth->fetchrow;
    $sth->finish;

    $pdmp->funded_by($fund_by);
    $pdmp->sequenced_by($seq_by);
}

sub write_fasta_file {
    my ($pdmp) = @_;

    my $seq_name = $pdmp->sequence_name;
    my $accno    = $pdmp->accession || '';
    my $file     = $pdmp->fasta_file_path;
    my $phase    = $pdmp->htgs_phase;

    warn "Phase = $phase\n";

    local *FASTA;
    open FASTA, "> $file" or confess "Can't write to '$file' : $!";

    my $dna    = $pdmp->dna;
    my $header = $seq_name;

    print FASTA ">$header\n" or confess "Can't print to '$file' : $!";
    while ($dna =~ m/(.{1,60})/g) {
        print FASTA $1, "\n" or confess "Can't print to '$file' : $!";
    }

    close FASTA or confess "Error creating fasta file ($?) $!";
}

1;

__END__

=head1 NAME - Hum::ProjectDump::EMBL::Pool

=head1 AUTHOR

Mustapha Larbaoui B<email> ml6@sanger.ac.uk

