
package Hum::EMBL;

use strict;
use Carp;

sub new {
    my $pkg = shift;
    
    confess "Odd number of agruments" if @_ % 2;
    
    if (@_) {
        my %handler = @_;
        return bless \%handler, $pkg;
    } else {
        return $pkg->defaultHandler;
    }
}

=pod

     ID - identification             (begins each entry; 1 per entry)
     AC - accession number           (>=1 per entry)
     SV - new sequence identifier    (>=1 per entry)
     NI - old sequence identifier    (>=1 per entry)
     DT - date                       (2 per entry)
     DE - description                (>=1 per entry)
     KW - keyword                    (>=1 per entry)
     OS - organism species           (>=1 per entry)
     OC - organism classification    (>=1 per entry)
     OG - organelle                  (0 or 1 per entry)
     RN - reference number           (>=1 per entry)
     RC - reference comment          (>=0 per entry)
     RP - reference positions        (>=1 per entry)
     RX - reference cross-reference  (>=0 per entry)
     RA - reference author(s)        (>=1 per entry)
     RT - reference title            (>=1 per entry)
     RL - reference location         (>=1 per entry)
     DR - database cross-reference   (>=0 per entry)
     FH - feature table header       (0 or 2 per entry)
     FT - feature table data         (>=0 per entry)
     CC - comments or notes          (>=0 per entry)
     XX - spacer line                (many per entry)
     SQ - sequence header            (1 per entry)
     bb - (blanks) sequence data     (>=1 per entry)
     // - termination line           (ends each entry; 1 per entry)

=cut

sub defaultHandler {
    my( $pkg ) = @_;
    
    return bless {

             ID => 'Hum::EMBL::ID',
             AC => 'Hum::EMBL::AC',
             SV => 'Hum::EMBL::SV',
             NI => 'Hum::EMBL::NI',
             DT => 'Hum::EMBL::DT',
             DE => 'Hum::EMBL::DE',
             KW => 'Hum::EMBL::KW',
             OS => 'Hum::EMBL::Organism',
             OC => 'Hum::EMBL::Organism',
             OG => 'Hum::EMBL::OG',
             RN => 'Hum::EMBL::Reference',
             RC => 'Hum::EMBL::Reference',
             RP => 'Hum::EMBL::Reference',
             RX => 'Hum::EMBL::Reference',
             RA => 'Hum::EMBL::Reference',
             RT => 'Hum::EMBL::Reference',
             RL => 'Hum::EMBL::Reference',
             DR => 'Hum::EMBL::DR',
             FH => 'Hum::EMBL::FeatureTable',
             FT => 'Hum::EMBL::FeatureTable',
             CC => 'Hum::EMBL::CC',
             XX => 'Hum::EMBL::XX',
             SQ => 'Hum::EMBL::Sequence',
           '  ' => 'Hum::EMBL::Sequence',
           '//' => 'Hum::EMBL::End',

    }, $pkg;
}

sub class {
    my( $handler, $prefix ) = @_;
    
    return $handler->{$prefix};
}

sub parse {
    my( $handler, $fh ) = @_;
    
    my( $current, @group, @obj );
    while (<$fh>) {
    
        # Get prefix and trim whitespace from the right
        my ($prefix) = /^(.{2,5})/;
        $prefix =~ s/(..+?)\s+$/$1/;
        
        # This ignores lines which aren't registered in the handler
        if (my $class = $handler->class( $prefix )) {
                
            $current ||= $class; # Needed for first line
            
            if ($current eq $class) {
                # Add to the group if belongs to same class
                push( @group, $_ );
            } else {
                # Make new line object(s) if current line belongs to a
                # different class, and add to the list of objects.
                my @line = $current->store(@group);
                warn $@ if $@;
                push( @obj, @line ) if @line;
                
                # Set $current to new class, and save line
                # in @group
                $current = $class;
                @group = ($_);
            }
        }
        
        # Break at end of entries
        last if $prefix eq '//';
    }

    # Store the last line group
    if (@group) {    
        my @last = $current->store(@group);
        push( @obj, @last ) if @last;
    }
    
    # Return an new Entry object if we've got Line objects
    if (@obj) {
        my $entry = Hum::EMBL::Entry->new();
        $entry->handler( $handler );
        $entry->lines( @obj );
        return $entry;
    } else {
        return;
    }
}

###############################################################################

package Hum::EMBL::Entry;

use strict;
use Carp;

sub compose {
    my( $entry ) = @_;
    
    my( @formatted );
    foreach my $line ($entry->lines()) {
        push( @formatted, $line->toString() );
    }
    return @formatted;
}


sub new {
    my( $pkg ) = @_;
    
    my $entry = bless {
        _handler => undef,
        _lines    => [],
    }, $pkg;
}

sub lines {
    my( $entry, @lines ) = @_;
    
    if (@lines) {
        foreach (@lines) { $_->entry($entry); }
        $entry->{'_lines'} = [ @lines ];
    } else {
        return @{$entry->{'_lines'}};
    }
}

sub handler {
    my( $entry, $handler ) = @_;
    
    if ($handler) {
        my $entry_pack = ref($entry);

        # Generate access methods for each line type package,
        # giving them the same name as the package.
        my %packages = map {$_, 1} values %$handler;
        foreach my $class (keys %packages) {
            my ($name) = $class =~ /([^:]+)$/;
            my $func = "${entry_pack}::$name";
            
            # Don't redefine existing subroutines
            ### IS THIS THE CORRECT BEHAVIOUR? ###
            unless (defined( &$func )) {
                no strict 'refs';
                *$func = sub {
                    my( $entry ) = @_;

                    my @lines = grep { ref($_) eq $class } $entry->lines()
                        or confess "No line types from '$class' class in entry";

                    if (wantarray) {
                        return @lines;
                    } else {
                        return $lines[0];
                    }
                }
            }
        }
    
        $entry->{'_handler'} = $handler;
    } else {
        return $entry->{'_handler'};
    }
}

###############################################################################

package Hum::EMBL::Line;

use strict;
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

sub compose {
    my( $line ) = @_;
    
    my $pkg = ref($line);
    confess "compose method not implemented in package '$pkg'";
}

sub makeFieldAccessFuncs {
    my( $pkg, @names ) = @_;
    
    foreach my $field (@names) {
        my $func = "$pkg\:\:$field";
    
        no strict 'refs';
        *$func = sub {
            my( $line, $data ) = @_;

            if ($data) {
                $line->data->{$field} = $data;
            } else {
                return $line->data->{$field};
            }
        }
    }
}

sub entry {
    my( $line, $entry ) = @_;
    
    if ($entry) {
        $line->{'_entry'} = $entry;
    } else {
        return $line->{'_entry'};
    }
}

sub string {
    my $line = shift;
    
    if (@_) {
        $line->{'_data'} = {};
        $line->{'_string'} = join '', @_;
    } else {
        return $line->{'_string'};
    }
}

sub pullString {
    my( $line ) = @_;
    
    my $string = $line->{'_string'};
    $line->{'_string'} = undef;
    return $string;
}

sub toString {
    my( $line ) = @_;
    
    if (my $string = $line->string()) {
        return $string;
    } else {
        return $line->compose();
    }
}

sub data {
    my( $line ) = @_;
    
    $line->parse() if $line->{'_string'};
    
    return $line->{'_data'};
}

sub list {
    my( $line, @list ) = @_;
    
    if (@list) {
        $line->data->{'list'} = [@list];
    } else {
        return @{$line->data->{'list'}};
    }
}

sub field {
    my( $line, $field, $data ) = @_;
    
    if ($data) {
        $line->data->{$field} = $data;
    } else {
        return $line->data->{$field};
    }
}

sub wrap {
    my( $line, $prefix, $text ) = @_;

    my $margin = $line->wrapMargin() - 1;
    
    # Pad prefix to 5 characters
    $prefix = $prefix . ( ' ' x (5 - length($prefix)) );
    
    my( @lines );
    while ($text =~ /(.{0,$margin}\S)(\s+|$)/g) {
        push( @lines, $prefix . $1 . "\n" );
    }
    
    return @lines;
}

sub wrapMargin {
    my( $line, $margin ) = @_;
    
    if ($margin) {
        $line->{'_wrap_margin'} = $margin;
    } else {
        return $line->{'_wrap_margin'} || 74;
    }
}

###############################################################################

package Hum::EMBL::CC;

use strict;
use Carp;
use vars qw( @ISA );
@ISA = qw( Hum::EMBL::Line );

sub parse {
    my( $line ) = @_;
    
    my $string = $line->pullString();
    my @lines = $string =~ /^CC   (.+)$/mg;
    my $text = join ' ', @lines;
    $line->list($text);
}

sub compose {
    my( $line ) = @_;
    
    my( @formatted );
    foreach my $txt ($line->list()) {
        push( @formatted, $line->wrap('CC', $txt) );
    }
    return @formatted;
}

###############################################################################

package Hum::EMBL::ID;

use strict;
use Carp;
use vars qw( @ISA );

BEGIN {
    @ISA = qw( Hum::EMBL::Line );
    Hum::EMBL::ID->makeFieldAccessFuncs(qw(
                                           entryname
                                           dataclass
                                           molecule
                                           division
                                           seqlength
                                           ));
}

sub parse {
    my( $line ) = @_;
    
    my $string = $line->pullString();
    my( $entryname, $dataclass, $molecule, $division, $length ) =
        $string =~ /^ID   (\S+)\s+(\S+);\s+(\S+);\s+(\S+);\s+(\d+)/
        or confess( "Can't parse ID line: $string" );
    
    $line->entryname( $entryname );
    $line->dataclass( $dataclass );
    $line->molecule ( $molecule  );
    $line->division ( $division  );
    $line->seqlength( $length    );
}

sub compose {
    my( $line ) = @_;
    
    my $entryname = $line->entryname();
    my $dataclass = $line->dataclass();
    my $molecule  = $line->molecule ();
    my $division  = $line->division ();
    my $length    = $line->seqlength();
    
    return "ID   $entryname  $dataclass; $molecule; $division; $length BP.\n";
}

###############################################################################

package Hum::EMBL::AC;

use strict;
use Carp;
use vars qw( @ISA );
@ISA = qw( Hum::EMBL::Line );

sub parse {
    my( $line ) = @_;
    
    my $string = $line->pullString();
    my @lines = $string =~ /^AC   (.+)$/mg;
    my( @ac );
    foreach (@lines) {
        push( @ac, split /;\s*/ );
    }
    $line->list(@ac);
}

sub primary {
    my( $line, $prim ) = @_;
    
    my @ac = $line->list();
    if ($prim) {
        $ac[0] = $prim;
        $line->list( @ac );
    } else {
        return $ac[0];
    }
}

sub secondaries {
    my( $line, @secs ) = @_;
    
    my @ac = $line->list();
    if (@secs) {
        $line->list( $ac[0], @secs );
    } else {
        return @ac[1..$#ac];
    }
}

sub compose {
    my( $line ) = @_;
    
    my $ac = join(' ', map "$_;", $line->list());
    
    return $line->wrap('AC', $ac);
}

###############################################################################

package Hum::EMBL::KW;

use strict;
use Carp;
use vars qw( @ISA );
@ISA = qw( Hum::EMBL::Line );

sub parse {
    my( $line ) = @_;
    
    my $string = $line->pullString();
    my @lines = $string =~ /^KW   (.+)$/mg;
    my( @kw );
    foreach (@lines) {
        push( @kw, split /;\s*/ );
    }
    # Remove full-stop from the last word
    $kw[$#kw] =~ s/\.$//;
    $line->list(@kw);
}

sub compose {
    my( $line ) = @_;
    
    my $kw = join('; ', $line->list()) . '.';
    
    return $line->wrap('KW', $kw);
}

###############################################################################

package Hum::EMBL::DT;

use strict;
use Carp;
use Time::Local qw( timelocal );
use vars qw( @ISA );

BEGIN {

    @ISA = qw( Hum::EMBL::Line );
    Hum::EMBL::ID->makeFieldAccessFuncs(qw(
                                           createdDate
                                           createdRelease
                                           date
                                           release
                                           version
                                           ));

    my @months = qw( JAN FEB MAR APR MAY JUN
                     JUL AUG SEP OCT NOV DEC );
    my @mDay = ('00'..'31');
    my( %months );
    {
        my $i = 0;
        %months = map { $_, $i++ } @months;
    }
    
    # Convert EMBL date to unix time int
    sub dateEMBL {
        my( $embl ) = @_;
        my( $mday, $mon, $year ) = split /-/, $embl;
        $year -= 1900;
        $mon = $months{ $mon };
        return timelocal( 0, 0, 0, $mday, $mon, $year );
    }

    # Convert unix time int to EMBL date
    sub EMBLdate {
        my $time = shift || time;
        my ($sec, $min, $hour, $mday, $mon, $year) = localtime($time);
        $year += 1900;
        $mon = $months[$mon];
        $mday = $mDay[$mday];
        return "$mday-$mon-$year";
    }
}

sub parse {
    my( $line ) = @_;
    
    my $string = $line->pullString();
    my @lines = split /\n/, $string;
    
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

sub compose {
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
    return "DT   $createdDate (Rel. $createdRelease, Created)\n" .
           "DT   $date (Rel. $release, Last updated, Version $version)\n";
}

###############################################################################

package Hum::EMBL::DE;

use strict;
use Carp;
use vars qw( @ISA );
@ISA = qw( Hum::EMBL::Line );

sub parse {
    my( $line ) = @_;
    
    my $string = $line->pullString();
    my @lines = $string =~ /^DE   (.+)$/mg;
    my $text = join ' ', @lines;
    $line->list($text);
}

sub compose {
    my( $line ) = @_;
    
    my( @formatted );
    foreach my $txt ($line->list()) {
        push( @formatted, $line->wrap('DE', $txt) );
    }
    return @formatted;
}

###############################################################################

package Hum::EMBL::XX;

use strict;
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

package Hum::EMBL::SV;

use strict;
use Carp;
use vars qw( @ISA );

BEGIN {
    @ISA = qw( Hum::EMBL::Line );
    Hum::EMBL::ID->makeFieldAccessFuncs(qw( version ));
}


sub new {
    my( $pkg ) = @_;
    return bless {}, $pkg;
}

sub parse {
    my( $line ) = @_;
    
    my $string = $line->pullString();
    my( $version ) = $string =~ /^SV   \S+\.(\d+)/
        or die "Can't parse SV line: $string";
    $line->version( $version );
}

sub compose {
    my( $line ) = @_;
    
    ### This will blow up if there aren't any entries in the AC class ###
    my $ac = $line->entry->AC->primary();
    
    my $version = $line->version();
    return "SV   $ac.$version\n";
}

###############################################################################

package Hum::EMBL::NI;

use strict;
use Carp;
use vars qw( @ISA );

BEGIN {
    @ISA = qw( Hum::EMBL::Line );
    Hum::EMBL::ID->makeFieldAccessFuncs(qw( nucleotide ));
}


sub new {
    my( $pkg ) = @_;
    return bless {}, $pkg;
}

sub parse {
    my( $line ) = @_;
    
    my $string = $line->pullString();
    my( $version ) = $string =~ /^NI   (\S+)/
        or die "Can't parse NI line: $string";
    $line->nucleotide( $version );
}

sub compose {
    my( $line ) = @_;
    
    my $nuc = $line->nucleotide();
    return "NI   $nuc\n";
}

###############################################################################

package Hum::EMBL::End;

use strict;
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

package Hum::EMBL::Sequence;

use strict;
use Carp;
use vars qw( @ISA );
@ISA = qw( Hum::EMBL::Line );


###############################################################################

package Hum::EMBL::Reference;

use strict;
use Carp;
use vars qw( @ISA );
@ISA = qw( Hum::EMBL::Line );


###############################################################################

package Hum::EMBL::DR;

use strict;
use Carp;
use vars qw( @ISA );
@ISA = qw( Hum::EMBL::Line );


###############################################################################

package Hum::EMBL::Organism;

use strict;
use Carp;
use vars qw( @ISA );
@ISA = qw( Hum::EMBL::Line );


###############################################################################

package Hum::EMBL::OG;

use strict;
use Carp;
use vars qw( @ISA );
@ISA = qw( Hum::EMBL::Line );


###############################################################################

package Hum::EMBL::FeatureTable;

use strict;
use Carp;
use vars qw( @ISA );
@ISA = qw( Hum::EMBL::Line );



1;
