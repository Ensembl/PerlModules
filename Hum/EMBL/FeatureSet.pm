
package Hum::EMBL::FeatureSet;

use strict;
use Carp;
use Hum::EMBL::Line;

sub new {
    my( $pkg ) = @_;
    
    return bless [], $pkg;
}

sub newFeature {
    my( $set ) = @_;
    
    my $ft = Hum::EMBL::FT->new;
    
    push(@$set, $ft);
    return $ft;
}

sub sortByPosition {
    my( $set ) = @_;
    
    # Get the star and end for each feature
    my @sort = map {[$_->location->start, $_->location->end, $_]} @$set;
    
    # Sort on start and ends
    @sort = sort {$a->[0] <=> $b->[0] or $a->[1] <=> $b->[1]} @sort;
    
    # Store the sorted array
    @$set = map $_->[2], @sort;
}

# EMBL won't allow two features with the same key and location
sub mergeFeatures {
    my( $set ) = @_;
    
    my( %tree );
    for (my $i = 0; $i < @$set;) {
        my $ft = $set->[$i];
        my $k = $ft->key;
        my $l = $ft->location;
        
        # Is there already a feature with this key and location?
        if (my $pt = $tree{$k}{$l}) {
            # Add all the qualifiers from this feature to the new one
            foreach my $qual ($ft->qualifiers) {
                $pt->addQualifier($qual);
            }
            # Remove the feature from the set
            splice(@$set, $i, 0);
        } else {
            $tree{$k}{$l} = $ft;
            $i++;
        }
    }
}

sub addToEntry {
    my( $set, $embl ) = @_;
    
    foreach my $f (@$set) {
        $embl->addLine($f);
    }
}

1;

__END__

