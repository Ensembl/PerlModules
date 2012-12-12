

# Used as a placeholder where elements aren't known in ID and AC lines.
my $UNK_STR = 'XXX';


=pod

=head1 NAME - Hum::EMBL::Line

=head1 DESCRIPTION

The file containing this package contains the
baseclass B<Hum::EMBL::Line> and line handling
packages for most of the standard EMBL line
types, which all inherit from it.  The baseclass
contains subroutines called at compile time to
generate standard data access functions for the
line object classes.

See L<Hum::EMBL> for more complete information.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

=cut

package Hum::EMBL::Line;

use strict;
use warnings;
use Carp;


sub new {
    my( $pkg ) = @_;
    
    return return bless {
        _string => undef,
        _data   => {},
    }, $pkg;
}

sub store {
    my $pkg = shift;
    
    if (@_) {
        my $line = $pkg->new();
        $line->string( @_ );
        return $line;
    } else {
        confess "No data provided";
    }
}

sub parse {
    my( $line ) = @_;
    
    my $pkg = ref( $line );
    confess "parse method not implemented in package '$pkg'";
}

sub _compose {
    my( $line ) = @_;
    
    my $pkg = ref($line);
    confess "_compose method not implemented in package '$pkg'";
}

sub makeFieldAccessFuncs {
    my( $pkg, @names ) = @_;
    
    foreach my $field (@names) {
        no strict 'refs';
    
        my $func = "${pkg}::$field";
        *$func = sub {
            my( $line, $data ) = @_;

            if (defined $data) {
                $line->data->{$field} = $data;
            } else {
                return $line->data->{$field};
            }
        }
    }
}

sub makeListAccessFuncs {
    my( $pkg, @names ) = @_;
    
    foreach my $field (@names) {
        no strict 'refs';
    
        my $func = "${pkg}::$field";
        *$func = sub {
            my $line = shift;

            if (@_) {
                $line->data->{$field} = [@_];
            } else {
                if ($line->data->{$field}) {
                    return @{$line->data->{$field}};
                } else {
                    return;
                }
            }
        }
    }
}

# Called by compose() in Hum::EMBL on each line
sub compose {
    my( $line ) = @_;
    
    if (my $string = $line->string) {
        return $string;
    } else {
        return $line->string($line->_compose);
    }
}

# Allows some line types to override this
# so that we can ignore data such as the
# RL submission date when comparing EMBL
# entries.
sub string_for_checksum {
    my $line = shift;
    
    return join '', $line->compose;
}

# Sets the string and empties the data hash
# if called with arguments.
# Returns the stored string
sub string {
    my $line = shift;
    
    if (@_) {
        $line->{'_data'} = {};
        $line->{'_string'} = join '', @_;
    }
    return $line->{'_string'};
}

sub data {
    my( $line ) = @_;
    
    if (my $s = $line->{'_string'}) {
        $line->{'_string'} = undef;
        $line->parse(\$s);
    }
    return $line->{'_data'};
}



{
    my $max   = 75;         # Maximum length for a line
    my $limit = $max - 1;

    sub wrap {
        my( $line, $prefix, $text ) = @_;

        # Test for a string longer than $max which can't be split on spaces
        confess "String '$1' too long to wrap"
            if $text =~ /(\S\S{$max,})/o;

        my( @lines );
        while ($text =~ /(.{0,$limit}\S)(\s+|$)/og) {
            push( @lines, "$prefix$1\n" );
        }

        return @lines;
    }

    sub commaWrap {
        my( $line, $prefix, $text ) = @_;

        my( @lines );
        while ($text =~ /\s*(.{1,$limit}(,|$))/og) {
            push( @lines, $prefix . $1 . "\n" );
        }
        return @lines;
    }
}

###############################################################################

=pod

ID   CD789012; SV 4; linear; genomic DNA; HTG; MAM; 500 BP.
       (1)     (2)     (3)      (4)       (5)  (6)   (7)

Tokens:

   1. Primary accession number.
   2. 'SV' + sequence version number.
   3. Topology: 'circular' or 'linear'.
   4. Molecule type.
   5. Data class (ANN, CON, PAT, EST, GSS, HTC, HTG, MGA,
      WGS, TPA, STS, STD,
      "normal" entries will have STD for standard).
   6. Taxonomic division (HUM, MUS, ROD, PRO, MAM, VRT,
      FUN, PLN, ENV, INV, SYN, UNC, VRL, PHG)."
   7. Sequence length + 'BP.'.


For a new submission, all tokens apart from number
3 (topology) and 7 (length) are non-mandatory; for
new submissions that are EST, GSS, HTC, HTG, and
STS, correct dataclass (5) is also mandatory

For the updates, mandatory tokens are 1
(accession), 3 (topology), 7 (length) and for EST,
GSS, HTC, HTG, and STS correct dataclass (5) is
mandatory

All tokens that are non-mandatory can be
represented by a universal placeholder "XXX", so
in the ID line in the new submission can look as
follows

ID   XXX; XXX; linear; XXX; XXX; XXX; 500 BP.

or, for EST, GSS, HTC, HTG, and STS :

ID   XXX; XXX; linear; XXX; HTG; XXX; 500 BP.

For the updates, the first token must be the
primary accession number, so the least defined ID
line can look

ID   YY010101; XXX; linear; XXX; XXX; XXX; 500 BP.

(again, for EST, GSS, HTC, HTG, and STS 5th token
must also be specified)


Change to AC line
----
NOTE: you only need to read the following it you
have to specify secondary accession numbers in the
AC line from time to time

The new ID line format affects the AC line format
in new submissions. Currently, the AC line format
for new submissions without and with a secondary
accession number CT999999 is:

AC   ;
AC   ACCESSION; CT999999;

Instead of the word 'ACCESSION' the new AC line
format uses the universal placeholder 'XXX':

AC   ;
AC   XXX;
AC   XXX; CT999999;

Please note that we continue to accept 'AC   ;'
and that it is functionally equivalent to
'AC   XXX;'.

For updates the assigned accession number should
be given as the first token in the AC line, like:

AC   YY010101;
AC   YY010101; CT999999;

Mixtures (i.e. old style ID line + new style AC
line) will not be allowed.

=cut

package Hum::EMBL::Line::ID;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::ID->makeFieldAccessFuncs(
    qw(
      accession
      version
      is_circular
      molecule
      dataclass
      division
      seqlength
      )
);

sub parse {
    my( $line, $s ) = @_;
    
    # ID   CD789012; SV 4; linear; genomic DNA; HTG; MAM; 500 BP.
    #      1         2     3       4            5    6    7
    
    my (
        $accession, $version,
        $topology,  $moltype,
        $dataclass, $division,
        $length
    )
    = map { $_ eq $UNK_STR ? undef : $_ }
      $$s =~ /^ID   (\S+);\s+SV\s+(\S+);\s+(linear|circular);\s+([^;]+);\s+(\S+);\s+(\S+);\s+(\d+)/
        or confess "Can't parse ID line: $$s";

    $line->accession  ( $accession              );
    $line->version    ( $version                );
    $line->is_circular( $topology eq 'circular' );
    $line->molecule   ( $moltype                );
    $line->dataclass  ( $dataclass              );
    $line->division   ( $division               );
    $line->seqlength  ( $length                 );
}

sub _compose {
    my( $line ) = @_;
    
    my $accession = $line->accession    || $UNK_STR;
    my $version   = $line->version      || $UNK_STR;
    my $topology  = $line->is_circular ? 'circular ' : 'linear';
    my $molecule  = $line->molecule     || $UNK_STR;
    my $dataclass = $line->dataclass    || $UNK_STR;
    my $division  = $line->division     || $UNK_STR;
    my $length    = $line->seqlength;
    
    return "ID   $accession; SV $version; $topology; $molecule; $dataclass; $division; $length BP.\n";
}

###############################################################################

# This is the obsolete format of EMBL ID line.

package Hum::EMBL::Line::ID1;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::ID1->makeFieldAccessFuncs(
    qw(
      entryname
      dataclass
      is_circular
      molecule
      division
      seqlength
      )
);

sub parse {
    my( $line, $s ) = @_;
    
    my( $entryname, $dataclass, $is_circular, $molecule, $division, $length ) =
        $$s =~ /^ID   (\S+)\s+(\S+);\s+(circular\s+)?([\w ]+);\s+(\S+);\s+(\d+)/
        or confess( "Can't parse ID1 line: $$s" );
    
    $line->entryname( $entryname );
    $line->dataclass( $dataclass );
    $line->molecule ( $molecule  );
    $line->is_circular(1) if $is_circular;
    $line->division ( $division  );
    $line->seqlength( $length    );
}

sub _compose {
    my( $line ) = @_;
    
    my $entryname = $line->entryname();
    my $dataclass = $line->dataclass();
    my $circular  = $line->is_circular ? 'circular ' : '';
    my $molecule  = $line->molecule ();
    my $division  = $line->division ();
    my $length    = $line->seqlength();
    
    return "ID   $entryname  $dataclass; $circular$molecule; $division; $length BP.\n";
}

###############################################################################

package Hum::EMBL::Line::AC;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::AC->makeFieldAccessFuncs(qw( primary     ));
Hum::EMBL::Line::AC->makeListAccessFuncs (qw( secondaries ));

sub parse {
    my( $line, $s ) = @_;
    
    my @lines = $$s =~ /^AC   (.+)$/mg;
    my( @ac );
    foreach (@lines) {
        push( @ac, split /;\s*/ );
    }
    if (my $primary = shift @ac) {
        $line->primary( $primary eq $UNK_STR ? undef : $primary );
    }
    $line->secondaries( @ac );
}

sub _compose {
    my( $line ) = @_;
    
    my $primary = $line->primary;
    my @second  = $line->secondaries;

    my $ac = join( ' ', map "$_;", ($primary || $UNK_STR, @second) );
    
    return $line->wrap('AC   ', $ac);
}

###############################################################################

package Hum::EMBL::Line::CC;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::CC->makeListAccessFuncs( 'list' );

sub parse {
    my( $line, $s ) = @_;
    
    my @lines = $$s =~ /^CC   (.+)$/mg;
    $line->list(@lines);
}

sub text {
    my( $line, $text ) = @_;
    
    if (defined $text) {
        $line->list($text);
    }
    return join ' ', $line->list;
}

sub _compose {
    my( $line ) = @_;
    
    my( @compose );
    foreach my $txt ($line->list()) {
        push( @compose, $line->wrap('CC   ', $txt) );
    }
    return @compose;
}

###############################################################################

package Hum::EMBL::Line::KW;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::KW->makeListAccessFuncs( 'list' );

sub parse {
    my( $line, $s ) = @_;
    
    my @lines = $$s =~ /^KW   (.+)$/mg;
    my( @kw );
    foreach (@lines) {
        push( @kw, split /;\s*/ );
    }
    # Remove full-stop from the last word
    $kw[$#kw] =~ s/\.$//;
    $line->list(@kw);
}

sub _compose {
    my( $line ) = @_;
    
    my $kw = join('; ', $line->list()) . '.';
    
    return $line->wrap('KW   ', $kw);
}

###############################################################################

package Hum::EMBL::Line::DT;

use strict;
use warnings;
use Carp;
use Hum::EMBL::Utils qw( EMBLdate dateEMBL );
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::DT->makeFieldAccessFuncs(qw(
                                             createdDate
                                             createdRelease
                                             date
                                             release
                                             version
                                             ));

sub parse {
    my( $line, $s ) = @_;
    
    my @lines = split /\n/, $$s;
    
    # DT   07-NOV-1985 (Rel. 07, Created)
    my( $createdDate, $createdRelease ) = $lines[0] =~
        /DT   (\S+) \(Rel. (\d+), Created/
        or confess "Can't parse DT line: $lines[0]";
    
    # DT   20-FEB-1990 (Rel. 23, Last updated, Version 1)
    my( $date, $release, $version )     = $lines[1] =~
        /DT   (\S+) \(Rel. (\d+), Last updated, Version (\d+)/
        or confess "Can't parse DT line: $lines[1]";

    $date        = dateEMBL( $date );
    $createdDate = dateEMBL( $createdDate );

    $line->createdDate   ($createdDate   );
    $line->createdRelease($createdRelease);
    $line->date          ($date          );
    $line->release       ($release       );
    $line->version       ($version       );
}

sub _compose {
    my( $line ) = @_;
    
    my $createdDate    = $line->createdDate   ();
    my $createdRelease = $line->createdRelease();
    my $date           = $line->date          ();
    my $release        = $line->release       ();
    my $version        = $line->version       ();
    
    $date        = EMBLdate( $date );
    $createdDate = EMBLdate( $createdDate );
    
    # Pad release version to 2 character length
    foreach ($createdRelease, $release) {
        $_ = ('0' x (2 - length($_))) . $_;
    }
    
    # DT   07-NOV-1985 (Rel. 07, Created)
    # DT   20-FEB-1990 (Rel. 23, Last updated, Version 1)
    return ("DT   $createdDate (Rel. $createdRelease, Created)\n",
            "DT   $date (Rel. $release, Last updated, Version $version)\n");
}

###############################################################################

package Hum::EMBL::Line::DE;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::DE->makeListAccessFuncs( 'list' );

sub parse {
    my( $line, $s ) = @_;
    
    my @lines = $$s =~ /^DE   (.+)$/mg;
    my $text = join ' ', @lines;
    $line->list($text);
}

sub _compose {
    my( $line ) = @_;
    
    my( @compose );
    foreach my $txt ($line->list()) {
        push( @compose, $line->wrap('DE   ', $txt) );
    }
    return @compose;
}

###############################################################################

package Hum::EMBL::Line::XX;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );
@ISA = qw( Hum::EMBL::Line );


sub new {
    my( $pkg ) = @_;
    return bless {}, $pkg;
}

sub store {
    my $pkg = shift;
    
    if (@_) {
        return $pkg->new();
    } else {
        confess "No data provided";
    }
}

sub compose {
    return "XX\n";
}

###############################################################################

package Hum::EMBL::Line::SV;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::SV->makeFieldAccessFuncs(qw( accession version ));

sub parse {
    my( $line, $s ) = @_;
    
    my( $acc, $version ) = $$s =~ /^SV   (\S+)\.(\d+)/
        or die "Can't parse SV line: $$s";
    $line->accession( $acc     );
    $line->version  ( $version );
}

sub _compose {
    my( $line ) = @_;
    
    my $acc     = $line->accession;
    my $version = $line->version;
    
    return "SV   $acc.$version\n";
}

###############################################################################

package Hum::EMBL::Line::NI;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::NI->makeFieldAccessFuncs(qw( identifier ));

sub parse {
    my( $line, $s ) = @_;
    
    my( $version ) = $$s =~ /^NI   (\S+)/
        or die "Can't parse NI line: $$s";
    $line->identifier( $version );
}

sub _compose {
    my( $line ) = @_;
    
    my $nuc = $line->identifier();
    return "NI   $nuc\n";
}


###############################################################################

package Hum::EMBL::Line::Reference;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::Reference->makeFieldAccessFuncs(qw(
                                                    number
                                                    title
                                                    group
                                                    ));
Hum::EMBL::Line::Reference->makeListAccessFuncs(qw(
                                                   authors
                                                   locations
                                                   comments
                                                   positions
                                                   xrefs
                                                   ));

sub parse {
    my( $line, $s ) = @_;
        
    # The number of this reference
    my ($number) = $$s =~ /^RN   \[(\d+)/m
        or die "Can't parse reference number from:\n$$s";
    $line->number( $number );
    
    # Comments about this reference
    my( @comments );
    while ($$s =~ /^RC   (.+)$/mg) {
        push( @comments, $1 );
    }
    $line->comments( join(' ', @comments) );
    
    # Positions in the nucleotide sequence associated with
    # this reference.  Could store as Location objects, but
    # they have a different format to FT location lines.
    my( @positions );
    while ($$s =~ /^RP   (.+)$/mg) {
        push( @positions, split( /,\s*/, $1) );
    }
    $line->positions( @positions );
    
    # Database cross-references (Only MEDLINE at the time
    # of writing).  Stored as a list of mini-objects.
    my( @xrefs );
    while ($$s =~ /^RX   (\S+);\s+(.+)\.$/mg) {
        my $xr = 'Hum::EMBL::Line::XRef'->new();
        $xr->db( $1 );
        $xr->id( $2 );
        push( @xrefs, $xr );
    }
    $line->xrefs( @xrefs );
    
    # Reference group
    my( @group );
    while ($$s =~ /^RG   (.+)$/mg) {
        push @group, $1;
    }
    $line->group(join ' ', @group);
    
    # The authors of the reference
    my( @authors );
    while ($$s =~ /^RA   (.+)$/mg) {
        push( @authors, split(/,\s*|;\s*/, $1) );
    }
    $line->authors( @authors );
    
    # The title of the reference
    my @title = $$s =~ /^RT   (.*?);?$/mg;
    my $title = join ' ', @title;
    $title =~ s/^"|"$//g;
    $line->title( $title );
    
    # Locations are actually quite complex, and may refer
    # to papers, books, patents, or the addresses of the
    # authors.  I decided to just store them verbatim,
    # until it is deemed necessary to do something more
    # sophisticated.
    my @locations = $$s =~ /^RL   (.+)$/mg;
    $line->locations( @locations );
}

sub _compose {
    my( $line ) = @_;
    
    my( @compose );
    
    my $num = $line->number();
    push( @compose, "RN   [$num]\n" );
    
    foreach my $comment ($line->comments) {
        push( @compose, $line->wrap('RC   ', $comment) );
    }
    
    my $pos_line = join(',', $line->positions);
    push( @compose, $line->commaWrap('RP   ', $pos_line) );
    
    foreach my $xr ($line->xrefs) {
        my $db = $xr->db();
        my $id = $xr->id();
        push( @compose, "RX   $db; $id.\n" );
    }
    
    if (my $group = $line->group) {
        push(@compose, $line->wrap('RG   ', $group));
    }
    
    my $au_line = join(', ', $line->authors) . ';';
    push( @compose, $line->commaWrap('RA   ', $au_line) );
    
    if (my $title = $line->title) {
        push( @compose, $line->wrap('RT   ', qq("$title";)) );
    } else {
        push( @compose, "RT   ;\n" );
    }
    
    foreach my $loc ($line->locations) {
        push( @compose, $line->wrap('RL   ', $loc) );
    }
    
    return @compose;
}

sub string_for_checksum {
    my( $line ) = @_;

    my @compose = $line->_compose;

    for (my $i = 0; $i < @compose;) {
        my $str = $compose[$i];
        # Don't return the Submitted date line
        # for inclusion in the checksum.
        if ($str =~ /^RL   Submitted /) {
            splice(@compose, $i, 1);
        } else {
            $i++;
        }
    }

    return join('', @compose);
}

###############################################################################

# Database cross references occur in three
# places in EMBL files:
# 
#   Reference 'RX' lines (Medline only at the time of writing).
#   'DR' lines.
#   In the '/db_xref' feature qualifier.
# 
# This package was supposed to be used by all three, but at
# the moment it's only used by Reference objects.

package Hum::EMBL::Line::XRef;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::XRef->makeFieldAccessFuncs(qw(
                                               db
                                               id
                                               ));



###############################################################################



package Hum::EMBL::Line::DR;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::DR->makeFieldAccessFuncs(qw(
                                             db
                                             id
                                             secondary
                                             ));

sub store {
    my $pkg = shift;
    
    my( @db_xrefs );
    foreach my $line (@_) {
        my $dr = $pkg->new();
        $dr->string( $line );
        push( @db_xrefs, $dr );
    }
    return( @db_xrefs );
}

sub parse {
    my( $line, $s ) = @_;
        
    my( $db, $id, $sec ) = $$s =~ /DR   (\S+); (\S+); (\S+)\.$/
        or confess "Can't parse DR line: $$s";
    my $xref = 'Hum::EMBL::Line::XRef'->new();
    $line->db       ( $db  );
    $line->id       ( $id  );
    $line->secondary( $sec );
}

sub _compose {
    my( $line ) = @_;
    
    my $db   = $line->db();
    my $prim = $line->id();
    my $sec  = $line->secondary();
    
    return "DR   $db; $prim; $sec.\n";
}

###############################################################################

package Hum::EMBL::Line::Organism;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::Organism->makeFieldAccessFuncs(qw(
                                                   species
                                                   genus
                                                   common
                                                   verbatim
                                                   ));
Hum::EMBL::Line::Organism->makeListAccessFuncs(qw(
                                                  classification
                                                  ));

sub parse {
    my( $line, $s ) = @_;
            
    my ($genus, $species, $common, $verbatim);
    
    unless (($genus, $species, $common) = $$s =~ 
        /^OS   (\S+)(?:\s+([^\(]\S*))?(?:\s+\(([^\)]+)\))?$/m) {
        ($verbatim) = $$s =~ /^OS   (.+)$/m
            or confess "Can't parse OS line from:\n$$s";
   }
    
    my( @class );
    foreach my $line ($$s =~ /^OC   (.+)$/mg) {
        $line =~ s/[\.\s]+$//;  # Trim trailing dots and spaces
        push(@class, split(/;\s*/, $line));
    }
    confess "No classification lines in:\n$$s" unless @class;
    
    $line->species ( $species  );
    $line->genus   ( $genus    );
    $line->common  ( $common   );
    $line->verbatim( $verbatim );
    $line->classification(@class);
}

sub _compose {
    my( $line ) = @_;
    
    my $os = 'OS   ';
    
    if (my $genus = $line->genus()) {
        my $species = $line->species();
        my $common  = $line->common();
        $os .= $genus;
        $os .= " $species"  if $species;
        $os .= " ($common)" if $common;
    } else {
        my $verbatim = $line->verbatim();
        $os .= $verbatim if $verbatim;
    }
    $os .= "\n";
    
    my $class_string = join('; ', $line->classification()) . '.';
    return ($os, $line->wrap('OC   ', $class_string ));
}

###############################################################################

package Hum::EMBL::Line::OG;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );
@ISA = qw( Hum::EMBL::Line );


@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::OG->makeFieldAccessFuncs(qw( organelle ));

sub parse {
    my( $line, $s ) = @_;
    
    my( $organelle ) = $$s =~ /^OG   (.+)/
        or die "Can't parse OG line: $$s";
    $line->organelle( $organelle );
}

sub _compose {
    my( $line ) = @_;
    
    my $organelle = $line->organelle();
    return "OG   $organelle\n";
}

###############################################################################

package Hum::EMBL::Line::FH;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );
@ISA = qw( Hum::EMBL::Line );


sub new {
    my( $pkg ) = @_;
    return bless {}, $pkg;
}

sub store {
    my $pkg = shift;
    
    if (@_) {
        return $pkg->new();
    } else {
        confess "No data provided";
    }
}

sub compose {
    return "FH   Key             Location/Qualifiers\nFH\n";
}

###############################################################################

package Hum::EMBL::Line::FT;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );
use Hum::EMBL::Location;
use Hum::EMBL::Qualifier;

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::FT->makeFieldAccessFuncs(qw( key location ));
Hum::EMBL::Line::FT->makeListAccessFuncs(qw( qualifiers ));

sub newLocation {
    my( $line ) = @_;
    
    my $l = 'Hum::EMBL::Location'->new;
    $line->location( $l );
    return $l;
}

sub newQualifier {
    my( $line ) = @_;
    
    my $q = 'Hum::EMBL::Qualifier'->new;
    $line->addQualifier( $q );
    return $q;
}

sub addQualifier {
    my( $line, $qual ) = @_;

    push( @{$line->data->{'qualifiers'}}, $qual );
}
sub addQualifierStrings {
    my( $line, $name, $value ) = @_;
    
    my $q = 'Hum::EMBL::Qualifier'->new;
    $q->name($name);
    $q->value($value) if defined $value;
    
    $line->addQualifier($q);
}


sub parse {
    my( $feat, $s ) = @_;
    
    # Get the key and the first line of the location
    my( $key, $q ) = $$s =~ /^FT   (\S+)\s+(.+)$/m;
    
    my( @qual );
    while ($$s =~ m{^FT {19}(/?)(.+?)\s*$}mg) {
        my $end = $2;
    
        # A slash (/) marks the start of a new qualifier
        if ($1) {
            push(@qual, $q);
            $q = $end;
        } else {
            # Join lines with a space only if the
            # previous lines contain one
            $q .= ($q =~ /\s/) ? " $end" : $end;
        }
    }
    push( @qual, $q );
        
    # Location is first string on @qual
    my $loc_string = shift @qual;
    my $location = 'Hum::EMBL::Location'->new;
    $location->parse(\$loc_string);
    
    # Make a new qualifier object from each string
    for (my $i = 0; $i < @qual; $i++) {
        my $x = $qual[$i];
        
        # Fuse with next element of @qual if unbalanced quote
        # (This only happens if a line began with '/')
        while (($x =~ tr/"/"/) % 2) {
            my $extra = splice(@qual, $i + 1, 1) or confess "Unbalanced quote in:\n'$$s'";
            $x .= ($x =~ /\s/) ? " /$extra" : "/$extra";
        }
        
        my $n = 'Hum::EMBL::Qualifier'->new;
        $n->parse(\$x);
        $qual[$i] = $n;
    }
    
    # Store the parsed data
    $feat->key       ($key     );
    $feat->location  ($location);
    $feat->qualifiers(@qual    );
}

sub store {
    my $pkg = shift;
    
    my( @features );
    my $string = shift;
    foreach (@_) {
        if (/FT   \S/) {
            my $feat = $pkg->new();
            $feat->string( $string );
            push( @features, $feat );
            $string = $_;
        } else {
            $string .= $_;
        }
    }
    my $last = $pkg->new();
    $last->string( $string );
    return( @features, $last );    
}

sub _compose {
    my( $feat ) = @_;
    
    my $loc = $feat->location;
    
    my $head = 'FT   '. $feat->key;
    $head .= ' ' x (21 - length($head));
    $head .= $loc->compose;
    
    my( @qual );
    foreach my $q ($loc->location_qualifiers, $feat->qualifiers) {
        push( @qual, $q->compose );
    }
    return ($head, @qual);
}

###############################################################################

package Hum::EMBL::Line::Sequence;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );
use Hum::EMBL::Utils;

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::Sequence->makeFieldAccessFuncs(qw( seq ));

sub parse {
    my( $line, $s ) = @_;
    
    $$s =~ s/^SQ.+$//m;
    $$s =~ s/[\s\d]+//g;
    
    $line->seq($$s);
}

sub embl_checksum {
    my( $line ) = @_;
    
    my $seq = $line->seq;
    return Hum::EMBL::Utils::crc32(\$seq);
}

{
    my $nuc = 60;               # Number of nucleotides per line
    my $whole_pat = 'a10' x 6;  # Pattern for unpacking a whole line
    my $out_pat   = 'A11' x 6;  # Pattern for packing a line

    sub _compose {
        my( $line ) = @_;

        my $seq = $line->seq();
        my $length = length($seq);
        confess "Sequence length '$length' too long for EMBL format" if length($length) > 9;

        # Count the number of each nucleotide in the sequence
        my $a_count = $seq =~ tr/a/a/;
        my $c_count = $seq =~ tr/c/c/;
        my $g_count = $seq =~ tr/g/g/;
        my $t_count = $seq =~ tr/t/t/;
        my $o_count = $length - ($a_count + $c_count + $g_count + $t_count);

        # Make the first line
        my $embl = "SQ   Sequence $length BP; $a_count A; $c_count C; $g_count G; $t_count T; $o_count other;\n";
        
        # Calculate the number of nucleotides which fit on whole lines
        my $whole = int($length / $nuc) * $nuc;
        
        # Format the whole lines
        my( $i );
        for ($i = 0; $i < $whole; $i += $nuc) {
            my $blocks = pack $out_pat,
                         unpack $whole_pat,
                         substr($seq, $i, $nuc);
            $embl .= sprintf "     $blocks%9d\n", $i + $nuc;
        }
        
        # Format the last line
        if (my $last = substr($seq, $i)) {
            my $last_len = length($last);
            my $last_pat = 'a10' x int($last_len / 10) .'a'. $last_len % 10;
            my $blocks = pack $out_pat,
                         unpack $last_pat, $last;
            $embl .= sprintf "     $blocks%9d\n", $length;
        }
        
        # Return as a single string
        return $embl;
    }
}

###############################################################################

package Hum::EMBL::Line::End;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );
@ISA = qw( Hum::EMBL::Line );


sub new {
    my( $pkg ) = @_;
    return bless {}, $pkg;
}

sub store {
    my $pkg = shift;
    
    if (@_) {
        return $pkg->new();
    } else {
        confess "No data provided";
    }
}

sub compose {
    return "//\n";
}

###############################################################################

package Hum::EMBL::Line::CO;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );

@ISA = qw( Hum::EMBL::Line );
Hum::EMBL::Line::CO->makeListAccessFuncs( 'list' );

sub parse {
    my( $line, $s ) = @_;
    
    my @lines = $$s =~ /^CO   (.+)$/mg;
    $line->list(@lines);
}

sub text {
    my( $line, $text ) = @_;
    
    if (defined $text) {
        $line->list($text);
    }
    return join ' ', $line->list;
}

sub assembly_elements {
	my ($line) = @_;
	
	my @element_hashes;
	my $assembly_string = $line->text;
	$assembly_string =~ s/\s//g;
	if($assembly_string =~ /^join\(/) {
		$assembly_string =~ s/^join\(//;
		$assembly_string =~ s/\)$//;
		my @assembly_elements = split(/,/, $assembly_string);
		foreach my $assembly_element (@assembly_elements) {
			my %element_hash = (
				orientation			=> 1,
				type				=> 'clone',
			);
			if($assembly_element =~ /^complement\(/) {
				$element_hash{orientation} = -1;
				$assembly_element =~ s/^complement\(//;
				$assembly_element =~ s/\)$//;
			}
			if($assembly_element =~ /^gap\((\d+)\)/) {
				$element_hash{type} = 'gap';
				$element_hash{length} = $1;
			}
			elsif($assembly_element =~ /^(.*):(\d+)\.\.(\d+)$/) {
				$element_hash{name} = $1;
				$element_hash{start} = $2;
				$element_hash{end} = $3;
				$element_hash{length} = $element_hash{end} - $element_hash{start} + 1;
			}
			else {
				$element_hash{type} = 'unknown';
			}
			push(@element_hashes, \%element_hash);
		}
	}
	
	return(@element_hashes);
}

sub _compose {
    my( $line ) = @_;
    
    my( @compose );
    foreach my $txt ($line->list()) {
        push( @compose, $line->wrap('CO   ', $txt) );
    }
    return @compose;
}

1;

