
### Hum::Species


package Hum::Species;

use strict;
use warnings;
use Carp;
use Hum::Submission qw{ prepare_statement };

{
    my $all_species = undef;

    sub fetch_all_Species {
        my ( $self ) = @_;

        unless ($all_species) {
            $all_species = [];
            my $sth = prepare_statement("SELECT * FROM species where active = 'yes'");
            $sth->execute;

            while (my $hashref = $sth->fetchrow_hashref()) {
                my $spec = Hum::Species->new;
                $spec->name           ($hashref->{species_name});
                $spec->taxon_id       ($hashref->{taxon_id});
                $spec->genus          ($hashref->{genus});
                $spec->species        ($hashref->{species});
                $spec->common_name    ($hashref->{common_name});
                $spec->ftp_dir        ($hashref->{ftp_dir});
                $spec->ftp_chr_prefix ($hashref->{ftp_chr_prefix});
                $spec->division       ($hashref->{division});
                $spec->lineage        ($hashref->{lineage});
                push(@$all_species, $spec);
            }
        }
        return @$all_species;
    }
}

sub new {
    my( $pkg ) = @_;

    return bless {}, $pkg;
}

sub list_all_species_names {
    my( $pkg ) = @_;

    return map $_->name, $pkg->fetch_all_Species;
}

sub fetch_Species_by_name {
    my( $pkg, $name ) = @_;

    my ($species) = grep {$_->name eq $name} $pkg->fetch_all_Species;
    return $species;
}

sub fetch_Species_by_taxon_id {
    my( $pkg, $taxon_id ) = @_;

    my ($species) = grep {$_->taxon_id == $taxon_id} $pkg->fetch_all_Species;
    return $species;
}

sub fetch_Species_by_genus_species {
    my( $pkg, $genus, $species ) = @_;
    
    confess "Missing argument: genus = '$genus'; species = '$species'"
        unless $genus and $species;
    
    foreach my $species ($pkg->fetch_all_Species) {
        if ($species->genus eq $genus and $species->species eq $species) {
            return $species;
        }
    }
    return;
}

sub binomial {
    my( $self ) = @_;
    
    my $genus   = $self->genus   or confess   "genus field not set";
    my $species = $self->species or confess "species field not set";
    return "$genus $species";
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub taxon_id {
    my( $self, $taxon_id ) = @_;
    
    if ($taxon_id) {
        $self->{'_taxon_id'} = $taxon_id;
    }
    return $self->{'_taxon_id'};
}

sub genus {
    my( $self, $genus ) = @_;
    
    if ($genus) {
        $self->{'_genus'} = $genus;
    }
    return $self->{'_genus'};
}

sub species {
    my( $self, $species ) = @_;
    
    if ($species) {
        $self->{'_species'} = $species;
    }
    return $self->{'_species'};
}

sub common_name {
    my( $self, $common_name ) = @_;
    
    if ($common_name) {
        $self->{'_common_name'} = $common_name;
    }
    return $self->{'_common_name'};
}

sub ftp_dir {
    my( $self, $ftp_dir ) = @_;
    
    if ($ftp_dir) {
        $self->{'_ftp_dir'} = $ftp_dir;
    }
    return $self->{'_ftp_dir'};
}

sub ftp_chr_prefix {
    my( $self, $ftp_chr_prefix ) = @_;
    
    if ($ftp_chr_prefix) {
        $self->{'_ftp_chr_prefix'} = $ftp_chr_prefix;
    }
    return $self->{'_ftp_chr_prefix'};
}

=pod

=head2 EMBL Database Divisions

    Division                Code
    -----------------       ----
    ESTs                    EST
    Bacteriophage           PHG
    Fungi                   FUN
    Genome survey           GSS
    High Throughput cDNA    HTC
    High Throughput Genome  HTG
    Human                   HUM
    Invertebrates           INV
    Mus musculus            MUS
    Organelles              ORG
    Other Mammals           MAM
    Other Vertebrates       VRT
    Plants                  PLN
    Prokaryotes             PRO
    Rodents                 ROD
    STSs                    STS
    Synthetic               SYN
    Unclassified            UNC
    Viruses                 VRL

=cut

sub division {
    my( $self, $division ) = @_;
    
    if ($division) {
        $self->{'_division'} = $division;
    }
    return $self->{'_division'};
}

sub lineage {
    my( $self, $lineage ) = @_;
    
    if ($lineage) {
        $self->{'_lineage'} = $lineage;
    }
    return $self->{'_lineage'};
}


1;

__END__

=head1 NAME - Hum::Species

=head1 AUTHOR

Chao-Kung Chen B<email> ck1@sanger.ac.uk

