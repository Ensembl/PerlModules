
### Hum::ZMapStyleCollection

package Hum::ZMapStyleCollection;

use strict;
use warnings;
use Carp;

use Config::IniFiles;
use IO::Scalar;     # Needed by Config::IniFiles for
                    # Config::IniFiles->new( -file => \$string )
                    # to work, but you don't get an obvious
                    # error message if it is not installed.
use Data::Dumper;

use Hum::ZMapStyle;

sub new {
    my( $pkg ) = @_;
    return bless {}, $pkg;
}

sub new_from_string {
    my ($pkg, $string) = @_;
    
    my $self = $pkg->new;
 
    my $cfg = Config::IniFiles->new( -file => \$string ) 
        or die "Error parsing styles from server:\n",
            join("\n", @Config::IniFiles::errors),
            "\nString was: ", substr($string, 0, 250);
    
    for my $sect ($cfg->Sections) {
        my $style = Hum::ZMapStyle->new(name => $sect, collection => $self); 
        for my $param ($cfg->Parameters($sect)) {
            if ($param eq 'parent-style') {
                $style->parent_style($cfg->val($sect, $param));
            }
            else {
                $style->$param($cfg->val($sect, $param));
            }
        }
        $self->add_style($style);
    }
    
    return $self;
}

sub add_style {
    my ($self, $style) = @_;
    confess "Argument must be a Hum::ZMapStyle object, not a ".ref($style) unless $style->isa('Hum::ZMapStyle');
    $self->{_styles}->{$style->name} = $style;
}

sub get_style {
    my ($self, $style_name) = @_;
    return $self->{_styles}->{$style_name};
}

sub write_to_file {
    my ($self, $filename) = @_;
    
    my $styles = $self->{_styles};
    
    my $cfg = Config::IniFiles->new;
    $cfg->SetFileName($filename);
    
    # XXX: sort the styles into ranks so that no child style is specified before
    # its parent, this works around a bug in zmap which will hopefully be fixed
    
    my @ranks;
    
    for my $name (sort keys %$styles) {
        
        my $style = $styles->{$name};
        my $orig_style = $style;
        my $rank = 0;
        
        while ($style) {
            my $parent = $style->parent_style;
            last unless $parent;
            $rank++;
            $style = $self->get_style($parent);
        }
        
        my $equivs = $ranks[$rank] ||= [];
        push @$equivs, $orig_style;
    }
    
    for my $equivs (@ranks) {
        for my $style (@$equivs) {
            my $name = $style->name;
            $cfg->AddSection($name);
            my $params = $style->to_style_hash;
            for my $param (keys %$params) {
                $cfg->newval($name, $param, $params->{$param});
            }
        }
    }
    
    # write the styles out in alphabetical order
    
#    for my $name (sort keys %$styles) {
#        my $style = $styles->{$name};
#        $cfg->AddSection($name);
#        my $params = $style->to_style_hash;
#        for my $param (keys %$params) {
#            $cfg->newval($name, $param, $params->{$param});
#        }
#    }
    
    $cfg->RewriteConfig or die "Failed to write styles file '$filename': {@Config::IniFiles::errors}";
}

1;

__END__

=head1 NAME - Hum::ZMapStyleCollection

A class representing a collection of ZMap styles

=head1 AUTHOR

Graham Ritchie B<email> gr5@sanger.ac.uk


