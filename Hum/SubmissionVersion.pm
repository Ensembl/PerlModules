
package Hum::SubmissionVersion;

use strict;
use Hum::Submission qw{ prepare_statement };

sub check_version{
    # check if schema has changed
    my $sth = prepare_statement(qq{
	SELECT meta_name, meta_value
	  FROM meta
        });
    
    # This is a bit "belt and braces".  It will work
    # whether {RaiseError => 1} is set or not
    my( %meta );
    eval{
        $sth->execute;
	while (my ($tag, $value) = $sth->fetchrow) {
	    $meta{$tag}=$value;
	}
    };
    if (!$@) {

	# check against values we are interested in

	# check schema (fatal if different)
	my $rsv=$meta{'schema_version'};
	my $lsv='0.11';
	if($rsv ne $lsv){
	    print<<ENDOFTEXT;

FATAL: schema on vegadb databases has been updated ($rsv) and your client
software is incompatible ($lsv).

You need to update your client software.  A new tgz file can be found at
http://www.sanger.ac.uk/Software/vegadb/

If this message is unexpected please email otter\@sanger.ac.uk

ENDOFTEXT

            return 0;
	}

	# check editor (warning if different)
	my $rev=$meta{'editor_version'};
	my $lev='0.11';
	if($rev ne $lev){
	    print<<ENDOFTEXT;

INFO==INFO==INFO==INFO==INFO

Software to access vegadb database has been updated ($rev).  You can
continue to edit using your existing client ($lev), but you may
benefit from new functionality/bug fixes from the newer version.

The new tgz file can be found at
http://www.sanger.ac.uk/Software/vegadb/

A message reporting what has been changed should have been emailed to
you on the otter\@sanger.ac.uk email list

INFO==INFO==INFO==INFO==INFO

ENDOFTEXT

            return 1;
	}

	# check schema (fatal if different)
	my $ea=$meta{'enable_access'};
	my $ea_expected='RW';
	if($ea ne $ea_expected){
	    print<<ENDOFTEXT;

FATAL: access to vegadb databases are currently blocked for maintainance

See messages on the otter\@sanger.ac.uk email list for more information.

ENDOFTEXT

            return 0;
	}

	#print "INFO check_version passed\n";
        return 1;
    } else {
        # no meta table - for now this is acceptable (backwards compatible)
	#print "WARN got no meta table\n";
	return 1;
    }

}

1;
