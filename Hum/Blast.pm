
### Hum::Blast

package Hum::Blast;

use strict;
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

sub query_name {
    my( $self, $query ) = @_;
    
    if ($query) {
        $self->{'_query_name'} = $query;
    }
    return $self->{'_query_name'};
}

sub expect_cutoff {
    my( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_expect_cutoff'} = $value;
    }
    return $self->{'_expect_cutoff'} || 0.001;
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

sub set_line_cache {
    my( $self, $line ) = @_;
    
    confess "Called without line argument"
        unless defined $line;
    if (my $l = $self->{'_line_cache'}) {
        confess "Already have line '$l' in cache\n"
            "Was asked to add '$line'";
    } else {
        $self->{'_line_cache'} = $line;
    }
}

sub get_line_cache {
    my( $self, $line ) = @_;
    
    return $self->{'_line_cache'};
}

sub next_hit {
    my( $self ) = @_;

    my( $db_name,           # Name of the db being searched (eg: "swir")
        $query_seq_name,    # Name of the query sequence (eg: "dJ357N32")
        );
    my $fh = $self->file_handle
        or confess "No file_handle";

    while (defined($_ ||= <$fh>)) {
        # Return if we detect elements of the footer
        return if /^Parameters/;

        if (/^\s*Query\W+(\w\S*)/) {
            die "Parse error: not in header: $_" if $query_seq_name;
            $query_seq_name = $1;
        }
        elsif (/^\s*Database\W+([\w]\S*)/) {
            return if $db_name; # Database is repeated in footer
            ($db_name) = $1 =~ m{([^/]+)$};
            $query_seq_name = undef;
        }
        elsif (/^>/) {
            unless ($query_seq_name and $db_name) {
                die "Failed to parse header: db_name='$db_name' query_name='$query_seq_name'";
            }
            my $hit = BlastHit->new();
            $hit->set_homol_tag($homol_tag);
            $hit->set_method_name($method_name);
            $hit->set_query_name($query_seq_name);
            $hit->set_db_name($db_name);
            $hit->set_expect_cutoff($expect_cutoff);
            $hit->parse_hit($fh);
            $hit->sort_by_query_coords;
            $hit->print_ace(\*STDOUT);
            next;   # Don't empty $_ -- its got the next ">Hit etc.." line in it
        }
        $_ = undef;
    }
}



1;

__END__

=head1 NAME - Hum::Blast

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

