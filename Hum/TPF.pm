
### Hum::TPF

package Hum::TPF;

use strict;
use Hum::TPF::Parser;
use Hum::TPF::Row::Clone;
use Hum::TPF::Row::Gap;

sub new {
    my( $pkg ) = @_;
    
    return bless {
        '_rows' => [],
        }, $pkg;
}

sub db_id {
    my( $self, $db_id ) = @_;
    
    if ($db_id) {
        $self->{'_db_id'} = $db_id;
    }
    return $self->{'_db_id'};
}

sub add_Row {
    my( $self, $row ) = @_;
    
    push @{$self->{'_rows'}}, $row;
}

sub fetch_all_Rows {
    my( $self ) = @_;
    
    return @{$self->{'_rows'}};
}

sub to_string {
    my( $self ) = @_;
    
    my $str = '';
    foreach my $row ($self->fetch_all_Rows) {
        $str .= $row->to_string;
    }
    return $str;
}

1;

__END__

=head1 NAME - Hum::TPF

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

