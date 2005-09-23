
### Hum::Ace::MethodCollection

package Hum::Ace::MethodCollection;

use strict;
use Carp;
use Symbol 'gensym';

use Hum::Ace::Method;
use Hum::Ace::AceText;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub new_from_string {
    my( $pkg, $str ) = @_;
    
    my $self = $pkg->new;

    # Split text into paragraphs (which are separated by two or more blank lines).
    foreach my $para (split /\n{2,}/, $str) {
        # Create Method object from paragraphs that have
        # any lines that begin with a word character.
        if ($para =~ /^\w/m) {
            my $txt  = Hum::Ace::AceText->new($para);
            my $meth = Hum::Ace::Method->new_from_AceText($txt);
            $self->add_Method($meth);
        }
    }
    return $self;
}

sub ace_string {
    my( $self ) = @_;
    
    my $str = '';
    foreach my $meth (@{$self->get_all_Methods}) {
        $str .= $meth->ace_string;
    }
    return $str;
}

sub new_from_file {
    my( $pkg, $file ) = @_;
    
    local $/ = undef;
    
    my $fh = gensym();
    open $fh, $file or die "Can't read '$file' : $!";
    my $str = <$fh>;
    close $fh or die "Error reading '$file' : $!";
    return $pkg->new_from_string($str);
}

sub write_to_file {
    my( $self, $file ) = @_;
    
    my $fh = gensym();
    open $fh, "> $file" or confess "Can't write to '$file' : $!";
    print $fh $self->ace_string;
    close $fh or confess "Error writing to '$file' : $!";
}

sub add_Method {
    my( $self, $method ) = @_;
    
    if ($method) {
        my $name = $method->name
            or confess "Can't add un-named method";
        if (my $existing = $self->{'_method_by_name'}{$name}) {
            confess "Already have method called '$name':\n",
                $existing->ace_string;
        }
        my $lst = $self->get_all_Methods;
        push @$lst, $method;
        $self->{'_method_by_name'}{$name} = $method;
        
    } else {
        confess "missing Hum::Ace::Method argument";
    }
}

sub get_all_Methods {
    my( $self ) = @_;
    
    my $lst = $self->{'_method_list'} ||= [];
    return $lst;
}

sub get_Method_by_name {
    my( $self, $name ) = @_;
    
    confess "Missing name argument" unless $name;
    
    return $self->{'_method_by_name'}{$name};
}

sub flush_Methods {
    my( $self ) = @_;
    
    $self->{'_method_list'} = [];
    $self->{'_method_by_name'} = {};
}

sub process_for_otterlace {
    my( $self ) = @_;
    
    $self->create_full_gene_Methods;
    $self->cluster_Methods_with_same_column_name;
    $self->order_by_zone;
    $self->assign_right_priorities;
}

sub order_by_zone {
    my( $self ) = @_;
    
    my $lst = $self->get_all_Methods;
    
    # Multiple methods with the same zone_number will
    # be left in their original order by sort.
    @$lst = sort {$a->zone_number <=> $b->zone_number} @$lst;
}

sub order_by_right_priority {
    my( $self ) = @_;
    
    my $lst = $self->get_all_Methods;
    @$lst = sort {$a->right_priority <=> $b->right_priority} @$lst;
}


sub cluster_Methods_with_same_column_name {
    my( $self ) = @_;
    
    my @all_meth = @{$self->get_all_Methods};
    $self->flush_Methods;
    my %column_cluster = ();
    foreach my $meth (@all_meth) {
        if (my $col = $meth->column_name) {
            my $cluster = $column_cluster{$col} ||= [];
            push(@$cluster, $meth);
        }
    }
    while (my $meth = shift @all_meth) {
        if (my $col = $meth->column_name) {
            # Add the whole cluster where we find its first
            # member in the list.
            if (my $cluster = delete $column_cluster{$col}) {
                my $zone = $meth->zone_number;
                foreach my $meth (@$cluster) {
                    # Make sure they are all in the same zone
                    $meth->zone_number($zone);
                    $self->add_Method($meth);
                }
            }
        } else {
            $self->add_Method($meth);
        }
    }
}

sub assign_right_priorities {
    my( $self ) = @_;
    
    my $incr = 0.020000;
    
    # The "oligo zone" is a region of the fMap where weird things
    # happen due to the special oligo drawing code.
    my @oligo_zone = (3.2, 3.9);
    
    my $meth_list = $self->get_all_Methods;
    # Must start at 0.1 or objects get drawn left of the ruler in fMap
    my $pos = 0.1;
    for (my $i = 0; $i < @$meth_list; $i++) {
        my $method = $meth_list->[$i];
        next if $method->right_priority_fixed;

        my $prev = $i > 0 ? $meth_list->[$i - 1] : undef;

        # Don't increase right_priority if we are
        # in the same column as the previous method
        if  ($prev and $prev->column_name and $prev->column_name eq $method->column_name) {
            $method->right_priority($prev->right_priority);
        }
        elsif ($pos >= $oligo_zone[0] and $pos <= $oligo_zone[1]) {
            #warn "Skipping oligo twilight zone\n";
            $pos = $oligo_zone[1] + $incr;
        }
        elsif (my $pri = $method->right_priority) {
            # Keep values greater than 5 greater than 5
            if ($pri >= 5 and $pos < 5) {
                $pos = 5;
            }
            # Keep values greater than 4 greater than 4
            elsif ($pri >= 4 and $pos < 4) {
                $pos = 4;
            }
            else {
                $pos += $incr;
            }
        }
        else {
            $pos += $incr;
        }

        $method->right_priority($pos);
    }
}

sub create_full_gene_Methods {
    my( $self ) = @_;
    
    my $meth_list = $self->get_all_Methods;
    $self->flush_Methods;
    
    # Take the skeleton prefix methods out of the list
    my @prefix_methods;
    for (my $i = 0; $i < @$meth_list;) {
        my $meth = $meth_list->[$i];
        if ($meth->name =~ /^[A-Z_]+:$/) {
            splice(@$meth_list, $i, 1);
            push(@prefix_methods, $meth);
        } else {
            $i++;
        }
    }
    
    my @mutable_methods;
    foreach my $method (@$meth_list) {
        # Skip existing _trunc methods - we will make new ones
        next if $method->name =~ /_trunc$/;
        
        $self->add_Method($method);
        if (my $type = $method->mutable) {
            push(@mutable_methods, $method);
            $self->add_Method($self->make_trunc_Method($method));
        }
    }

    # Make copies of all the editable transcript methods for each prefix
    foreach my $prefix (@prefix_methods) {
        foreach my $method (@mutable_methods) {
            my $new = $method->clone;
            $new->mutable(0);
            $new->name($prefix->name . $method->name);
            $new->color($prefix->color);
            if ($method->cds_color) {
                $new->cds_color($prefix->cds_color);
            }
            $self->add_Method($new);
            $self->add_Method($self->make_trunc_Method($new));
        }
    }
}

sub make_trunc_Method {
    my( $self, $method ) = @_;
    
    my $new = $method->clone;
    $new->name($method->name . '_trunc');
    $new->mutable(0);
    $new->color('GRAY');
    $new->cds_color('BLACK') if $method->cds_color;
    return $new;
}

1;

__END__

=head1 NAME - Hum::Ace::MethodCollection

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

