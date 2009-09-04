
package Hum::EMBL::FeatureSet;

use strict;
use warnings;
#use Carp 'cluck';
use Hum::EMBL::Line;

sub new {
    my( $pkg ) = @_;
    
    return bless [], $pkg;
}

sub newFeature {
    my( $set ) = @_;
    
    my $ft = 'Hum::EMBL::Line::FT'->new;
    
    push(@$set, $ft);
    return $ft;
}

sub sortByPosition {
    my( $set ) = @_;
    
    #cluck "called sort";
    
    # Get the start and end for each feature
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
        my $l = $ft->location->hash_key;
        
        # Is there already a feature with this key and location?
        if (my $pt = $tree{$k}{$l}) {
            # Add all the qualifiers from this feature to the new one
            foreach my $qual ($ft->qualifiers) {
                $pt->addQualifier($qual);
            }
            # Remove the feature from the set
            splice(@$set, $i, 1);
        } else {
            $tree{$k}{$l} = $ft;
            $i++;
        }
    }
}

sub removeDuplicateFeatures {
    my( $set ) = @_;
    
    my( %tree );
    for (my $i = 0; $i < @$set;) {
        my $ft = $set->[$i];
        my $k = $ft->key;
        my $l = $ft->location->hash_key;
        
        # Is there already a feature with this key and location?
        if ($tree{$k}{$l}) {
            # Remove the feature from the set
            splice(@$set, $i, 1);
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

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>
