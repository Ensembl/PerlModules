
package Hum::SubmissionConf;

use strict;

sub localisation{
     # allow sanger people to view what is on vegadb if 'VIEW_VEGADB' set
    my($host,$port);
    if($ENV{'VIEW_VEGADB'}){
	$host   = 'vegadb.sanger.ac.uk';
	$port   = 3306;
    }else{
	$host   = 'humsrv1';
	$port   = 3399;
    }
    return($host,$port);
}

1;
