
package Hum::Ace::EmblUtils;

use strict;
use Hum::Tracking qw( external_clone_name );
use Exporter;
use vars qw( @EXPORT_OK @ISA );
@ISA       = qw( Exporter );
@EXPORT_OK = qw( extCloneName projectAndSuffix );


{
    # For caching external clone names
    my( %ext_clone_name );

    sub extCloneName {
        my( @list ) = @_;
        
        # Convert all the sequence names to projects
        foreach (@list) {
            if (ref($_)) {
                die "Not an acedb object"
                        unless $_->isa('Ace::Object');
                ($_) = projectAndSuffix($_);
            }
        }
        
        # Fetch any names we don't have already
        my @missing = grep ! $ext_clone_name{$_}, @list;
        my $ext = external_clone_name(@missing);
        foreach my $p (keys %$ext) {
            $ext_clone_name{$p} = $ext->{$p};
        }
        
        # Fill in the names in the return array
        foreach (@list) {
            $_ = $ext_clone_name{$_};
        }
        
        return wantarray ? @list : $list[0];
    }
}

sub projectAndSuffix {
    my( $ace ) = @_;
    
    my( $project, $suffix );
    eval{ $project = $ace->at('Project.Project_name[1]')->name   };
    eval{ $suffix  = $ace->at('Project.Project_suffix[1]')->name };
    
    
    return($project, $suffix);
}


1;

__END__
