
package Hum::Ace::Reverse;

use strict;
use warnings;

use AceParse qw( aceParse aceQuote );
use Sequence;
use Carp;
use Exporter;
use vars qw( @EXPORT_OK @ISA );
@ISA       = qw( Exporter );
@EXPORT_OK = qw( reverse_sequence );

sub reverse_sequence {
    my( $seq, $fh ) = @_;
    
    confess "Argument '$seq' is not an Ace::Object"
        unless $seq->isa('Ace::Object');
    
    $fh ||= *STDOUT;
    my $name = $seq->name();
    my( $DNA, $length );

    # $dna is a Sequence object
    my $dna = fetchRevCompDNA( $seq );
    
    $length = $dna->length();
    
    print $fh "\n", aceQuote( 'Sequence', ':', $name );
    
    # Do reverse_complementing under 4 tags:
    revComp_Structure     ( $seq, $length, $fh );
    revComp_Assembly_tags ( $seq, $length, $fh );
    revComp_Feature       ( $seq, $length, $fh );
    revComp_Homol         ( $seq, $length, $fh );

    # Print out the reversed DNA
    print $fh "\n-D DNA $name\n";
    $dna->write_ace($fh);
    
    return $dna;
}

BEGIN {

    my %adjNo = (
	         Subsequence     => [2, 3],
	         Clone_left_end  => [2],
	         Clone_right_end => [2],
	         True_left_end   => 0,
	         True_right_end  => 0,
	         Overlap_left    => 0,
	         Overlap_right   => 0,
	         Next_left       => 0,
	         Next_right      => 0,
	         Overlaps        => 0,
	         );
    my %donTpanic = (
	             Length_estimate => 1,
	             Has_STS         => 1,
	             From            => 1,
	             );

    sub revComp_Structure {
        my( $seq, $length, $fh ) = @_;
        my( %scrub, @l );
        my( $table );
        $table = showTag( $seq, 'Structure');
        foreach my $tag (sort keys %adjNo) {
            delPrint( $fh, $tag );
        }
        foreach my $l ( $table->row() ) {
            next unless $l->[1]; # Skip unfilled tags
            my $pos = $adjNo{ $l->[0] };
	    if ( defined($pos) ) {
                if ($pos) {
	            adjNumbers( $length, $pos, $l );
	            # Special case for Clone_end info
                    if ($l->[0] =~ /Clone_(left|right)_end/) {
                        next unless $l->[1] eq $seq->name(); # Only keep hits to self
                        $l->[0] = $1 eq 'left' ? 'Clone_right_end' : 'Clone_left_end';
                    }
                    print $fh aceQuote(@$l);
                }
	    } else {
                carp "Unknown tag '$l->[0]' in '$seq'"
                    unless $donTpanic{ $l->[0] };
            }
        }
    }
}

sub revComp_Assembly_tags {
    my( $seq, $length, $fh ) = @_;
    my( $table );
    # 'Assembly_tags' => [2, 3],
    $table = rawShowTag( $seq, 'Assembly_tags' );
    #prepend( $table, 'Assembly_tags' );
    delPrint( $fh, 'Assembly_tags');
    foreach my $l ( $table->row() ) {
        # 'variation' tags are just thrown away
        # - they're too inconsistent to deal with
        next if $l->[1] =~ /variation/i;
	if (adjNumbers( $length, [2, 3], $l )) {
	    print $fh aceQuote( @$l );
	}
    }
}

sub revComp_Feature {
    my( $seq, $length, $fh ) = @_;
    my( $table );
    # 'Feature' => [2, 3]
    $table = showTag( $seq, 'Feature' );
    prepend( $table, 'Feature' );
    delPrint( $fh, 'Feature' );
    foreach my $l ($table->row()) {
	if (adjNumbers( $length, [2, 3], $l )) {
	    print $fh aceQuote( @$l );
	}
    }
}

BEGIN {

    my %XREF = (
                DNA_homol               => [qw( Sequence DNA_homol         )],
                EST_homol               => [qw( Sequence DNA_homol         )],
                STS_homol               => [qw( Sequence DNA_homol         )],
                GSS_homol               => [qw( Sequence DNA_homol         )],
                vertebrate_mRNA_homol   => [qw( Sequence DNA_homol         )],
                cgidb_homol             => [qw( Sequence DNA_homol         )],
                Pep_homol               => [qw( Protein  DNA_homol         )],
                Motif_homol             => [qw( Motif    DNA_homol         )],
                Oligo_homol             => [qw( Oligo    In_sequence_homol )],
                );

    # 0         1               2               3       4       5       6       7
    # DNA_homol Em:AC002991     embl_blastn     144     61404   61457   10953   11006
    sub revComp_Homol {
        my( $seq, $length, $fh ) = @_;

        # %H is hash for storing homol hits
        my( $table, %H );

        $table = showTag( $seq, 'Homol' );
        delPrint( $fh, 'Homol' );
        foreach my $l ($table->row()) {
	    my( $homol );
	    if ( $l->[1] eq $seq->name ) {
	        # Special case where homology is to self
	        adjNumbers( $length, [4, 5, 6, 7], $l );
	    } else {
	        # Just delete incomplete homol lines
	        next unless defined $l->[7];

	        # Adjust the appropriate fields
	        adjNumbers( $length, [4, 5], $l );
                # Store homology info for deletes in complex hash
                my $name = $l->[1];
                my( $class, $tag ) = @{ $XREF{$l->[0]} };

                # We don't put all the numbers in Motif homol objects
                # They are all repeats, which would produce V.large
                # Motif objects!
                unless ($l->[0] eq 'Motif_homol') {
                    # Make empty array if it doesn't already exist
                    $H{$class}{$name}{$tag} ||= [];

                    push( @{$H{$class}{$name}{$tag}}, [@$l[2, 3, 6, 7, 4, 5]]  );
                }
	    }
	    print $fh aceQuote( @$l );
        }

        # Print output to delete entries on other objects
        foreach my $class ( keys %H ) {
	    foreach my $name ( keys %{$H{$class}} ) {
                print $fh "\n";
                print $fh aceQuote( $class, ':', $name );
                foreach my $tag (keys %{$H{$class}{$name}}) {
                    # Don't need to delete tag since it gets deleted
                    # by the XREF when delete applied in main object
                    #print $fh aceQuote( '-D', $tag, $seq );
                    foreach my $line (@{$H{$class}{$name}{$tag}}) {
                        print $fh aceQuote( $tag, $seq, @$line );
                    }
                }
            }
        }
    }
}

sub fetchRevCompDNA {
    my( $seq ) = @_;
    
    my $name = $seq->name();
    
    # Fetch the dna:
    my( $DNA, $dbLength );
    eval {
        $DNA      = $seq->at('DNA[1]')->fetch->at();
        $dbLength = $seq->at('DNA[2]')->name();
    };
        
    if ($DNA) {
    
        # Make new Sequence object and rev_comp
        my $dna = Sequence->new_from_strings($name, "$DNA");
        $dna->revcomp_iub();
    
	my $length = $dna->length();
	
	# Check fetched DNA is same length as
	# tagged in acedb
	unless ( $dbLength == $length ) {
	    confess "Error: $name: DNA length inconsistent";
	}
        
        return $dna;
        
    } else {
	confess "Error: $name: Can't fetch DNA";
    }
}

sub delPrint {
    my $fh = shift;
    print $fh aceQuote( '-D', @_ );
}


sub showTag {
    my( $obj, $tag ) = @_;
    my( $data );
    {
        local $^W = 0;
        $data = $obj->at($tag)->asAce();
    }
    my $table = AceParse->aceTable( \$data );
    return $table;
}

# Needed until Lincoln correctly deals with quoting multi-line
# tags in asAce() in AcePerl.
sub rawShowTag {
    my( $obj, $tag ) = @_;
    
    my $db    = $obj->db();
    my $class = $obj->class();
    my $name  = $obj->name();
    $db->raw_query("find $class $name");
    my $data = $db->raw_query("show -a $tag");
    $data =~ s/\0//g;       # Remove nulls
    $data =~ s{^//.+$}{}mg; # Remove comments
    my $table = AceParse->aceTable( \$data );
    shift( @$table ); # Remove first line which is "Class : foo"
    return $table;
}

sub prepend {
    my( $table, $tag ) = @_;
    
    foreach my $row ($table->row()) {
        unshift(@$row, $tag);
    }
}

sub adjNumbers {
    my($length, $pos, $line) = @_;
       
    foreach my $p ( @$pos ) {
	my $num = $line->[$p];
	if ($num) {
	    unless ( (int $num) eq $num ) {
		confess "Error: Not an integer ('$num') in line (",
                    join(' ', map "'$_'", @$line ). ')';
	    }
	} else {
	    undef $line;
	    return;
	}
	# Here's the actual arithmetic:
	$line->[$p] = (($length - 1) - ($num - 1)) + 1;
    }
    return 1;
}

1;

__END__

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>
