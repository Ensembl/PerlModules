
### Hum::EnsCmdLineDB

package Hum::EnsCmdLineDB;

use strict;
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

    my( $dna_host, $dna_dbname, $dna_user, $dna_password );

    sub do_getopt {
        my( @script_args ) = @_;
    
        splice_defaults_into_ARGV();
    
        GetOptions(
            'host=s'        => \$host,
            'dbname=s'      => \$dbname,
            'user=s'        => \$user,
            'password=s'    => \$password,
            'nopassword'    => sub{ $password = undef; $prompt = 0 },

            'dnahost=s'     => \$dna_host,
            'dnadbname=s'   => \$dna_dbname,
            'dnauser=s'     => \$dna_user,
            'dnapassword=s' => \$dna_password,

            'sgp|gold=s'    => \$sgp_type,
            'prompt!'       => \$prompt,
            'pipeline!'     => \$pipeline,
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
            );

        my $adaptor_class = 'Bio::EnsEMBL::DBSQL::DBAdaptor';
        if ($pipeline) {
            require Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor;
            $adaptor_class = 'Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor';
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
        $db_adaptor->static_golden_path_type($sgp_type) if $sgp_type;
        
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
            push(@options, split);
        }
    }
    close ENSDEF;
    unshift(@ARGV, @options);
}


1;

__END__

=head1 NAME - Hum::EnsCmdLineDB

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

