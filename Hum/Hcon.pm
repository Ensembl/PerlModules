
package Hum::Hcon;

use Hum::Hcon::Filter;

use strict;
use Carp;

use AceParse qw( aceQuote );
use Sequence;
use humpubace qw( acedate );

use vars qw( $AUTOLOAD );

sub new {
    my $pkg = shift;
    my( $name, $suffix ) = @_;
    

    unless ($name) {
	confess "new(): name not specified";
    }

    my $table = AceParse->new();

    return bless {
	name => $name,
	suffix => $suffix,
	novel => '',
	changed => '',
	contig => [],  # An array of Hcon objects
	seq => '',     # A Sequence object
	filter => '',  # A Hum::Hcon::Filter object
	tags => $table # An AceParse aceTable object
    }, $pkg;
}

##########################################
# Access methods

my %autoloadMethods = map {$_, 1} qw(
				     name
				     suffix
				     novel
				     changed
				     seq
				     filter
				     tags
				     );
sub AUTOLOAD {
    my $hcon = shift;
    my( $type );

    my $name = $AUTOLOAD;

    $name =~ s/.*://; #get only the bit we want

    # Ignore DESTROY messages...
    return if $name eq 'DESTROY';
    
    unless ($type = ref($hcon)) {
        confess "[$hcon] is not an object; can't use AUTOLOAD to access [$name]";
    }

    # Only allow access to fields listed in %autoloadMethods
    if ($autoloadMethods{$name}) {
	if (@_) {
	    $hcon->{$name} = shift;
	} else {
	    return $hcon->{$name};
	}
    } else {
	confess "Unknown field [$name] in [$type] object";
    }
}

sub contig {
    my $hcon = shift;

    if (@_) {
	push( @{$hcon->{'contig'}}, @_ );
    } else {
	return @{$hcon->{'contig'}};
    }
}

sub addTag {
    my $hcon = shift;
    my @tagLine = @_;

    confess "addTag(): no data supplied" unless @tagLine;

    my $table = $hcon->tags();
    $table->addRow( @tagLine );
}

##########################################
# Smart methods

sub tagByName {
    my $hcon = shift;
    my $name = lc shift;

    my $table = $hcon->tags();
    foreach my $r ($table->rowIndex) {
	if (lc $table->cell($r, 0) eq $name) {
	    my @row = $table->row($r);
	    # Remove first element from row
	    shift @row;
	    return @row;
	}
    }
    return;
}

sub acePrint {
    my( $hcon, $fh ) = @_;

    foreach my $contig ($hcon->contig()) {
	print $fh "\n",
	aceQuote( 'Sequence', ':', $contig->name );

	# Contigs get copy of top-level info
	$hcon->filterPrint( $fh );

	# Print info from this contig
	$contig->filterPrint( $fh );

	# Then print out sequence
	if (my $seq = $contig->seq()) {
	    $seq->write_ace($fh);
	}
    }
}

sub filterPrint {
    my( $hcon, $fh ) = @_;

    # Print out ace formatted info, applying filter if present
    if (my $table = $hcon->tags()) {
	if (my $filter = $hcon->filter()) {
	    foreach my $row ($table->row()) {
		if (my @clean = $filter->validate( $row )) {
		    print $fh aceQuote( @clean );
		}
	    }
	} else {
	    # It's just a straight print if no filter
	    $hcon->tags()->print($fh);
	}
    }
}

sub pacePrint {
    my( $hcon, $fh ) = @_;

    my $seqName = $hcon->name;

    # Print out entries for parent sequence
    print $fh "\n",
    aceQuote( 'Sequence', $seqName ),
    aceQuote( 'Analysis', acedate() ),
    aceQuote( '-D', 'DNA_contig' );
    foreach my $contig ($hcon->contig) {
	print $fh aceQuote( 'DNA_contig', $contig->name );
    }

    # Print out individual contigs
    foreach my $contig ($hcon->contig) {
	print $fh "\n",
	aceQuote( 'DNA_contig', ':', $contig->name ),
	aceQuote( 'Parent', $seqName ),
	aceQuote( 'Contig_finished_length', $contig->seq()->length );
    }
}

sub processMkconOutput {
    my( $pkg, $name, $fh ) = @_;

    # Gives a max of 702 contigs!
    my @suffices = ('A'..'ZZ');

    # Make a new hcon object
    my $hcon = $pkg->new($name);
    $hcon->tags( AceParse->new() );

    local $/ = "";

    # Blocks from mkcon-gap are DNA followed by ace formatted sequence info
    for (my $i = 0; defined(my $DNA = <$fh>); $i++) {

	my $tags = <$fh>;

	my( $moniker, $suffix, $contig, $seq, $ace, @firstRow );

	# Name gets suffix if multiple contigs
	if (eof($fh) and $i == 0) {
	    $moniker = $name;
	} else {
	    $suffix = $suffices[$i];
	    $moniker = $name . $suffix;
	}

	# Make a new Hcon object
	$contig = $pkg->new($moniker, $suffix);

	# Remove first line from DNA chunk
	unless ($DNA =~ s/^DNA.+?\n//) {
	    warn "Chunk [ $DNA ] is not DNA";
	    return;
	}
	$DNA =~ s/\s+//g;

	# Make a new sequence object and store it in the Hcon object
	$seq = Sequence->new_from_strings( $moniker, $DNA );
	$seq->lowercase();
	$contig->seq($seq);

	$ace = AceParse->aceTable( \$tags );
	@firstRow = $ace->shiftRow();
	unless ($firstRow[0] =~ /^Sequence$/) {
	    warn "Object is not from Sequence class [ @firstRow ]";
	    return;
	}
	$contig->tags($ace);

	# Add this contig to the parent Hcon object
	$hcon->contig($contig);
    }
    return $hcon;
}

1;
