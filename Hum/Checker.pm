#!/usr/local/bin/perl -w

=pod 

=head1 NAME

Hum::Checker

=head1 SYNOPSIS

my $host = 'humsrv1';
my $port = 410000;
my $db = Spangle::Ace::connect( $host, $port )
    or die "Can't connect to '$host' on port '$port' : ", Ace->error;
my @clonelist = ('91K3A' , '91K3B', 'bA192P3', 'Em:AB014081', 'Em:AC006165');

my $checkobj = Hum::Checker->new ($db, @clonelist);

=head1 DESCRIPTION
An object which takes a handle to an acedb database and a list of clones.
Various checks can then be run on the clones. The results are written to two
output handles set through output() and ace_output().

=head1 PUBLIC METHODS
new()
cloneidlist(@clonelist)
checkclones(@checks)
output($filehandle)
ace_output($filehandle)
 

=head1 CONTACT
M.A.Qureshi

=head1 APPENDIX

=cut

use strict;
package Hum::Checker;
use vars qw(@ISA);

use Bio::Root::Object;
use Spangle::Clone;
use Hum::Tracking;
use Spangle::Ace; # is this needed? 
use Data::Dumper;
use Hum::Tracking qw( ref_from_query );
use Bio::SeqIO;
use Bio::PrimarySeq;

@ISA = qw(Bio::Root::Object);

sub _initialize {
    my ($self,@args) = @_;
    my $make = $self->SUPER::_initialize;            
    
    my( $dbhandle, @clones ) = @args;
    $self->throw("Database handle required") unless ($dbhandle) ;
    
    $self->{'db'} = undef;
    $self->{'_cloneidList'} = [];       # A list of clone IDs
    $self->{'_output'} =[];             # To store results of checks
    $self->{'_aceedit'}=[];             # To store any ace corrections
    $self->{'_checklist'} =[];          # Methods to be run on object
    $self->{'_clone'} = undef;          # A stored clone object
    $self->{'_outfile'} = undef;        # Filehandle for output
    $self->{'_aceoutfile'} = undef;     # Filehandle for ace output 

    #set db handle
    $self->db($dbhandle) if ($dbhandle);
    #fill clone id list if provided
    $self->cloneidlist(@clones) if @clones;            
    return $self; # success - we hope!
}

#get/set method for database handle
sub db {
    my ($self, $dbhandle, @args) = @_;
    if ($dbhandle)
        {$self->{'db'} = $dbhandle;}
        
    return $self->{'db'};
}

=head2 cloneidlist

    Title   :   cloneidlist
    Usage   :   $self->cloneidlist(@clones)
    Function:   Get/set method for list of clone ids
    Returns :   list of clonenames
    Args    :   list of clonenames

=cut
#get/set method for list of clone id
sub cloneidlist {
    my ($self, @clones) =@_;

    if (@clones) 
        {
            @{$self->{'_cloneidlist'}} = @clones;
        }
    return @{$self->{'_cloneidlist'}};
}

#get/set method for list of checks
sub checklist {
    my ($self, @checks) =@_;
    if (@checks)
        { @{$self->{'_checklist'}} = @checks; }

    return @{$self->{'_checklist'}};
}

{ #start block for _translatecheck
    #translation from argument to method name hash
    my %check_to_method = ( "acc"   , "_accession_check",
                            "anal"  , "_analysis_directory_check",
                            "chrom" , "_chromosome_check",
                            "seq"   , "_sequence_check",
                            "mask"  , "_masked_check",
                            "proj"  , "_project_check",
                            "seqby" , "_seq_by_check",
                            "clone" , "_clonename_check",
                            "subseq", "_subsequence_check",
                            "link"  , "_link_check"                 
                            );
    #translates arguments into function names
    sub _translatecheck {
        my ($self, $check) = @_;

        return $check_to_method {$check};
    }
}

=head2 checkclones

    Title   :   checkclones
    Usage   :   $self->checkclones(@checks)
    Function:   Runs checks on list of clones already provided
    Returns :   none
    Args    :   "acc"   # Runs EMBL accession number and id check
                "anal"  # Checks if analysis directory and tag exist 
                "chrom" # Checks if chromosome tag is correct
                "seq"   # Checks if the length tag and file are the same value
                "mask"  # Checks the masked and .seq file are the same length
                "proj"  # Checks the project tag is set correctly
                "seqby" # Checks sequenced_by tag is correctly set
                "clone" # Checks that the clonename is GULL + suffix
                "subseq"# Checks that subsequence lengths match object values
                "link"  # Checks that the subsequences of link objects match thelink tags

=cut
#main check method - takes list of checks to done
#precondition: cloneid must exist in humace    
sub checkclones {
    my ($self, @checks) = @_;
          
    $self->throw("filehandles must be provided through output() and ace_output")
                unless ($self->output() && $self->ace_output());
    #set check list
    if (@checks)
        {$self->checklist( @checks);}
    else 
        {$self->throw("Check list required");}
        
    #test list of clone ids is present
    $self->throw("List of clone IDs required") unless $self->cloneidlist();
    
    CLONE: foreach my $cloneid ($self->cloneidlist())
    {
        my $counter = 1;
        eval 
        {
           print "Processing $cloneid ...\n";
           $self->{_clone} = Spangle::Clone->new( $cloneid, $self->db);
           $self->throw("Clone object not created!") unless ($self->{_clone});
        };
        if ($@)
        {
            print "Failed to create $cloneid object. Retrying...\n"; 
            print "$@\n";
            $counter ++;
            if ($counter < 3)   #three tries and you're out
            {
                $self->add_output(" CLONE $cloneid not tested: FAILED TO LOAD");
                next CLONE;
            }
            redo; 
        }   
                                
        foreach my $check ($self->checklist())
        {
           my $method = $self->_translatecheck($check);
           $self->throw("Method not found") unless ($method);
           $self->$method();
        }       
    }                            
}

#############################
# Check functions 
#############################

#Precondition: correctly set project and suffix and sequenced_by tags
sub _accession_check {
    my ($self) = @_;
    my $embl = undef;    #flag for embl entry
     
    $self->add_output(" Accession and ID check");
    
    #exclude links
    if ($self->{_clone}->link())
    {
        $self->add_output(" ABORT: Check cannot run on LINK");
        return;
    }      
    #exclude not sanger clones
    my $seq_by = $self->{_clone}->sequenced_by();
    if ((!$seq_by) || ($seq_by !~ /(^sanger|^sc$)/i))
    {
        $self->add_output(" ABORT: not sequenced by sanger");
        return;
    }
    #get accession and embl id from gull using ace project number tag
    my $ace_suffix;
    my $ace_proj_name = $self->{_clone}->project_name();
    unless ($ace_proj_name)
    {
        $self->add_output(" FAIL: Can't find accession without project tag");
        return;
    }
    
    $ace_suffix = "NULL" unless $ace_suffix = $self->{_clone}->suffix();
 
    my $accession_query = "select accession
                           from finished_submission
                           where  projectname = '$ace_proj_name'
                           and suffix = '$ace_suffix'";
 
    my $id_query       = "select name
                          from finished_submission f, embl_submission e
                          where f.accession = e.accession
                          and projectname = '$ace_proj_name'
                          and suffix = '$ace_suffix'";
 
    if ($ace_suffix eq 'NULL')
    {
        substr ($accession_query, -15, 15) = "suffix is NULL";
        substr ($id_query, -15, 15) = "suffix is NULL"
    }
 
    my @arr_accession = @{ref_from_query($accession_query)};
    my @arr_id = @{ref_from_query($id_query)};
    #test return from queries 
    unless (@arr_accession == 1 && @arr_id == 1)
    {
        $self->add_output(" FAIL: non existent or non unique accession and/or id in Gull");
        return;
    }
    my ($gull_accession) = @{pop @{@arr_accession}};
    my ($gull_id) = @{pop @{@arr_id}};

    #1.check if the clone has a database tag
    my @db_name = $self->{_clone}->database();
    if (@db_name)
    {
        foreach my $entry (@db_name)    #loop through every entry
        {
            if ($entry =~ /^embl/i)     #2. check if entry contains EMBL
            {
                my $num_rows = $self->{_clone}->db_count_rows($entry);
                my $num_cols = $self->{_clone}->db_count_cols($entry);
                #3.check EMBL entry format
                if ($num_rows = 1 && $num_cols == 2)
                {
                    my $ace_accession = $self->{_clone}->embl_accession();
                    my $ace_id = $self->{_clone}->embl_id();
 
                    #4. Compare gull and sanger
                    if ($ace_accession eq $gull_accession
                                            && $ace_id eq $gull_id)
                    {
                        #numbers match: Passed check
                        $embl = "True";
                        $self->add_output (" PASS: Accession and ID check");
                        next;
                    }
                    #Gull and Ace acc or id number different (Failed 4.)
                    else
                    {$self->add_output (" FAIL: ace $ace_accession !=".
                    "gull $gull_accession and/or ace $ace_id != gull $gull_id");}
                }
                else    #EMBL entry in invalid format (Failed 3.)
                { $self->add_output (" FAIL: EMBL entry invalid format");}
            }
        }
        # if any of above tests failed write GULL accession and id to ace_output
        unless ($embl)
        {
            $self->add_output (" FAIL: EMBL database entry not found");
            $self->add_ace_reptag("DB_info Database \"EMBL\"",
                                         ("\"".$gull_id."\""),
                                         ("\"".$gull_accession."\""));
        }
    }
    else # No entries under DB.info tag (Failed 1.)
    {
        $self->add_output(" FAIL: No database entries found");
        $self->add_ace_reptag("DB_info Database \"EMBL\"",
                                         ("\"".$gull_id."\""),
                                         ("\"".$gull_accession."\""));
    }
}

#pre: correctly set sequenced by
sub _analysis_directory_check {
    my ($self) = @_;
    
    $self->add_output(" Analysis Directory check");
    
    #exclude links
    if ($self->{_clone}->link())
    {
        $self->add_output(" ABORT: Check cannot run on LINK");
        return;
    }
    #exclude not sanger clones
    my $seq_by = $self->{_clone}->sequenced_by();
    if ((!$seq_by) || ($seq_by !~ /(^sanger|^sc$)/i))
    {
        $self->add_output(" ABORT: not sequenced by sanger");
        return;
    }
    #get directory name - take first entry
    my $analysis_dir = $self->{_clone}->analysis_Directory();
 
    if ($analysis_dir)
    {
        #test for existence of directory
        if (-d $analysis_dir)
        {
            $self->add_output(" PASS: Analysis Directory Check");
        }
        else #directory doesn't exist
        {$self->add_output("FAIL: directory not found");}
    }
    else #directory tag doesn't exist in Humace
    {$self->add_output(" FAIL: directory tag not found");}  
}

#precondition: correctly set project and sequenced_by tags
sub _chromosome_check {
    my ($self) =@_;
    my $chr_check = undef;   #flag for sensible chromosome value
    my $sanger = undef;      #flag for sequenced by sanger
    
    $self->add_output(" Chromosome check");
    #exclude links
    if ($self->{_clone}->link())
    {
        $self->add_output(" ABORT: Check cannot run on LINK");
        return;
    }
    #exclude not sanger clones
    my $seq_by = $self->{_clone}->sequenced_by();
    if ((!$seq_by) || ($seq_by !~ /(^sanger|^sc$)/i))
    {
        $self->add_output(" ABORT: not sequenced by sanger");
        return;
    }
    
    # get the ace chromosome tag value
    my $chromosome = $self->{_clone}->chromosome();
    $chromosome = '' unless ($chromosome); #to prevent undef warning
    $chromosome =~ s/Chr_//i; #regex deletes Chr_ from chromosome value
    
    #query gull for matching chromosome number
    my $project_name = $self->{_clone}->project_name();
    unless ($project_name)
    {
        $self->add_output(" FAIL: Can't find chromosome without project tag");
        return;
    }
 
    my @arr_chromosome = @{ ref_from_query(qq(
                                select d.chromosome
                                from project p, clone_project cp,
                                clone c, chromosomedict d
                                where p.projectname = '$project_name'
                                and cp.projectname = p.projectname
                                and cp.clonename = c.clonename
                                and c.chromosome = d.ID_dict))};
    #test query result
    unless (@arr_chromosome == 1)
    {
        $self->add_output(" FAIL: non-existent or non-unique chromosome value in gull");
        return;
    }
    my ($gull_chromosome) =  @{pop @{@arr_chromosome}};
 
    if ($chromosome ne $gull_chromosome)
    {
        $self->add_output(" FAIL: $chromosome doesn't match $gull_chromosome");
        $self->add_ace_reptag ("Origin Chromosome",
                                ("\"Chr_".$gull_chromosome."\""));
    }
    else #chromosomes match
    { $self->add_output(" PASS: Chromosome Check");}
        
         
}
    
#precondition: Correctly set analysis directory and sequenced by   
sub _sequence_check {
    my ($self) =@_;
    $self->add_output(" Sequence check");
    
    #exclude links
    if ($self->{_clone}->link())
    {
        $self->add_output(" ABORT: Check cannot run on LINK");
        return;
    }
    #exclude not sanger clones
    my $seq_by = $self->{_clone}->sequenced_by();
    if ((!$seq_by) || ($seq_by !~ /(^sanger|^sc$)/i))
    {
        $self->add_output(" ABORT: not sequenced by sanger");
        return;
    }
    
    #get directory name - take first entry
    my $analysis_dir = $self->{_clone}->analysis_Directory();
    #get ace suffix
    my $ace_suffix = $self->{_clone}->suffix();
    $ace_suffix = '' unless ($ace_suffix);
    #get project tag and use it to get gull name
    my $ace_project = $self->{_clone}->project_name();
    unless ($ace_project)
    {
        $self->add_output(" FAIL: project tag required for sequence check"); 
        return;        
    }
    my @arr_name = @{ ref_from_query(qq(
                                     select clonename
                                     from clone_project
                                     where projectname = '$ace_project'))};
    unless (@arr_name == 1)
    {
        $self->add_output(" FAIL: non existent or non-unique project in Gull");
        return;
    }
    my ($gull_name) = @{pop @{@arr_name}}; 
    my $gull_fullname = $gull_name.$ace_suffix;
    
    #set the sequence name and path
    #my $seqfile = $analysis_dir.'/'.$self->{_clone}->id().'.seq';
    my $seqfile = $analysis_dir.'/'.$gull_fullname.'.seq';
    
    if (-e $seqfile) #check file exists
    {
        #get length from ace or set it to false
        my $ace_length = $self->{_clone}->seqlength();
        $ace_length = 0 unless ($ace_length);
        
        #load file into Bio::SeqIO object to check the size
        my $seqio = Bio::SeqIO->new(-file => $seqfile , '-format' => 'Fasta')
            or $self->throw("Can't create new Bio::SeqIO from $seqfile '$' : $!");
        my $seq = $seqio->next_seq();
        #get seq lengths from file
        my $seq_length = $seq->length();
 
        #compare ace and seq length
        if ($ace_length == $seq_length)
        {
            $self->add_output(" PASS: Sequence Check");
        }
        else
        {
            $self->add_output(" FAIL: ace $ace_length doesn't match $seq_length");
        }
    }
    else
    {$self->add_output(" FAIL: $seqfile not found");}
}

#pre: correctly set analysis directory
sub _masked_check {
    my ($self) = @_;
    $self->add_output(" Sequence mask check");
    
    #exclude links
    if ($self->{_clone}->link())
    {
        $self->add_output(" ABORT: Check cannot run on LINK");
        return;
    }
    #exclude not sanger clones
    my $seq_by = $self->{_clone}->sequenced_by();
    if ((!$seq_by) || ($seq_by !~ /(^sanger|^sc$)/i))
    {
        $self->add_output(" ABORT: not sequenced by sanger");
        return;
    }
  
    my $analysis_dir = $self->{_clone}->analysis_Directory();    
    #get ace suffix
    my $ace_suffix = $self->{_clone}->suffix();
    $ace_suffix = '' unless ($ace_suffix);
    #get project tag and use it to get gull name
    my $ace_project = $self->{_clone}->project_name();
    unless ($ace_project)
    {
        $self->add_output(" FAIL: project tag required for masked sequence check"); 
        return;        
    }
    my @arr_name = @{ ref_from_query(qq(
                                     select clonename
                                     from clone_project
                                     where projectname = '$ace_project'))};
    unless (@arr_name == 1)
    {
        $self->add_output(" FAIL: non existent or non-unique project in Gull");
        return;
    }
    my ($gull_name) = @{pop @{@arr_name}}; 
    my $gull_fullname = $gull_name.$ace_suffix;
    my $seqfile = $analysis_dir.'/'.$gull_fullname.'.seq';
    my $seqpfile = $analysis_dir.'/'.$gull_fullname.'.seq.p';
    
    if (-e $seqfile && -e $seqpfile)
    {
         my $seqio = Bio::SeqIO->new(-file => "<$seqfile" , '-format' => 'Fasta')
            or $self->throw("Can't create new Bio::SeqIO from $seqfile '$' : $!");
         my $seq = $seqio->next_seq();
         my $seqpio = Bio::SeqIO->new(-file => "<$seqpfile" , '-format' => 'Fasta')
            or $self->throw("Can't create new Bio::SeqIO from $seqpfile '$' : $!");
             #get seq lengths from files
         my $seqp = $seqpio->next_seq();
         my $seq_length = $seq->length();
         my $seqp_length = $seqp->length();
         if ($seq_length == $seqp_length)
         {$self->add_output(" PASS: Sequence Check");}
         else
         {$self->add_output(" FAIL: $seqfile doesn't match $seqpfile length");}
     }
     else
     {$self->add_output(" FAIL: $seqfile or $seqpfile doesn't exist");}
} 

#pre: correct sequenced_by and clonename
sub _project_check {
    my ($self) = @_;
    $self->add_output(" Project check");
    
    #exclude links
    if ($self->{_clone}->link())
    {
        $self->add_output(" ABORT: Check cannot run on LINK");
        return;
    }
    #exclude not sanger clones
    #my $seq_by = '' unless (my $seq_by = $self->{_clone}->sequenced_by());
    my $seq_by = $self->{_clone}->sequenced_by();   
    if ((!$seq_by) || ($seq_by !~ /(^sanger|^sc$)/i))
    {
        $self->add_output(" ABORT: not sequenced by sanger");
        return;
    }
    #get project tag
    my $ace_project = "" unless (my $ace_project = 
                                    $self->{_clone}->project_name());
    
    #remove any suffix from the clone name = clone->id
    my $clone_name = $self->{_clone}->id();
    #only a-f are suffixes
    $clone_name =~ s/[a-f]$//i;
    #extract gull projectname
    my @arr_project = @{ ref_from_query(qq(
                                    select projectname
                                    from clone_project
                                    where clonename = '$clone_name'))};
    unless (@arr_project == 1)
    {
        $self->add_output(" FAIL: non existent or non-unique chromosome in Gull");
        return;
    }
    my ($gull_project) = @{ pop @{@arr_project}};
    if ($ace_project eq $gull_project)
    {
        $self->add_output(" PASS: Project Check");
    }
    else
    {
        $self->add_output("  FAIL: ace $ace_project doesn't match $gull_project");
        $self->add_ace_reptag ("Project Project_name", ("\"".$gull_project."\""));
    }
}

#pre: correctly set project tag and suffix tag
sub _clonename_check {
    my ($self) = @_;
    $self->add_output(" Clone name check");
    
    #exclude links
    if ($self->{_clone}->link())
    {
        $self->add_output(" ABORT: Check cannot run on LINK");
        return;
    }
    #exclude not sanger clones
    my $seq_by = $self->{_clone}->sequenced_by();   
    if ((!$seq_by) || ($seq_by !~ /(^sanger|^sc$)/i))
    {
        $self->add_output(" ABORT: not sequenced by sanger");
        return;
    }
   
    #Get project_suffix and clonename in Ace
    my $ace_name = $self->{_clone}->id();
 
    my $ace_suffix = $self->{_clone}->suffix();
    $ace_suffix = '' unless ($ace_suffix);
 
    my $ace_project = $self->{_clone}->project_name();
    unless ($ace_project)
    {
        $self->add_output(" FAIL: project tag required for name check");
        return;
    }
    my @arr_name = @{ ref_from_query(qq(
                                     select clonename
                                     from clone_project
                                     where projectname = '$ace_project'))};
    unless (@arr_name == 1)
    {
        $self->add_output(" FAIL: non existent or non-unique project in Gull");
        return;
    }
    my ($gull_name) = @{pop @{@arr_name}};
 
    my $gull_fullname = $gull_name.$ace_suffix;
 
     if ($ace_name eq $gull_fullname)
     {
         $self->add_output (" PASS: Clone name Check");
     }
     else
     {
         $self->add_output(" FAIL: ace $ace_name doesn't match $gull_fullname");
         $self->add_ace_renobj ('Genomic Sequence', 
                                            ("\"".$ace_name."\""),
                                            ("\"".$gull_fullname."\""));
     }
}

#start block for _seq_by_check creates locally-scoped static variables
{
#valid sequenced_by values
    my %valid_lab = ( 'agct'            , 'ACGT at the University of Oklahoma',
                      'baylor'          , 'Baylor',
                      'berlin'          , 'Berlin University',
                      'cnrs'            , 'CNRS',
                      'csh'             , 'Cold Spring Harbor',
                      'columbia'        , 'Columbia',
                      'genome'          , 'Genome Therapautics Corp',
                      'gsc'             , 'GSC',
                      'icrf'            , 'ICRF',
                      'imm'             , 'IMM',
                      'jena'            , 'Jena',
                      'keio'            , 'Keio University',
                      'lbnl'            , 'LBNL',
                      'mercator'        , 'Mercator Genetics',
                      'merck'           , 'Merck',
                      'mrc mhu'         , 'MRC MHU',
                      'oklahoma'        , 'Oklahoma',
                      'perkin elmer'    , 'Perkin Elmer',
                      'sanger'          , 'Sanger Centre',
                      'shimizu'         , 'Shimizu University',
                      'tigr'            , 'The Institute for Genome Research',
                      'tokai'           , 'Tokai University',
                      'washington'      , 'University of Washington',
                      'w genome center' , 'University of Washington Genome Center',
                      'w medicine'      , 'University of Washington School of Medicine',
                      'unknown'         , 'Unknown',
                      'wugsc'           , 'Washington University Genome Sequencing Center',
                      'whitehead'       , 'Whitehead' );
    
    #abbreviation errors in lab entries                                                                  
    my %abbreviations;
    $abbreviations {'tigr'} = $valid_lab{tigr};
    $abbreviations {'sc'}   = $valid_lab{sanger};

    sub _seq_by_check {
        my ($self) = @_;
        $self->add_output(" Sequenced_by check");
        #exclude links
        if ($self->{_clone}->link())
        {
            $self->add_output(" ABORT: Check cannot run on LINK");
            return;
        }
        my $labfound = undef;   #flag for succesful identification of lab
        my $ace_lab = $self->{_clone}->sequenced_by();
        unless ($ace_lab)
        {
            $self->add_output (" FAIL: Sequenced_by tag not set");
            return;
        }
                
        #check against valid labs
        foreach my $lab (values(%valid_lab))
        {
            if ($ace_lab eq $lab)
            {
                $self->add_output(" PASS: Sequenced_by check $lab");
                $labfound = 'True';
                last;
            }
            elsif ($lab =~  /$ace_lab/i)    # lab is similar to valid lab entry
            {
                $labfound = 'True';
                $self->add_output(" FAIL: $ace_lab invalid format");
                $self->add_ace_reptag("Origin Sequenced_by", ("\"".$lab."\""));
                last;
            }
        }
 
        if ($labfound) #if lab not found check in abbreviations
        {
            foreach my $entry (keys(%abbreviations))
            {
                if ($ace_lab =~ /$entry/i)
                {
                    $labfound = 'True';
                    $self->add_output(" FAIL: $ace_lab is abbreviation"); 
                    $self->add_ace_reptag("Origin Sequenced_by",
                                                ("\"".$abbreviations{$entry}."\""));
                }
            }
        }
        #if lab entry still not found then output failure
        $self->add_output (" FAIL: $ace_lab is not a valid value") unless ($labfound);
    }#end function
}#end block

sub _subsequence_check {
    my ($self) =@_;
    $self->add_output(" Subsequence check");
    
    #exclude links
    if ($self->{_clone}->link())
    {
        $self->add_output(" ABORT: Check cannot run on LINK");
        return;
    }
        
    my @subsequence_list = $self->{_clone}->subsequence_list();
    $self->add_output(" FAIL: has no subsequences") 
                                                unless (@subsequence_list);  
    foreach my $subseq (@subsequence_list)
    {
        ##length of subsequence in clone        
        my @sub_coordinates = $self->{_clone}->subseq_clone_coordinates($subseq);
        unless (@sub_coordinates == 2)
        {
            $self->add_output(" FAIL: $subseq coordinates in bad format in $self->id ("
                                                                        .@sub_coordinates.")");
            next;
        }
        my ($sub_start, $sub_end) = $self->_minmax (@sub_coordinates);
        my $sub_length = abs ($sub_end - $sub_start) +1;
        
        ##length of subsequence as object
        my @coordinates = $self->{_clone}->subseq_internal_coordinates($subseq);
        if (@coordinates == 0)
        {
            $self->add_output(" FAIL: $subseq coordinates not found");
            $self->add_ace_delobj ('Sequence', $subseq);   #delete sequence object
            $self->add_ace_deltag ('Structure Subsequence', '"'.$subseq.'"'); #delete reference ot sequence
            next;
        }
        
        if (@coordinates%2 != 0)
        {      
            $self->add_output(" FAIL: $subseq odd number coordinates (".@coordinates.")");
             next;
        }
        my ($start, $end) = $self->_minmax(@coordinates);
        my $length = abs ($end - $start) +1;
        
        if ($sub_length == $length)
        {
            $self->add_output(" PASS: $subseq Subsequence length check");   
        }
        else
        {
            $self->add_output
            ("  FAIL: Subsequence $subseq sequence value $length doesn't match $sub_length");
        }  
    }
}

#pre: clones to be checked are links
sub _link_check {
    my ($self) =@_;
    $self->add_output(" Link check");

    if ($self->{_clone}->link())
    {
        foreach my $subseq ($self->{_clone}->subsequence_list())
        {
            my @coordinates = $self->{_clone}->
                                    subseq_clone_coordinates($subseq);
            my ($sub_start, $sub_end) = $self->_minmax(@coordinates);
            my $sub_length = ($sub_end - $sub_start) +1;                        
            my @internal_coordinates = 
                $self->{_clone}->subseq_internal_coordinates($subseq);             
            my ($start, $end) = $self->_minmax(@internal_coordinates);
            my $length = ($end - 1) +1; #NB should use $start ?
            if ($sub_length == $length)
            {
                $self->add_output (" PASS: $subseq length link check");
            }
            else
            {
                $self->add_output ("  FAIL: $subseq".
                        " length $length doesn't match link $sub_length");
            }
        } 
    }
    else 
    {$self->add_output(" ABORT: Sequence isn't link");}
}

#############################
#I/O functions
#############################
=head2 output

    Title   :   output
    Usage   :   $self->output($handle, $filename)
    Function:   get/set method for output of checkclones()
    Returns :   contents of file pointed to by handle
    Args    :   filehandle

=cut
sub output {
    my ($self, $handle) = @_;
    if ($handle)
    {
        $self->{_outfile} = $handle;
    }
    return \*{$self->{_outfile}};
}

=head2 ace_output

    Title   :   ace_output
    Usage   :   $self->ace_output($filename)
    Function:   get/set method for corrections based on checks run by 
                checkclones() in .ace format
    Returns :   contents of file pointed to by handle
    Args    :   filehandle

=cut
sub ace_output {
    my ($self, $handle) = @_;
    if ($handle)
    {   
        $self->{_aceoutfile} = $handle;        
    }
    return \*{$self->{_aceoutfile}};
}

sub add_output {
    my ($self, $str) = @_;
    if ($str)
    {
        print {$self->{_outfile}} $self->{_clone}->id.$str."\n";
    }
}

sub add_ace_deltag {
    my ($self, $tag) = @_;
    my $class = 'Genomic Sequence';
    my $object = $self->{_clone}->id;
    
    my $setobject = "$class \"$object\"\n";   #define the object
    my $deleteline = "-D $tag\n";           #delete the tag (if it exists)
    print {$self->{_aceoutfile}} $setobject;
    print {$self->{_aceoutfile}} $deleteline;
    print {$self->{_aceoutfile}} "\n";
}

sub add_ace_delobj {
    my ($self, $type, $name) = @_;
    my $class = $type;
    my $object = $name;
    
    my $deleteline = "-D $class \"$object\"\n";
    print {$self->{_aceoutfile}} $deleteline;
    print {$self->{_aceoutfile}} "\n";
}

sub add_ace_reptag {
    my ($self, $tag, @value) = @_;
    my $class = 'Genomic Sequence';
    my $object = $self->{_clone}->id;
    
    my $setobject = "$class \"$object\"\n";   #define the object
    my $deleteline = "-D $tag\n";           #delete the tag (if it exists)
    my $edit = "$tag @value\n"; #replace it with new value(s)
    print {$self->{_aceoutfile}} $setobject;
    print {$self->{_aceoutfile}} $deleteline;
    print {$self->{_aceoutfile}} $edit;
    print {$self->{_aceoutfile}} "\n"; 

}

sub add_ace_renobj {
    my ($self, $type, $name, $rename) = @_;
    my $class = $type;
    my $object = $name;
    my $newobj = $rename;
    
    my $renameobject = "-R $class \"$object\" \"$newobj\"\n";
    print  {$self->{_aceoutfile}} $renameobject;
    print {$self->{_aceoutfile}} "\n";
}

##########################
#misc
#########################

#returns min and max numbers from list in that order
sub _minmax {
    my ($self, @list) =@_;
    my ($min, $max) = @list; #initialise min and max with two numbers
    foreach my $number (@list)
    {   
        if ($number < $min) { $min = $number; } 
        if ($number > $max) { $max = $number; }
    }
    return ($min, $max);
}

















    
    
    
