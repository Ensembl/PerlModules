
### Hum::Blast::DB::Multi

package Hum::Blast::DB::Multi;

use strict;
use Carp;
use Hum::Blast::DB;
use vars '@ISA';

@ISA = qw{ Hum::Blast::DB };

sub version {
    my( $self, $version ) = @_;
    
    if ($version) {
        $self->{'_version'} = $version;
    }
    return $self->{'_version'};
}

sub db_list {
    my( $self ) = @_;
    
    unless ($self->{'_db_list'}) {
        if ($self->write_access) {
            $self->{'_db_list'} = $self->_make_build_dbs;
        } else {
            $self->{'_db_list'} = $self->_read_dbs_from_disk;
        }
    }
    return @{$self->{'_db_list'}};
}

sub _make_build_dbs {
    my( $self ) = @_;
    
    my $db_name     = $self->db_name;
    my $type        = $self->type;
    my $path        = $self->path;
    my $build_path  = $self->build_path;
    my $version     = $self->version;
    
    my @file_list = $self->_list_db_files_from_path($build_path);
    my $part_count = @file_list;
    my( @db_list );
    foreach my $f (@file_list) {
        my ($file_path, $part) = @$f;
        my $db = Hum::Blast::DB->new();
        
        # We're going to be inexing, so propagate the information
        # from the Multi parent to its children.
        $db->db_name($db_name);
        $db->write_access(1);
        $db->build_path($file_path);
        $db->path("$path-$part");
        $db->part($part, $part_count);
        $db->type($type);
        $db->version($version) if $version;
        
        push(@db_list, $db);
   }
   return \@db_list;
}

sub _read_dbs_from_disk {
    my( $self ) = @_;
    
    my $path = $self->path;
    my $type = $self->type;
    my @file_list = $self->_list_db_files_from_path($path);
    my $part_count = @file_list;
    my( @db_list );
    foreach my $f (@file_list) {
        my ($file_path, $part) = @$f;
        
        # Make the new Blast::DB objects
        my $db = Hum::Blast::DB->new();
        $db->type($type);
        $db->path($file_path);
        
        # Check the definition of parts
        my ($stored_part, $stored_part_count) = $db->part;
        unless ($stored_part == $part
            and $stored_part_count == $part_count)
        {
            confess "Stored parts ($stored_part of $stored_part_count)\n",
                "inconsistent with files ($part of $part_count)";
        }
        
        push(@db_list, $db);
    }
    return \@db_list;
}

sub _list_db_files_from_path {
    my( $self, $path ) = @_;
    
    my $dir  = $self->_dir_name($path);
    $path = "$dir/$path"
        unless substr($path, 0, length($dir) + 1) eq "$dir/";
    local *BUILD;
    opendir BUILD, $dir or confess "Can't opendir '$dir' : $!";
    my $file = $self->_file_name($path);
    my $path_length = length($path);
    my @file_list =
        # Sort by part number
        sort {$a->[1] <=> $b->[1]}
        
        # Only show those with part numbers
        grep $_->[1],
        
        # Make each element into anon array of [filename, N]
        map [$_, /$path-(\d+)$/],
        
        # List all files in directory
        map "$dir/$_", readdir BUILD;
    closedir BUILD;
    
    confess "No DBs found for '$path'" unless @file_list;
    
    # Check that there are no missing files in sequence
    for (my $i = 0; $i < @file_list; $i++) {
        unless ($file_list[$i][1] == $i + 1) {
            confess "Missing file in list:\n",
                map "  $_->[0]\n", @file_list;
        }
    }
    return @file_list;
}

sub do_indexing {
    my( $self ) = @_;
    
    confess "Can't index: Don't have write access"
        unless $self->write_access;

    foreach my $sub_db ($self->db_list) {
        $sub_db->do_indexing;
    }
}

sub rename_build_to_path {
    my( $self ) = @_;
    
    foreach my $sub_db ($self->db_list) {
        $sub_db->rename_build_to_path;
    }
}

sub read_db_details {
    confess "Can't call read_db_details on Multi\n",
        "You can get individual DB objects with the db_list() method";
}

1;

__END__

=head1 NAME - Hum::Blast::DB::Multi

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

