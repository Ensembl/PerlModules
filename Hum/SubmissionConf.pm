
package Hum::SubmissionConf;

use strict;

sub localisation{
    # allow sanger people to view what is on vegadb if 'VIEW_VEGADB' set
    my( $host, $port, $dbname );
    if($ENV{'VIEW_VEGADB'}){
	    $host   = 'vegadb.sanger.ac.uk';
	    $port   = 3306;
	    $dbname = 'submissions';
    }else{
	    $host   = 'humsrv1';
	    $port   = 3399;
	    $dbname = 'submissions';
    }
    return($host, $port, $dbname);
}

1;
