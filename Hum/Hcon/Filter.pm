
package Hum::Hcon::Filter;

use strict;
use Carp;
use vars qw( %BUILTIN_TEST @EXPORT_OK );
use Exporter;

use AceParse qw( aceQuote );

@EXPORT_OK = qw( makeTester );

# Some hard-coded tests for the common acedb data types
%BUILTIN_TEST = (
		 # All acedb integers are positive?
		 INT => sub {
		     my $thing = shift;
		     if ($thing =~ /^\d+$/) {
			 return $thing;
		     } else {
			 return;
		     }
		 },

		 FLOAT => sub {
		     my $thing = shift;
		     if ($thing =~ /^[+-]?\d+\.?\d*$/) {
			 return $thing;
		     } else {
			 return;
		     }
		 },

		 # Could have a better test for dates?
		 DATE => sub {
		     my $thing = shift;
		     if ($thing =~ /^(19|20)\d{2}-\d{1,2}-\d{1,2}$/) {
			 return $thing;
		     } else {
			 return;
		     }
		 },

		 # Text fields tested for at least one non-space character
		 TEXT => sub {
		     my $thing = shift;
		     if ($thing =~ /\S/) {
			 return $thing;
		     } else {
			 return;
		     }
		 }
		 );
# Provides access to %BUILTIN_TEST
sub BUILTIN_TEST {
    if (wantarray) {
	return %BUILTIN_TEST;
    } else {
	return \%BUILTIN_TEST;
    }
}


sub makeTester {
    my $pattern = shift;
    return sub {
	my $thing = shift;
	if ($thing =~ /$pattern/) {
	    return $thing;
	} else {
	    return;
	}
    }
}

# Create a new test object, optionally supplying an array of
# arrays, each of which is of the format:
#     [ tag, sub, sub, sub, sub ]
# for initiallising line assays
sub new {
    my $pkg = shift;

    my $test = bless {}, $pkg;

    if (@_) {
	foreach my $A (@_) {
	    if (ref($A) eq 'ARRAY') {
		my $tag = shift @$A;
		$test->assay( $tag, $A );
	    } else {
		confess "Arguments to new must be refs to ARRAY";
	    }
	}
    }
    
    return $test;
}

# assay adds tests to, or returns them from, the test object
sub assay {
    my $test = shift;
    my $tag = shift;

    # Make sure that we're case insensitive
    $tag = lc $tag;

    my $pkg = ref($test);

    if (@_) {
	# $A is a ref to an array of test subs, or
	# strings which match a key in %BUILTIN_TEST
	my $A = shift;

	# Check each element of the array, replacing
	# any scalars with the corresponding sub from
	# %BUILTIN_TEST
	foreach my $sub (@$A) {
	    my $ref = ref($sub);
	    unless ($ref) {
		if (my $code = $pkg->BUILTIN_TEST->{$sub}) {
		    $sub = $code;
		}
		elsif ($sub ne 'JOIN') {
		    confess "No such test: $sub";
		}
	    } elsif ($ref ne 'CODE') {
		confess "Tests supplied to assay must be refs to CODE, not $ref";
	    }
	}
	# Add this array to the test object
	$test->{$tag} = $A;
    } else {
	# Return a ref to an array of subs
	return $test->{$tag};
    }
}

sub validate {
    my $filter = shift;
    my $row = shift;

    # Get copy of data, so we don't alter it in main object
    my @data = @$row;

    my $join;
    my $i = 0;
    while ( $i < @data ) {
	my( $subs );

	# Get the assay for this tag
	if ($subs = $filter->assay($data[$i])) {
	    $i++; # Move pointer to next data element
	}
	elsif ($join) {
	    # We're inside a registered line type, but this tag
	    # isn't registered
	    warn 'Rejecting: ', aceQuote( @$row );
	    return;
	}
	else {
	    # Unregistered line type, so reject silently
	    return;
	}
	
	# Apply each test in this assay
	foreach my $sub (@$subs) {

	    # "JOIN" flags when we need a new assay for this tag
	    if ($sub eq 'JOIN') {
		$join = 1;
		last;
	    }

	    # Apply test to data element
	    $data[$i] = &{$sub}( $data[$i] );

	    # Check value returned
	    if (defined $data[$i]) {
		# Got data, or an explicit error
		if ($data[$i] eq '__FATAL__') {
		    die 'FATAL ERROR IN DATA: ', aceQuote( @$row );
		    return;
		} 
		elsif ($data[$i] eq '__SILENT__') {
		    return;
		}
	    } else {
		# Got an undefined value
		warn 'Rejecting: ', aceQuote( @$row );
		return;
	    }
	    $i++; # Move pointer to next data element
	}
    }

    # Last test increments pointer off end of array, so test for
    # equality with array length here
    if ($i == @data) {
	return @data;
    } else {
	warn 'Rejecting [bad count] : ', aceQuote( @$row );
    }
}

1;
