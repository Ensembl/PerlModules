
### Hum::Species


package Hum::Species;

use strict;
use Carp;
use Hum::Submission ("prepare_statement");

{

  my $all_spec_info = [];
  my ($hashref, $info);

  # all species data returned are default to those with active column set to 'yes'

  $info = prepare_statement("SELECT * FROM species where active = 'yes'");
  $info->execute();

  while ( $hashref = $info->fetchrow_hashref() ) {
    my $spec = Hum::Species->new;

    $spec->name           ($hashref->{species_name});
    $spec->taxon_id       ($hashref->{taxon_id});
    $spec->genus          ($hashref->{genus});
    $spec->species        ($hashref->{species});
    $spec->common_name    ($hashref->{common_name});
    $spec->ftp_dir        ($hashref->{ftp_dir});
    $spec->ftp_chr_prefix ($hashref->{ftp_chr_prefix});
    $spec->active         ($hashref->{active});
    $spec->division       ($hashref->{division});
    $spec->lineage        ($hashref->{lineage});
    push(@$all_spec_info, $spec);
  }

  sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
  }

  sub list_all_species_names {
	my ( $self ) = @_;

	my $spec_name_list = [];
	foreach my $species (@$all_spec_info) {
	  push( @$spec_name_list, $species->name );
	}
	return $spec_name_list;
  }

  sub fetch_all_Species {
    my ( $self ) = @_;

    return $all_spec_info;
  }

  sub fetch_Species_by_name {
    my ( $self, $species_name ) = @_;

    unless ( $species_name ){
      confess "Missing species_name!";
    }
    return $self->_filter("name", $species_name);

  }

  sub fetch_Species_by_taxon_id {
    my ( $self, $taxon_id ) = @_;

    unless ( $taxon_id ){
      confess "Missing taxon_id!";
    }
    return $self->_filter("taxon_id", $taxon_id);
  }

  sub fetch_Species_by_genus {
    my ( $self, $genus ) = @_;

    unless ( $genus ){
      confess "Missing genus!";
    }

    return $self->_filter("genus", $genus);
  }

  sub fetch_Species_by_genus_species {
    my ( $self, $genus, $species ) = @_;

    unless ( $genus and $species ){
      confess "Missing bionomial info: genus and/or species!";
    }

    return $self->_filter("genus", $genus, "species", $species);
  }

  sub fetch_Species_by_common_name {
    my ( $self, $common_name ) = @_;

    unless ( $common_name ){
      confess "Missing common_name!";
    }

    return $self->_filter("common_name", $common_name);
  }

  sub fetch_sll_Species_ftp_structure {
    my ( $self ) = @_;

	my $ftp_structure = {};
	foreach my $species (@$all_spec_info) {
	  my $name = $species->name;

	  if ( $species->ftp_chr_prefix ) {
		push( @{$ftp_structure->{"\u$name"}}, $species->ftp_dir, $species->ftp_chr_prefix );
	  } else {
		push( @{$ftp_structure->{"\u$name"}}, $species->ftp_dir);
	  }
	}

	return $ftp_structure;
  }

  sub _filter {
    my ( $self, $method1, $val1, $method2, $val2 ) = @_;
	
	if ( $method1 and $val1 ) {

	  my $obj_count = 0;
	  my $spec_list = [];
	  my $spec;

	  foreach my $e ( @$all_spec_info ) {
		if ( lc($e->$method1) eq lc("$val1") ) {
		  $obj_count++;
		  $spec = Hum::Species->new;
		  $spec = $self->_get_set_data($spec, $e);
		  push(@$spec_list, $spec); 
		}
	  }
	  if ( $obj_count > 1 ) {
		return $spec_list;
	  } elsif ( $obj_count == 1 ) {
		return $spec;
	  } else {
		confess "Invalid arguments";
	  }
	} elsif ( $method1 and $val1 and $method2 and $val2 ) {
	  foreach my $e ( @$all_spec_info ) {
		if ( lc($e->$method1) eq lc("$val1") and lc($e->$method2) eq lc("$val2") ) {	
		  my $spec = Hum::Species->new;
		  return $self->_get_set_data($spec, $e);
		}
	  }
	  confess "Invalid argument(s)";
	}
  }

  sub _get_set_data {

	my ( $self, $new_spec, $wanted ) =@_;

	$new_spec->name           ($wanted->name);
	$new_spec->taxon_id       ($wanted->taxon_id);
	$new_spec->genus          ($wanted->genus);
	$new_spec->species        ($wanted->species);
	$new_spec->common_name    ($wanted->common_name);
	$new_spec->ftp_dir        ($wanted->ftp_dir);
	$new_spec->ftp_chr_prefix ($wanted->ftp_chr_prefix);	
	$new_spec->active         ($wanted->active);
	$new_spec->division       ($wanted->division);
	$new_spec->lineage        ($wanted->lineage);
	return $new_spec;
  }

  sub name {
    my ( $self, $colval ) = @_;

    if ( ! $self->{species_name} ) {
      $self->{species_name} = $colval;
    }

    return $self->{species_name};
  }

  sub taxon_id {
    my ( $self, $colvalue ) =@_;

    unless ( $self->{taxon_id} ) {
      $self->{taxon_id} = $colvalue;
    }

    return $self->{taxon_id};
  }

  sub genus {
    my ( $self, $colvalue ) =@_;

    unless ( $self->{genus} ) {
      $self->{genus} = $colvalue;
    }

    return $self->{genus};
  }

  sub species {
    my ( $self, $colvalue ) =@_;

    unless ( $self->{species} ) {
      $self->{species} = $colvalue;
    }

    return $self->{species};
  }

  sub common_name {
    my ( $self, $colvalue ) =@_;

    unless ( $self->{common_name} ) {
      $self->{common_name} = $colvalue;
    }

    return $self->{common_name};
  }

  sub ftp_dir {
    my ( $self, $colvalue ) =@_;

    unless ( $self->{ftp_dir} ) {
      $self->{ftp_dir} = $colvalue;
    }

    return $self->{ftp_dir};
  }

  sub ftp_chr_prefix {
    my ( $self, $colvalue ) =@_;

    unless ( $self->{ftp_chr_prefix} ) {
      $self->{ftp_chr_prefix} = $colvalue;
    }

    return $self->{ftp_chr_prefix};
  }

  sub active {
    my ( $self, $colvalue ) =@_;

    unless ( $self->{active} ) {
      $self->{active} = $colvalue;
    }

    return $self->{active};
  }

  sub division {
  	my ( $self, $colvalue ) =@_;

    unless ( $self->{division} ) {
      $self->{division} = $colvalue;
    }

    return $self->{division};
  }

  sub lineage {
    my ( $self, $colvalue ) =@_;

    unless ( $self->{lineage} ) {
      $self->{lineage} = $colvalue;
    }

    return $self->{lineage};
  }


}

1;

__END__

=head1 NAME - Hum::Species

=head1 AUTHOR

Chao-Kung Chen B<email> ck1@sanger.ac.uk

