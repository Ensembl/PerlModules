
### Hum::EnsCmdLineDB

package Hum::EnsCmdLineDB;

use strict;
use warnings;
use Bio::EnsEMBL::DBSQL::DBAdaptor;

use Getopt::Long 'GetOptions';
use Term::ReadKey qw{ ReadMode ReadLine };


{
    my $host     = 'localhost';
    my $dbname   = '';
    my $user     = 'ensro';
    my $password = '';
    my $sgp_type = '';
    my $prompt   = 1;
    my $pipeline = 0;
    my $otter    = 0;
    my $port     = 3306;

    my( $dna_host, $dna_dbname, $dna_user, $dna_password );

    sub do_getopt {
        my( @script_args ) = @_;
    
        splice_defaults_into_ARGV();
    
        GetOptions(
            'host=s'                => \$host,
            'dbname=s'              => \$dbname,
            'user=s'                => \$user,
            'password=s'            => \$password,
            'nopassword'            => sub{ $password = undef; $prompt = 0 },
            'port=i'                => \$port,
            #'port=i'                => sub{ $port = $_[1]; warn "GOT PORT=$port\n" },

            'dnahost=s'             => \$dna_host,
            'dnadbname=s'           => \$dna_dbname,
            'dnauser=s'             => \$dna_user,
            'dnapassword=s'         => \$dna_password,

            'sgp|gold|assembly=s'   => \$sgp_type,
            'prompt!'               => \$prompt,
            'pipeline!'             => \$pipeline,
            'otter!'                => \$otter,
            @script_args,
            ) or die "Error processing command line\n";
        die "No database name (dbname) parameter given" unless $dbname;
    }

    sub connect {
        my $passwd = $password;
        if ($prompt and ! $password) {
            $passwd = prompt_for_password("Password for '$user': ");
        }

        my @adaptor_args = (
            -HOST   => $host,
            -DBNAME => $dbname,
            -USER   => $user,
            -PASS   => $passwd,
            -PORT   => $port,
            );

        #warn "Adaptor args = [@adaptor_args]\n";

        my $adaptor_class = 'Bio::EnsEMBL::DBSQL::DBAdaptor';
        if ($pipeline and $otter) {
            die "Can't set both -pipeline and -otter";
        }
        elsif ($pipeline) {
            require Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor;
            $adaptor_class = 'Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor';
        }
        elsif ($otter) {
            require Bio::Otter::DBSQL::DBAdaptor;
            $adaptor_class = 'Bio::Otter::DBSQL::DBAdaptor';
        }

        if ($dna_dbname) {
            my $dna_db = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
                -HOST   => $dna_host     || $host,
                -DBNAME => $dna_dbname,
                -USER   => $dna_user     || $user,
                -PASS   => defined($dna_password) ? $dna_password : $passwd,
                );
            push(@adaptor_args, -DNADB => $dna_db);
        }

        # Connect to the EnsEMBL database
        my $db_adaptor = $adaptor_class->new(@adaptor_args);
        if ($sgp_type) {
            if ($db_adaptor->can('assembly_type')) {
                $db_adaptor->assembly_type($sgp_type);
            } else {
                $db_adaptor->static_golden_path_type($sgp_type);
            }
        }            
        
        $passwd = '';
        
        return $db_adaptor;
    }
}

sub prompt_for_password {
    my $prompt = shift || "Password: ";
    print $prompt;

    ReadMode('noecho');
    my $password = ReadLine(0);
    print "\n";
    chomp $password;
    ReadMode('normal');
    return $password;
}

sub splice_defaults_into_ARGV {
    my $home = (getpwuid($<))[7];
    my $defaults_file = "$home/.ensdb_defaults";
    
    my( @options );
    local *ENSDEF;
    if (open ENSDEF, $defaults_file) {
        while (<ENSDEF>) {
            next if /^\s*#/;
            push(@options, split);
        }
    }
    close ENSDEF;
    unshift(@ARGV, @options);
}


1;

__END__

=head1 NAME - Hum::EnsCmdLineDB

=head1 SYNOPSIS

  use Hum::EnsCmdLineDB;
  Hum::EnsCmdLineDB::do_getopt(
        # Add script specific Getopt::Long::GetOptions
        # arguments here
        );
  my $dba = Hum::EnsCmdLineDB::connect();

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

