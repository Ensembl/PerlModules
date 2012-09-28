
### Hum::TPF

package Hum::TPF;

use strict;
use warnings;
use Carp;
use Hum::TPF::Parser;
use Hum::TPF::Row::Clone;
use Hum::TPF::Row::Gap;
use Hum::Tracking qw{
    prepare_cached_track_statement
    prepare_track_statement
    iso2time
    };
use Hum::Species;


sub new {
    my( $pkg ) = @_;

    return bless {
        '_rows' => [],
        }, $pkg;
}

sub species {
  # SANGER oracle db not always uses binomial system
    my( $self, $species ) = @_;

    if ($species) {
        $self->{'_species'} = ucfirst lc $species;
    }
    return $self->{'_species'};
}

sub organism {
  # use for NCBI TPF submission: binomial system
  my( $self ) = @_;
  $self->{'ncbi_species'} = Hum::Species->fetch_Species_by_name($self->species)->binomial;
  return $self->{'ncbi_species'};
}
sub assembly {
  # use for NCBI TPF submission
  my( $self, $assembly ) = @_;

  if ($assembly) {
    $self->{'_assembly'} = $assembly;
  }
  else {
    $self->{'_assembly'} = $self->subregion ? $self->subregion : 'Reference';
  }
  return $self->{'_assembly'};
}

sub type {
  # use for NCBI TPF submission
  my( $self, $type ) = @_;

  if ($type) {
    $self->{'_type'} = $type;
  }
  else {
    $self->{'_type'} = $self->subregion ? 'Contig' : 'Complete Chromosome';
  }
  return $self->{'_type'};
}
sub version {
  # use for NCBI TPF submission
  my( $self, $version ) = @_;

  if ($version) {
    $self->{'_version'} = $version;
  }
  return $self->{'_version'};
}

sub comment {
  # use for NCBI TPF submission
  my( $self, $comment ) = @_;

  if ($comment) {
    $self->{'_comment'} = $comment;
  }
  return $self->{'_comment'};
}

sub strain {
  # use for NCBI TPF submission
  my( $self, $strain ) = @_;

  if ($strain) {
    $self->{'_strain'} = $strain;
  }
  return $self->{'_strain'};
}

sub submitter {
  # use for NCBI TPF submission
  my( $self, $submitter ) = @_;

  if ($submitter) {
    $self->{'_submitter'} = $submitter;
  }
  return $self->{'_submitter'};
}

sub chromosome {
    my( $self, $chromosome ) = @_;

    if ($chromosome) {
        $self->{'_chromosome'} = uc $chromosome;
    }
    return $self->{'_chromosome'};
}

sub subregion {
    my( $self, $subregion ) = @_;

    if ($subregion) {
        $self->{'_subregion'} = $subregion;
    }
    return $self->{'_subregion'};
}

sub entry_date {
    my( $self, $entry_date ) = @_;

    if (defined $entry_date) {
        $self->{'_entry_date'} = $entry_date;
    }
    return $self->{'_entry_date'};
}

sub program {
    my( $self, $program ) = @_;

    if ($program) {
        $self->{'_program'} = $program;
    }
    return $self->{'_program'} || $0 =~ m{([^/]+)$};
}

sub operator {
    my( $self, $operator ) = @_;

    if ($operator) {
        $self->{'_operator'} = $operator;
    }
    return $self->{'_operator'} || (getpwuid($<))[0];
}

sub iscurrent {
    my( $self, $iscurrent ) = @_;

    if ($iscurrent) {
        $self->{'_iscurrent'} = $iscurrent;
    }
    return $self->{'_iscurrent'};
}

sub new_from_db_id {
    my( $pkg, $db_id ) = @_;

    confess "missing db_id argument" unless $db_id;

    return $pkg->_fetch_generic(q{ AND t.id_tpf = ? }, $db_id);
}

sub dated_from_species_chromsome {
    my( $pkg, $max_date, $species, $chromsome ) = @_;

    return $pkg->_fetch_generic(q{
          AND t.entry_date < TO_DATE(?, 'YYYY-MM-DD')
          AND c.speciesname = ?
          AND c.chromosome = ?
          AND g.subregion IS NULL
          ORDER BY t.entry_date DESC
        },
        $max_date, $species, $chromsome);
}

sub dated_from_species_chromsome_subregion {
    my( $pkg, $max_date, $species, $chromsome, $subregion ) = @_;

    return $pkg->_fetch_generic(q{
          AND t.entry_date < TO_DATE(?, 'YYYY-MM-DD')
          AND c.speciesname = ?
          AND c.chromosome = ?
          AND g.subregion = ?
          ORDER BY t.entry_date DESC
        },
        $max_date, $species, $chromsome, $subregion);
}

sub current_from_species_chromsome {
    my( $pkg, $species, $chromsome ) = @_;

    return $pkg->_fetch_generic(q{
          AND t.iscurrent = 1
          AND c.speciesname = ?
          AND c.chromosome = ?
          AND g.subregion IS NULL
        },
        $species, $chromsome);
}

sub current_from_species_chromsome_subregion {
    my( $pkg, $species, $chromsome, $subregion ) = @_;

    return $pkg->_fetch_generic(q{
          AND t.iscurrent = 1
          AND c.speciesname = ?
          AND c.chromosome = ?
          AND g.subregion = ?
        },
        $species, $chromsome, $subregion);
}

sub _fetch_generic {
    my( $pkg, $where_clause, @data ) = @_;

    my $sql = qq{
        SELECT t.id_tpf
          , t.id_tpftarget
          , TO_CHAR(t.entry_date, 'YYYY-MM-DD HH24:MI:SS') entry_date
          , t.program
          , t.operator
          , g.subregion
          , c.speciesname
          , c.chromosome
          , t.iscurrent
        FROM tpf t
          , tpf_target g
          , chromosomedict c
        WHERE t.id_tpftarget = g.id_tpftarget
          AND g.chromosome = c.id_dict
          $where_clause
        };
    #warn "$sql (@data)";
    my $sth = prepare_cached_track_statement($sql);
    $sth->execute(@data);
    my ($db_id, $id_tpftarget, $entry_date, $prog, $operator,
        $subregion, $species, $chr, $iscurrent) = $sth->fetchrow;
    $sth->finish;

    confess "No tpf found" unless $db_id;

    my $self = $pkg->new;
    $self->db_id($db_id);
    $self->id_tpftarget($id_tpftarget);
    $self->entry_date(iso2time($entry_date));
    $self->program($prog);
    $self->operator($operator);
    $self->subregion($subregion);
    $self->species($species);
    $self->chromosome($chr);
    $self->iscurrent($iscurrent);

    # Get all the row data
    $self->_express_fetch_TPF_Rows;

    return $self;
}

sub _express_fetch_TPF_Rows {
    my( $self ) = @_;

    my $db_id = $self->db_id;

    my $rank_gap   = $self->_express_fetch_TPF_Gaps_rank_hash;
    my $rank_clone = $self->_express_fetch_TPF_Clones_hash;

    my $sql = q{
        SELECT r.rank
		  , r.remark
          , s.accession
          , s.id_sequence
        FROM tpf_row r
          , clone_sequence cs
          , sequence s
        WHERE r.clonename = cs.clonename
          AND cs.id_sequence = s.id_sequence
          AND cs.is_current = 1
          AND r.id_tpf = ?
        ORDER BY r.rank ASC
        };
    #warn $sql;
    my $sth = prepare_cached_track_statement($sql);
    $sth->execute($db_id);
    my( $clone_rank, $remark, $acc, $current_seq_id );
    $sth->bind_columns(\$clone_rank, \$remark, \$acc, \$current_seq_id);

	# Keep track of clones by name so you can add contained clones to their container
	my %clone_for_accession;
	my %contained_by_container_accession;

    my $rank = 1;
    while ($sth->fetch) {

        # Add any non-sequence entries before this position
        until ($clone_rank == $rank) {
            my $row = $rank_clone->{$rank} || $rank_gap->{$rank};
            confess "Can't get row for rank '$rank'" unless $row;
            $self->add_Row($row);
            $rank++;
        }

        my $clone = $rank_clone->{$rank}
            or confess "Missing Clone for rank '$rank'";
        $clone->accession($acc);
        $clone->current_seq_id($current_seq_id);

        # If the clonename is same as the accession,
        # set the international clone name to the accession
        if ($clone->sanger_clone_name eq $acc) {
            $clone->intl_clone_name('?');
        }

		# If the clone is contained, store a note of this
		# so we can put the clones together once all clones have been loaded
		if(defined($remark) and $remark =~ /CONTAINED\s+(\S+)/) {
			my $container_accession = $1;
			push(@{$contained_by_container_accession{$container_accession}}, $clone);
		}

        $self->add_Row($clone);
		$clone_for_accession{$acc} = $clone;
        $rank++;
    }

    # Add any non-sequence entries onto the end
    while (my $gap = $rank_clone->{$rank} || $rank_gap->{$rank}) {
        $self->add_Row($gap);
        $rank++;
    }

	# Add contained clones to their containers
	# and containers to the contained clones
	# This happens at the end to allow for the possibility of contained clones
	# that are in the TPF before their containers
	foreach my $container_accession (keys %contained_by_container_accession) {
		foreach my $clone (@{$contained_by_container_accession{$container_accession}}) {
			if(exists($clone_for_accession{$container_accession})) {
				$clone->container_clone($clone_for_accession{$container_accession});
				$clone_for_accession{$container_accession}->add_contained_clone($clone);
			}
			else {
				carp("Cannot identify container clone $container_accession for contained clone " . $clone->accession . "\n");
			}
		}
	}

    return $self;
}

sub _express_fetch_TPF_Clones_hash {
    my( $self ) = @_;

    my $sql = q{
        SELECT r.id_tpfrow
          , r.rank
          , r.clonename
          , r.contigname
          , r.remark
          , l.internal_prefix
          , l.external_prefix
          , c.remark
        FROM tpf_row r
          , clone c
          , library l
        WHERE r.clonename = c.clonename
          AND c.libraryname = l.libraryname (+)
          AND r.id_tpf = ?
        };
    #warn $sql;
    my $sth = prepare_cached_track_statement($sql);
    $sth->execute($self->db_id);
    my( $clone_id, $clone_rank, $clonename, $contigname,
        $remark, $int_pre, $ext_pre, $clone_remark );
    $sth->bind_columns(\$clone_id, \$clone_rank, \$clonename, \$contigname,
        \$remark, \$int_pre, \$ext_pre, \$clone_remark );

    my $rank_clone = {};
    while ($sth->fetch) {
        my $clone = Hum::TPF::Row::Clone->new;
        $clone->db_id($clone_id);
        $clone->contig_name($contigname);
        $clone->sanger_clone_name($clonename);
        $clone->remark($remark);

        if ($clone_remark and $clone_remark =~ /MULTIPLE/) {
            $clone->is_multi_clone(1);
        }
        elsif (! $clone_remark or $clone_remark !~ /UNKNOWN/) {
            $clone->set_intl_clone_name_from_sanger_int_ext($clonename, $int_pre, $ext_pre);
        }

        $rank_clone->{$clone_rank} = $clone;
    }
    return $rank_clone;
}

sub _express_fetch_TPF_Gaps_rank_hash {
    my( $self ) = @_;

    my $sql = q{
        SELECT r.id_tpfrow
          , r.rank
          , r.remark
          , g.length
          , g.id_gaptype
        FROM tpf_row r
          , tpf_gap g
        WHERE r.id_tpfrow = g.id_tpfrow
          AND r.id_tpf = ?
        };
    my $sth = prepare_cached_track_statement($sql);
    $sth->execute($self->db_id);
    my( $gap_id, $gap_rank, $remark, $gap_length, $gap_type );
    $sth->bind_columns(\$gap_id, \$gap_rank, \$remark, \$gap_length, \$gap_type);

    my $rank_gap = {};
    while ($sth->fetch) {
        $gap_length = undef if defined($gap_length) and $gap_length eq '?';
        my $gap = Hum::TPF::Row::Gap->new;
        $gap->db_id($gap_id);
        $gap->gap_length($gap_length);
        $gap->type($gap_type);
        $gap->remark($remark);
        $rank_gap->{$gap_rank} = $gap;
    }
    return $rank_gap;
}

sub db_id {
    my( $self, $db_id ) = @_;

    if ($db_id) {
        $self->{'_db_id'} = $db_id;
    }
    return $self->{'_db_id'};
}

sub id_tpftarget {
    my( $self, $id ) = @_;

    if ($id) {
        $self->{'_id_tpftarget'} = $id;
    }
    return $self->{'_id_tpftarget'};
}

sub add_Row {
    my( $self, $row ) = @_;

    push @{$self->{'_rows'}}, $row;
}

sub fetch_all_Rows {
    my( $self ) = @_;

    return @{$self->{'_rows'}};
}

sub fetch_non_contained_Rows {
    my( $self ) = @_;

	my @non_contained_rows;
	foreach my $row (@{$self->{'_rows'}}) {
		if($row->is_gap or not defined($row->container_clone)) {
			push(@non_contained_rows, $row);
		}
	}
	
	return @non_contained_rows;
}


sub string {
    my( $self ) = @_;

    # Make the header
    my $str = "##";
    foreach my $method (qw{ species chromosome subregion }) {
        if (my $data = $self->$method()) {
            $str .= "  $method=$data";
        }
    }
    $str .= "\n";

    # Add the rows
    foreach my $row ($self->fetch_all_Rows) {
        $str .= $row->string;
    }
    return $str;
}

sub ncbi_string {
  my( $self ) = @_;

  # Make the NCBI header
  # currently REQUIRED: ORGANISM, ASSEMBLY, CHROMOSOME, TYPE
  #           OPTIONAL: STRAIN/HAPLOTYPE/CULTIVAR, Version,
  #                     Comment, SUBMITTER, "CREATE DATE", "UPDATE DATE"
  my $str;
  foreach my $method (qw{ organism chromosome assembly subregion type version comment submitter}) {
    my $header = $method;
    if ( $method eq "subregion" ){ $header = "Strain/Haplotype/Cultivar" }
    elsif ( $method eq "assembly" ){ $header = "Assembly Name" }

    if (my $data = $self->$method()) {
      $str .= "##" . ucfirst($header) . ": $data\n";
    }
    else {
      if ( $self->strain and $method eq "subregion" ){
        $str .= "##" . ucfirst($header) . ": " . $self->strain() . "\n";
      }
      else {
        $str .= "##" .ucfirst($header) . ":\n";
      }
    }
  }
  $str .= "##Create date:\n";
  $str .= "##Update date:\n";
  $str .= "\n##=== Beginning of TPF Data ===\n\n";

  # Add the rows
  foreach my $row ($self->fetch_all_Rows) {
    # wait until database is updated
    # type-4 is still used for undetermined GAP types (Darren G)

    if ( $row->isa("Hum::TPF::Row::Gap") ){

      # make sure to flag ncbi for changes in Hum::TPF::Row::Gap:string();
      $row->ncbi(1);

      if ( $row->type == 4 ){
        if ( ! $row->remark ){
          warn "NO REMARK for type-4\n"; # remark has the control vocabulary for NCBI
          $row->type(3);                 # default to type-3 but check by hand
                                         # to determine if type2 via flanking contigs
        }
      }
    }
    else{
      # new foramt:
      # Human: Hschr4_ctg3
      # Mouse: Mmchr4_ctg*
      my $prefix;

      my $ctgname = $row->contig_name;
      # eg  MmchrXctg1, Mmchr11_ctg3
      # make sure contig name has right format
      if ( $self->species  eq 'Mouse' ){
        if ($ctgname =~ /^Mus_(\d+|\w*)(ctg.*)/i or
            $ctgname =~ /Mmchr(\d+|\w*)_?(ctg.*)/i or
            $ctgname =~ /chr(\d+|\w*)_?(.*)/i
           ) {
          $prefix = 'Mmchr';
          $row->contig_name($prefix.$1."_".lc($2));
          #warn %$row;
        }
        else {
           warn "BAD contigname: ", $row->accession, "\n";
           warn %$row;
        }
      }
      else{
        #eg Chr_Xctg3 or X_JENA_3
        if ($ctgname =~ /^chr_(\d+|\w*)(ctg.*)/i or $ctgname =~ /(X)_(.*)/i ) {
          $prefix = 'Hschr';
          my $new_ctgname = $prefix.$1."_".$2;
          $new_ctgname =~ s/CTG/ctg/;

          $row->contig_name($new_ctgname);
          #warn "$ctgname vs $new_ctgname";
        }
        elsif ( $ctgname !~ /^Hschr\d+_ctg\d+/ ) {
          warn "BAD contigname, $ctgname: ", $row->accession, "\n";
        }
      }

      # also want remark column
      warn "REMARK: ", $row->{'_remark'} if $row->{'_remark'};
    }

    $str .= $row->string;
  }

  $str .= "\n##=== End of TPF Data ===\n";

  return $str;
}

sub store {
    my( $self ) = @_;

    confess("Already stored with id_tpf=", $self->db_id)
        if $self->db_id;

    my ($chr_id, $id_tpftarget) = $self->get_store_chr_tpftarget_ids;
    $self->get_next_id_tpf;

    # Set any existing to not_current
    my $not_current = prepare_cached_track_statement(q{
        UPDATE tpf
        SET iscurrent = 0
        WHERE id_tpftarget = ?
        });
    $not_current->execute($id_tpftarget);

    # Store self into TPF table
    my $sth = prepare_cached_track_statement(q{
        INSERT INTO tpf(id_tpf
              , id_tpftarget
              , entry_date
              , iscurrent
              , program
              , operator)
        VALUES(?,?,sysdate,1,?,?)
        });
    $sth->execute($self->db_id,
        $id_tpftarget,
        $self->program,
        $self->operator,
        );

    # Store all rows
    my $rank = 0;
    foreach my $row ($self->fetch_all_Rows) {
        $row->store($self, ++$rank);
    }
}

sub get_store_chr_tpftarget_ids {
    my( $self ) = @_;

    my $species = $self->species
        or confess "species not set";
    my $chr = $self->chromosome
        or confess "chromosome not set";
    my $subregion = $self->subregion;
    my( $chr_id, $id_tpftarget );
    if ($subregion) {
        my $sth = prepare_track_statement(q{
            SELECT c.id_dict
              , g.id_tpftarget
            FROM chromosomedict c
              , subregion s
              , tpf_target g
            WHERE c.id_dict = s.chromosome
              AND s.chromosome = g.chromosome
              AND s.subregion = g.subregion
              AND c.speciesname = ?
              AND c.chromosome = ?
              AND s.subregion = ?
            });
        $sth->execute($species, $chr, $subregion);
        ($chr_id, $id_tpftarget) = $sth->fetchrow;

        # Can't use the left join trick we do below
        # Have to do an extra select
        unless ($chr_id) {
            my $sth = prepare_track_statement(q{
                SELECT c.id_dict
                FROM chromosomedict c
                  , subregion s
                WHERE c.id_dict = s.chromosome
                  AND c.speciesname = ?
                  AND c.chromosome = ?
                  AND s.subregion = ?
                });
            $sth->execute($species, $chr, $subregion);
            ($chr_id) = $sth->fetchrow;
        }
    } else {
        my $sth = prepare_track_statement(q{
            SELECT c.id_dict
              , g.id_tpftarget
            FROM chromosomedict c
              , tpf_target g
            WHERE c.id_dict = g.chromosome (+)
              AND c.speciesname = ?
              AND c.chromosome = ?
              AND g.subregion IS NULL
            });
        $sth->execute($species, $chr);
        ($chr_id, $id_tpftarget) = $sth->fetchrow;
    }

    unless ($chr_id) {
        my $err = "No id_dict for species '$species' and chromosome '$chr'";
        if ($subregion) {
            $err .= " and subregion '$subregion'";
        }
        confess $err;
    }
    unless ($id_tpftarget) {
        $id_tpftarget = $self->get_next_id_tpftarget;
        my $sth = prepare_track_statement(q{
            INSERT INTO tpf_target(id_tpftarget
                  , chromosome
                  , subregion)
            VALUES (?,?,?)
            });
        $sth->execute($id_tpftarget, $chr_id, $subregion);
    }

    return( $chr_id, $id_tpftarget );
}

sub get_next_id_tpftarget {
    my( $self ) = @_;

    my $sth = prepare_track_statement(q{SELECT tpft_seq.nextval FROM dual});
    $sth->execute;
    my ($id) = $sth->fetchrow;
    return $id;
}

sub get_next_id_tpf {
    my( $self ) = @_;

    my $sth = prepare_track_statement(q{SELECT tpf_seq.nextval FROM dual});
    $sth->execute;
    my ($id) = $sth->fetchrow;
    $self->db_id($id);
}

1;

__END__

=head1 NAME - Hum::TPF

=head1 SEE ALSO

http://www.ncbi.nlm.nih.gov/projects/genome/assembly/grc/info/index.shtml
for the TPF specification and diagrams of various types of overlap.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

