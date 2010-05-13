
### Hum::ZMapStyle

package Hum::ZMapStyle;

use strict;
use warnings;
use Carp;

our $AUTOLOAD;

sub new {
    my( $pkg, %args ) = @_;
    my $self = bless {}, $pkg;
    
    for my $param (qw(name collection)) {
        $self->$param($args{$param});
    }
    
    return $self;
}

sub name {
    my ($self, $name) = @_;
    $self->{_name} = $name if $name;
    return $self->{_name};
}

sub collection {
    my ($self, $collection) = @_;
    $self->{_collection} = $collection if $collection;
    return $self->{_collection};
}

# NB this just stores the name of the parent style, not the object itself as this makes
# writing the stylesfile out later simpler, the actual parent object can be obtained with
# a line like $style->collection->get_style($style->parent_style)
sub parent_style {
    my ($self, $parent_style) = @_;
    
    if ($parent_style) {
        # if we're passed a style object then be tolerant and just save the object's name
        if ($parent_style->isa(ref($self))) {
            $self->{parent_style} = $parent_style->name;
        }
        else {
            $self->{parent_style} = $parent_style
        }
    }
    
    return $self->{parent_style};
}

sub is_mutable {
    my ($self) = @_;
    
    if ($self->name =~ /^curated/) {
        return 1;
    }
    elsif (my $parent = $self->parent_style) {
        return $self->collection->get_style($parent)->is_mutable;
    }
    else {
        return 0;
    }
}

sub to_style_hash {
    my $self = shift;
    
    my $hash;
    
    for my $param (keys %$self) {
        unless ($param =~ /^_/) { # ignore object variables
            my $val = $self->{$param};
            $param =~ s/_/-/g; # change the _s back to -s
            $hash->{$param} = $val;
        }
    }
    
    return $hash;
}

sub AUTOLOAD {
    my ($self, $val) = @_;
    
    # get what we were called as
    my $name = $AUTOLOAD;
    $name =~ s/.*://;
    
    # ignore special perl methods (like DESTROY etc.)
    return if $name =~ /^[A-Z]*$/; 
    
    # turn -s to _s to make them valid method names
    $name =~ s/-/_/g;
    
    $self->{$name} = $val if defined $val;
    
    # if we have this param set return it
    return $self->{$name} if defined $self->{$name};
    
    # otherwise try the parent (if we have one)
    if (my $parent = $self->parent_style) {
        #confess "Failed to find parent style ".$parent->name." for style ".$self->name unless $self->collection->get_style($parent);
        return $self->collection->get_style($parent)->$name;
    }
}

1;

__END__

=head1 NAME - Hum::ZMapStyle

A class representing a ZMap style

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk
