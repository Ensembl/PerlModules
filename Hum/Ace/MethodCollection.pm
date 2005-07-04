
### Hum::Ace::MethodCollection

package Hum::Ace::MethodCollection;

use strict;
use Carp;

use Hum::Ace::Method;
use Hum::Ace::AceText;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub new_from_string {
    my( $pkg, $str ) = @_;
    
    my $self = $pkg->new;

    # Split text into paragraphs of two or more lines
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

sub add_Method {
    my( $self, $method ) = @_;
    
    if ($method) {
        my $lst = $self->get_all_Methods;
        push @$lst, $method;
    } else {
        confess "missing Hum::Ace::Method argument";
    }
}

sub get_all_Methods {
    my( $self ) = @_;
    
    my $lst = $self->{'_method_list'} ||= [];
    return $lst;
}

sub flush_Methods {
    my( $self ) = @_;
    
    $self->{'_method_list'} = [];
}

sub order {
    my( $self ) = @_;
    
    $self->cluster_Methods_with_same_column_name;
    
    my $lst = $self->get_all_Methods;
    
    # Multiple methods with the same zone_number will
    # be left in their original order by sort.
    @$lst = sort {$a->zone_number <=> $b->zone_number} @$lst;
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
    my $pos = 0;
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

1;

__END__

=head1 NAME - Hum::Ace::MethodCollection

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

