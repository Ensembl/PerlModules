
package Hum::ProjectDump;

use strict;
use Carp;
use Hum::Submission qw( sub_db
                        acc_data
                        );
use Hum::Tracking qw( track_db
                      ref_from_query
                      is_finished
                      project_finisher
                      project_team_leader
                      fishData
                      );
use humConf qw( FTP_ROOT FTP_GHOST );
use File::Path;

# Object methods

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}

# Generate simple data access functions using closures
BEGIN {
        
    # List of fields we want scalar access fuctions to
    my @scalar_fields = qw(
        accession
        author
        dump_time
        chromosome
        embl_name
        htgs_phase
        online_path
        project_name
        fish_map
        sanger_id
        seq_id
        sequence_name
        sequence_version
        species
    );
    
    # Make scalar field access functions
    foreach my $func (@scalar_fields) {
        no strict 'refs';
        
        # Don't overwrite existing functions
        die "'$func()' already defined" if defined (&$func);
        
        my $field = "_$func";
        *$func = sub {
            my( $pdmp, $arg ) = @_;
            
            if ($arg) {
                $pdmp->{$field} = $arg;
            }
            return $pdmp->{$field};
        }
    }
}

sub set_ftp_path {
    my( $pdmp ) = @_;
    return $pdmp->set_path($FTP_ROOT);
}
sub set_ghost_path {
    my( $pdmp ) = @_;
    return $pdmp->set_path($FTP_GHOST);
}

# Where to dump different projects
BEGIN {

    my %species_dirs = (
                        'Human'         => [ 'human/sequences', 'Chr_' ],
                        'Mouse'         => [ 'mouse',           'Chr_' ],
                        'Chicken'       => [ 'chicken'                 ],
                        'Fugu'          => [ 'fugu'                    ],
                        'Zebrafish'     => [ 'zebrafish'               ],
                        'Drosophila'    => [ 'drosophila'              ],
                        'Arabidopsis'   => [ 'arabidopsis'             ],
                        );
    sub set_path {
        my( $pdmp, $base_dir ) = @_;
        
        $base_dir ||= '.';
        my $species = $pdmp->species;
        my $chr     = $pdmp->chromosome;
        my $phase   = $pdmp->htgs_phase;
        my $p = $species_dirs{$species}
            or confess "Don't know about '$species'";

        my $path = "$base_dir/$p->[0]";
        $path .= "/$p->[1]$chr" if $p->[1];
        if ($phase == 0 or $phase == 1) {
            $path .= "/unfinished_sequence";
        }
        return $pdmp->file_path($path);
    }
}

sub file_path {
    my( $pdmp, $path ) = @_;
    
    if ($path) {
        $pdmp->{'_file_path'} = $path;
    }
    return $pdmp->{'_file_path'} || confess "file_path not set";
}

sub new_from_project_name {
    my( $pkg, $project ) = @_;
    
    my $pdmp = $pkg->new;
    $pdmp->project_name($project);
    $pdmp->read_tracking_details;
    $pdmp->sanger_id('_'. uc $project);
    $pdmp->read_accession_data;
    return $pdmp;
}


sub new_from_sanger_id {
    my( $pkg, $sanger_id ) = @_;
    
    my $sub_db = sub_db();
    my $get_dump = $sub_db->prepare(q{
        SELECT UNIX_TIMESTAMP(d.dump_time) dump_time
          , d.htgs_phase
          , s.sequence_name
          , s.sequence_version
          , s.embl_checksum
          , s.unpadded_length
          , s.contig_count
          , s.file_path
        FROM project_dump d
          , sequence s
        WHERE d.seq_id = s.seq_id
          AND d.is_current = 1
          AND d.sanger_id = ?
        });
    $get_dump->execute($sanger_id);
    if (my $ans = $get_dump->fetchrow_hashref) {
        my $pdmp = $pkg->new;
        map $pdmp->$_($ans->{$_}), keys %$ans; 
        return $pdmp;
    } else {
        return;
    }
}


BEGIN {
    foreach my $func (qw( DNA BaseQuality )) {
        my $field = "_$func";
        
        {
            no strict 'refs';
            *$func = sub {
                my( $pdmp, $contig, $data ) = @_;
                
                confess("Can't call $func() without contig name")
                    unless $contig;
                if ($data) {
                    confess "Not a reference: '$data'" unless ref($data);
                    $pdmp->{$field}{$contig} = $data;
                }
                return $pdmp->{$field}{$contig};
            }
        }
    }

    sub contig_list {
        my( $pdmp ) = @_;

        if ($pdmp->{'_DNA'}) {
            return sort keys %{$pdmp->{'_DNA'}};
        } else {
            confess "No contigs";
        }
    }

    sub contig_count {
        my( $pdmp, $count ) = @_;

        if ($pdmp->{'_DNA'}) {
            return scalar keys %{$pdmp->{'_DNA'}};
        } else {
            if (defined $count) {
                $pdmp->{'_contig_count'} = $count;
            }
            return $pdmp->{'_contig_count'};
        }
    }

    sub new_dna_ref {
        my( $pdmp, $contig ) = @_;

        confess "Can't call new_dna_ref() without contig name"
            unless $contig;
        my $dna = '';
        $pdmp->{'_DNA'}{$contig} = \$dna;
        return $pdmp->{'_DNA'}{$contig};
    }

    sub delete_contig {
        my( $pdmp, $contig ) = @_;

        confess "Can't call delete_contig() without contig name"
            unless $contig;
        delete( $pdmp->{'_DNA'}{$contig} )
            or confess "No such DNA '$contig'";
        delete( $pdmp->{'_BaseQuality'}{$contig} )
            or confess "No such BaseQuality '$contig'";;
    }
    
    sub contig_length {
        my( $pdmp, $contig ) = @_;
        
        confess "Contig name not specified" unless defined $contig;
        my $dna = $pdmp->{'_DNA'}{$contig}
            or confess "No such contig '$contig'";
        return length($$dna);
    }
    
    sub unpadded_length {
        my( $pdmp, $length ) = @_;
        
        if ($pdmp->{'_DNA'}) {            
            foreach my $contig ($pdmp->contig_list) {
                $length += $pdmp->contig_length($contig);
            }
            return $length;
        } else {
            if (defined $length) {
                $pdmp->{'_unpadded_length'} = $length;
            }
            return $pdmp->{'_unpadded_length'};
        }
    }
    
    sub cleanup_contigs {
        my( $pdmp, $cutoff ) = @_;
        
        $cutoff = 1000 unless defined $cutoff;
        
        foreach my $contig ($pdmp->contig_list) {
            my $dna = $pdmp->DNA($contig);
            my $qual = $pdmp->BaseQuality($contig);
            
            # Depad BaseQuality array
            my $pos = length($$dna);
            while (($pos = rindex($$dna, '-', $pos)) >= 0) {
	        splice(@$qual, $pos, 1);
	        $pos--;
            }
            # Depad DNA
            $$dna =~ s/\-//g;
            
            # Report traling n's
            {
                my $n = 0;
                for (my $i = (length($$dna) - 1);
                     substr($$dna, $i, 1) eq 'n';
                     $i--) {
                    print STDERR '.';
                    $n++;
                }
                if ($n) {
                    warn "\nIn project '", $pdmp->project_name,
                        "' contig '$contig' has $n trailing n's\n";
                }
            }
            # Trim trailing n's from the contig
            #if ($$dna =~ s/(n+)$//) {
            #    my $n_len = length($&);
            #    my $n_pre = length($`);
            #    splice(@$qual, $n_pre, $n_len);
            #    print "Stripped $n_len n's from contig $n\n";
            #}
            
            # Filter out contigs shorter than minimum contig length
	    if (length($$dna) < $cutoff) {
                $pdmp->delete_contig($contig);
            }
        }
        $pdmp->validate_contig_lengths;
    }
    
    sub validate_contig_lengths {
        my( $pdmp ) = @_;
        
        foreach my $contig ($pdmp->contig_list) {
            my $dna = $pdmp->DNA($contig);
            my $qual = $pdmp->BaseQuality($contig);
            confess "Differing DNA and BaseQuality lengths detected in contig '$contig'"
                unless length($$dna) == @$qual;
        }
    }
}

sub read_gap_contigs {
    my( $pdmp ) = @_;
    my $db_name  = uc $pdmp->project_name;
    my $db_dir   = $pdmp->online_path;
    
    local *GAP2CAF;
    local $/ = ""; # Paragraph mode for reading caf file

    my $contig_prefix = "Contig_prefix_ezelthrib";

    open(GAP2CAF, "cd $db_dir; gap2caf -project $db_name -version 0 -silent -cutoff 2 -bayesian -staden -contigs $contig_prefix 2> /dev/null |")
	|| die "COULDN'T OPEN PIPE FROM GAP2CAF : $!\n";
    
    while (<GAP2CAF>) {
	my ($object, $value) = split("\n", $_, 2);
	
	# Only read contig DNA and BaseQuality objects.
	# We know which ones the contigs are without looking for Is_contig
	# tags as gap2caf was told to put $contig_prefix in front of the
	# contig staden id.
	
	if ($object =~ /(DNA|BaseQuality)\s+\:\s+$contig_prefix(\d+)/) {
	    
	    my ($class, $name) = ($1, $2);
	    if ($class eq 'DNA') {
		$value =~ s/\s+//g;
                $value = lc $value;
		$pdmp->DNA($name, \$value);
	    } else {
		$pdmp->BaseQuality($name, [split(/\s+/, $value)]);
	    }
	    
	}
    }
    close(GAP2CAF) || confess $! ? "ERROR RUNNING GAP2CAF : exit status $?\n"
                                 : "ERROR RUNNING GAP2CAF : $!\n";
    $pdmp->dump_time(time); # Record the time of the dump
}

sub read_fasta_file {
    my( $pdmp ) = @_;
    
    my $dir = $pdmp->file_path or confess "file_path not set";
    my $seq_name = $pdmp->sequence_name;
    my $file = "$dir/$seq_name";
    
    local *FASTA;
    open FASTA, $file or confess "Can't read '$file' : $!";
    my( $dna );
    while (<FASTA>) {
        if (/^>/) {
            my ($contig) = /Contig_ID:\s+(\w+)/;
            unless ($contig) {
                $pdmp->htgs_phase == 3
                    or confess "Can't see 'Contig_ID:' in fasta header; not a Sanger fasta file?";
                $contig = 'FINISHED_CONTIG';
            }
            $dna = $pdmp->new_dna_ref($contig);
        } else {
            chomp;
            $$dna .= $_;
        }
    }
    
    if (my $count = $pdmp->contig_count) {
        return $count;
    } else {
        confess "No contigs read";
    }
}

sub write_fasta_file {
    my( $pdmp ) = @_;
    
    my $seq_name = $pdmp->sequence_name;
    my $accno    = $pdmp->accession || '';
    my $dir = $pdmp->file_path;
    my $file = "$dir/$seq_name";
    
    local *FASTA;
    open FASTA, "> $file" or confess "Can't write to '$file' : $!";
    foreach my $contig ($pdmp->contig_list) {
        my $dna = $pdmp->DNA($contig);
        my $len = length($$dna);
        my $c_name = "$seq_name.$contig";
        my $header = join('  ', $c_name,
                               "Unfinished sequence: $seq_name",
                               "Contig_ID: $contig",
                               "acc=$accno",
                               "Length: $len bp");
	print FASTA ">$header\n" or confess "Can't print to '$file' : $!";
	while ($$dna =~ m/(.{1,60})/g) {
	    print FASTA $1, "\n" or confess "Can't print to '$file' : $!";
	}
    }
    close FASTA or confess "Error creating fasta file ($?) $!";
}

sub write_quality_file {
    my( $pdmp ) = @_;
    
    my $seq_name = $pdmp->sequence_name;
    my $accno    = $pdmp->accession || '';
    my $dir = $pdmp->file_path;
    my $file = "$dir/$seq_name.qual";
    
    my $N = 30; # Number of quality values per line
    my $pat = 'A3' x $N;

    local *QUAL;
    open QUAL, "> $file" or confess "Can't write to '$file' : $!";
    foreach my $contig ($pdmp->contig_list) {
        my $qual = $pdmp->BaseQuality($contig);
        my $len = @$qual;
        my $c_name = "$seq_name.$contig";
        my $header = join('  ', $c_name,
                               "Unfinished sequence: $seq_name",
                               "Contig_ID: $contig",
                               "acc=$accno",
                               "Length: $len bp");
	print QUAL ">$header\n" or confess "Can't print to '$file' : $!";
        my $lines = int( @$qual / $N );
        my( $x, $y );
        for (my $l = 0; $l < $lines; $l++) {
            $x = $l * $N;
            $y = $x + $N - 1;
            # Print a slice of the array on one line
            print QUAL pack($pat, @{$qual}[$x..$y]), "\n"
                or confess "Can't print to '$file' : $!";
        }
        # Print out the last line
        if (my $r = @$qual % $N) {
            my $pat = 'A3' x $r;
            $x = $y + 1;
            $y += $r;
            print QUAL pack($pat, @{$qual}[$x..$y]), "\n"
                or confess "Can't print to '$file' : $!";
        }

    }
    close QUAL or confess "Error creating quality file ($?) $!";
}

sub write_embl_file {
    my( $pdmp ) = @_;

    my $seq_name = $pdmp->sequence_name;
    my $dir = $pdmp->file_path;
    my $file = "$dir/$seq_name.embl";
    
    my $embl = $pdmp->embl_file;
    
    local *EMBL;
    open EMBL, "> $file" or confess "Can't write to '$file' : $!";
    print EMBL $embl->compose or confess "Can't write to '$file' : $!";
    close EMBL or confess "Error creating EMBL file ($?) $!";
}

sub embl_file {
    my( $pdmp, $embl ) = @_;
    
    if ($embl) {
        $pdmp->{'_embl_file'} = $embl;
    }
    unless ($embl = $pdmp->{'_embl_file'}) {
        require Hum::ProjectDump::EMBL;
        $embl = Hum::ProjectDump::EMBL::make_embl($pdmp);
        $pdmp->{'_embl_file'} = $embl;
    }
    return $embl;
}

sub embl_checksum {
    my( $pdmp ) = @_;
    
    return $pdmp->embl_file->Sequence->embl_checksum;
}

sub read_accession_data {
    my( $pdmp ) = @_;

    my( $accession, $embl_name, @secondaries ) = acc_data($pdmp->sanger_id);
    $pdmp->accession($accession);
    $pdmp->embl_name($embl_name);
    $pdmp->secondary(@secondaries) if @secondaries;
}

# Fills in information found in the oracle Tracking database
sub read_tracking_details {
    my( $pdmp ) = @_;

    my $project = $pdmp->project_name;
    my $dbh = track_db();
    my $query = qq{
        SELECT c.clonename sequence_name
          , c.speciesname species
          , c_dict.chromosome
          , o.online_path
        FROM chromosomedict c_dict
          , clone c
          , clone_project cp
          , project p
          , online_data o
        WHERE c_dict.id_dict = c.chromosome
          AND c.clonename = cp.clonename
          AND cp.projectname = p.projectname
          AND p.id_online = o.id_online
          AND p.projectname = '$project'
    };
    my $project_details = $dbh->prepare($query);
    $project_details->execute;
    if (my $ans = $project_details->fetchrow_hashref) {
        foreach my $field (keys %$ans) {
            my $meth = lc $field;
            $pdmp->$meth($ans->{$field});
        }
        $pdmp->htgs_phase(is_finished($project) ? 3 : 1);
        $pdmp->fish_map(fishData( $project ));
        my( $author );
        eval{
            $author = project_finisher($project);
        };
        $author ||= project_team_leader($project);
        $pdmp->author($author);
    } else {
        die "Couldn't get project details with query:\n$query"
    }
}

BEGIN {
    my $field = '_secondary';

    sub secondary {
        my $pdmp = shift;

        if (@_) {
            $pdmp->{$field} = [@_];
        }
        return $pdmp->{$field} ? @{$pdmp->{$field}} : ();
    }

    sub add_secondary {
        my( $pdmp, $sec ) = @_;

        push( @{$pdmp->{$field}}, $sec ) if $sec;
    }
}

sub store_dump {
    my( $pdmp ) = @_;
    
    my $sub_db = sub_db();
    my $seq_id = $pdmp->_store_sequence
        or confess "Got no seq_id from _store_sequence()";
    $pdmp->seq_id($seq_id);
    $pdmp->_store_project_dump;
}

=pod

 +------------------+--------------+------+-----+---------+----------------+
 | Field            | Type         | Null | Key | Default | Extra          |
 +------------------+--------------+------+-----+---------+----------------+
 | seq_id           | int(11)      |      | PRI | 0       | auto_increment |
 | sequence_name    | varchar(20)  |      | MUL |         |                |
 | sequence_version | int(11)      | YES  |     | NULL    |                |
 | embl_checksum    | int(11)      |      | MUL | 0       |                |
 | unpadded_length  | int(11)      |      | MUL | 0       |                |
 | contig_count     | int(11)      |      |     | 0       |                |
 | file_path        | varchar(200) |      |     |         |                |
 +------------------+--------------+------+-----+---------+----------------+

=cut

BEGIN {

    my @fields = qw(
        sequence_name
        sequence_version
        embl_checksum
        unpadded_length
        contig_count
        file_path
    );
    
    sub _store_sequence {
        my( $pdmp ) = @_;

        my $sub_db = sub_db();
        my $insert = $sub_db->prepare(q{
            INSERT INTO sequence(seq_id,}
            . join(',', @fields)
            . q{) VALUES (NULL,?,?,?,?,?,?)}
            );
        $insert->execute(map $pdmp->$_(), @fields);
        return $insert->{'insertid'};   # The auto_incremented value
    }
}

=pod

 +------------+-----------------------------+------+-----+---------------------+-------+
 | Field      | Type                        | Null | Key | Default             | Extra |
 +------------+-----------------------------+------+-----+---------------------+-------+
 | sanger_id  | varchar(20)                 |      | MUL |                     |       |
 | dump_time  | datetime                    |      | MUL | 0000-00-00 00:00:00 |       |
 | seq_id     | int(11)                     |      | MUL | 0                   |       |
 | is_current | enum('Y','N')               |      |     | Y                   |       |
 | htgs_phase | enum('1','2','3','4','UNK') |      |     | UNK                 |       |
 +------------+-----------------------------+------+-----+---------------------+-------+

=cut

BEGIN {

    my @fields = qw(
        sanger_id 
        dump_time 
        seq_id    
        htgs_phase
    );
    
    sub _store_project_dump {
        my( $pdmp ) = @_;

        my $sub_db = sub_db();
        my $update = $sub_db->prepare(q{
            UPDATE project_dump
            SET is_current = 'N'
            WHERE sanger_id = ?
            });
        $update->execute($pdmp->sanger_id);
        
        my $insert = $sub_db->prepare(q{
            INSERT INTO project_dump(is_current,}
            . join(',', @fields)
            . q{) VALUES ('Y',?,FROM_UNIXTIME(?),?,?)}
            );
        $insert->execute(map $pdmp->$_(), @fields);
    }
}

1;

__END__



=pod

=head1 NAME - Hum::ProjectDump

=head1 DESCRIPTION

=head2 Author

James Gilbert email B<jgrg@sanger.ac.uk>
