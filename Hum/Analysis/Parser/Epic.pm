
### Hum::Analysis::Parser::Epic

package Hum::Analysis::Parser::Epic;

use strict;
use warnings;
use Carp;
use Hum::Ace::SeqFeature::Pair::Epic;
use File::Path 'rmtree';

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub get_all_Features {
    my( $self ) = @_;
    
    my $all = [];
    while (my $f = $self->next_Feature) {
        push(@$all, $f);
    }
    return $all;
}

sub next_Feature {
    my( $self ) = @_;

    my $feature = $self->_current_feature;
    my $aln_str = '';
    my $fh = $self->results_filehandle or return( $feature );
    while (<$fh>) {

      if (!/^\z/) {
            my $new_feature = $self->new_Feature_from_epic_line($_)
                or confess "No new feature returned";
            if ($feature) {
                $self->_current_feature($new_feature);
                return $feature;
            } else {
                $feature = $new_feature;
            }
        elsif ($feature) {
            $aln_str .= $_;
        }
    }

    $self->close_results_filehandle;

    return $feature;
}

sub _current_feature {
    my( $self, $feature ) = @_;
    
    if ($feature) {
        $self->{'_current_feature'} = $feature;
    }
    elsif ($feature = $self->{'_current_feature'}) {
        $self->{'_current_feature'} = undef;
        return $feature;
    }
}

sub new_Feature_from_epic_line {
  my( $self, $line ) = @_;


  chomp $line;
  # 31337M  31337   100.00  AC171462.2      11238   42574   AC118196.12     189918  158582
  my @data = split /\s+/, $line;


  my $feature = Hum::Ace::SeqFeature::Pair::Epic->new();
  
  $feature->cigar(      $data[0] );
  $feature->length(     $data[1] );


  
  my ($percent_insertion, $percent_deletion);
  foreach my $block ( $cigar =~ /(\d*\w)/g) {
    my ($length, $type) = $block =~ /(\d*)(\w)/;
    $length ||= 1;
    
    $percent_insertion += $length ( if $type eq "I");
    $percent_deletion  += $length ( if $type eq "D");
  }
  
  $percent_insertion /= $length;
  $percent_deletion  /= $length;

  # NCBI does not count these, should we?
  $percent_insertion = 0;
  $percent_deletion  = 0;

  my $percent_substitution = 100 - $data[2];
  
  $feature->percent_substitution( $percent_substitution );
  $feature->percent_insertion(    $percent_insertion    );
  $feature->percent_deletion(     $percent_deletion     );

  $feature->percent_id( $data[2] );
  
  $feature->seq_name(   $data[3]  );
  $feature->seq_start(  $data[4]  );
  $feature->seq_end(    $data[5]  );
  
  $feature->hit_name(   $data[6]  );
  $feature->hit_start(  $data[7]  );
  $feature->hit_end(    $data[8]  );
  
  $feature->seq_strand(1);
  $feature->hit_strand( $data[7] > $data[8] ? 1 : -1 );
  
  return $feature;
}



sub results_filehandle {
    my( $self, $results_filehandle ) = @_;

    if ($results_filehandle) {
        $self->{'_results_filehandle'} = $results_filehandle;
    }
    return $self->{'_results_filehandle'};
}

sub close_results_filehandle {
    my( $self ) = @_;

    if (my $fh = $self->{'_results_filehandle'}) {
      #close($fh) or confess "Error from cross_match filehandle exit($?)";
      close($fh);
      $self->{'_results_filehandle_status'} = $?;
    }

    $self->{'_results_filehandle'} = undef;
}

sub results_filehandle_status {

  my( $self, $status ) = @_;
  if ( $status ){
    $self->{'_results_filehandle_status'} = $status
  }

  return $self->{'_results_filehandle_status'};
}


sub temporary_directory {
    my( $self, $temporary_directory ) = @_;

    if ($temporary_directory) {
        $self->{'_temporary_directory'} = $temporary_directory;
    }
    return $self->{'_temporary_directory'};
}


sub DESTROY {
    my( $self ) = @_;
    
    if (my $log = $self->crossmatch_log_file) {
        unlink($log);
    }
    if (my $dir = $self->temporary_directory) {
        #warn "Removing '$dir'";
        rmtree($dir);
    }
}

1;

__END__

=head1 NAME - Hum::Analysis::Parser::CrossMatch

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

