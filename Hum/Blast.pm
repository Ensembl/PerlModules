
### Hum::Blast

package Hum::Blast;

use strict;
use Hum::Blast::Subject;
use Carp;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub file_handle {
    my( $self, $fh ) = @_;
    
    if ($fh) {
        confess "Not a filehandle ref '$fh'"
            unless $fh and ref($fh) eq 'GLOB';
        $self->{'_file_handle'} = $fh;
    }
    return $self->{'_file_handle'};
}

sub expect_cutoff {
    my( $self, $cutoff ) = @_;
    
    if (defined $cutoff) {
        $self->{'_expect_cutoff'} = $cutoff;
    }
    return $self->{'_expect_cutoff'} || 0.001;
}

sub query_name {
    my( $self, $query ) = @_;
    
    if ($query) {
        $self->{'_query_name'} = $query;
    }
    return $self->{'_query_name'};
}

sub clear_query_name {
    my( $self, $query ) = @_;
    
    $self->{'_query_name'} = undef;
}

sub database_name {
    my( $self, $db ) = @_;
    
    if ($db) {
        $self->{'_database_name'} = $db;
    }
    return $self->{'_database_name'};
}

sub clear_database_name {
    my( $self, $query ) = @_;
    
    $self->{'_database_name'} = undef;
}


sub set_line_cache {
    my( $self, $line ) = @_;
    
    confess "Called without line argument"
        unless defined $line;
    if (my $l = $self->{'_line_cache'}) {
        confess "Already have line '$l' in cache\n",
            "Was asked to add '$line'";
    } else {
        $self->{'_line_cache'} = $line;
    }
}

sub get_line_cache {
    my( $self ) = @_;
    
    my $line = $self->{'_line_cache'};
    $self->{'_line_cache'} = undef;
    return $line;
}

sub next_Subject {
    my( $self ) = @_;

    my $fh = $self->file_handle
        or confess "No file_handle";
    $_ = $self->get_line_cache;

    my( $hit );
    while (defined($_ ||= <$fh>)) {
        
        if (/^(Statistics|Parameters)/) {
            # Have detected elements of the footer
            $self->clear_database_name;
            $self->clear_query_name;
        }
        elsif (/^\s*Query\W+(\w\S*)/) {
            # We've found the name of the query
            $self->query_name($1);
        }
        elsif (/^\s*Database\W+(\w\S*)/) {
            # We're at the beginning of a new report
            my ($db_name) = $1 =~ m{([^/]+)$};
            $self->database_name($db_name);
        }
        elsif (/^>/) {
            my $db_name        = $self->database_name;
            my $query_seq_name = $self->query_name;
            unless ($db_name and $query_seq_name) {
                die "Failed to parse header: db_name='$db_name' query_name='$query_seq_name'";
            }
            $self->set_line_cache($_);
            if (my $subject = $self->parse_Subject) {
                return $subject;
            } else {
                $_ = $self->get_line_cache;
                next;
            }
        }
        $_ = undef;
    }
    return;
}


sub parse_Subject {
    my( $self ) = @_;
    
    my $fh = $self->file_handle
        or confess "No file_handle";
    $_ = $self->get_line_cache;
    my $expect_cutoff = $self->expect_cutoff;
    
    my $subject = Hum::Blast::Subject->new;
    
    # Get the accession number of the Subject
    my ($id_string, $acc) = /^>\s*(\S+)\s+(\S+)?/
        or confess("Can't parse ID line ('$_')");
    if (! $acc or $acc eq 'bases') {
        $acc = $id_string;
    }
    if ($id_string =~ /\|([^\|]+)$/) {
        $acc = $1;
    }
    $subject->subject_name($acc);
    
    # Get everything up to the next blank line...
    while (defined(my $tmp = <$fh>)) {
        last if $tmp =~ /^\s*$/;
        $_ .= $tmp
    }
    # ...and record the length of the Subject sequence
    my ($length) = /length\s*=\s*([\d,]+)/i
        or confess("Can't parse length from ('$_')");
    $length =~ s/,//g;  # Remove commas from long numbers
    $subject->subject_length($length);
    
    # Now parse the HSPs
    my( $hsp );
    while (<$fh>) {
        # Skip blank lines and lines starting with six spaces.
        next if /(^$|^\s{6})/;
        
        # Skip gratuitous label
        next if /^\s*(Plus|Minus)/;
        
        if (/^\s*Score/) {
            $_ .= <$fh>;    # We want the next line as well
            
            $hsp = undef;   # Forget the last HSP (It is
                            # stored in the Subject object);
            
            # Parse out the score
            # Score = 1078 bits (544)   -- Blast 2 format
            # Score = 1667 (766.8 bits) -- Blast 1 format
            my( $score );
            ($score) = /Score\s*=\s*[\d\.]+\s*bits\s*\(([\d\.]+)/
                or ($score) = /Score\s*=\s*([\d\.]+)\s*\([\d\.]+\s*bits/
                or confess("Can't parse score from ('$_')");
            
            # Parse out the identity
            # Identities = 544/544
            my ($identity) = /Identities\s*=\s*(\d+)\//
                or confess("Can't parse identity from ('$_')");
            
            # Parse out the expect value
            # Expect = 5.4e-116
            # Expect(16) = 0.0          -- Blast 2 format
            # Expect = 0.0              -- Blast 1 format
            my ($expect) = /Expect(?:\(\d+\))?\s*=\s*([\d\.eE-]+)/
                or confess("Can't parse expect value from ('$_')");
            
            # expect_cutoff can be set to zero
            # if we want all HSPs
            unless ($expect < $expect_cutoff) {
                $hsp = $subject->new_HSP;
                $hsp->score($score);
                $hsp->identity($identity);
                $hsp->expect($expect);
            }
        }
        elsif (/^\s*Query:\s*(\d+)[^\d]+(\d+)/) {
            next unless $hsp;   # expect is below cutoff
            $hsp->query_start($1) unless $hsp->query_start;
            $hsp->query_end($2);
        }
        elsif (/^\s*Sbjct:\s*(\d+)[^\d]+(\d+)/) {
            next unless $hsp;   # expect is below cutoff
            $hsp->subject_start($1) unless $hsp->subject_start;
            $hsp->subject_end($2);
        }
        else {
            # End of subject
            $self->set_line_cache($_);
            last;
        }
    }
    
    # Sort the HSPs in the Subject, and return it
    if ($subject->count_HSPs) {
        $subject->sort_HSPs_by_query_start_end;
        return $subject;
    } else {
        return;
    }
}


1;

__END__

=head1 NAME - Hum::Blast

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

