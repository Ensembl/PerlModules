
### Hum::TPF::Parser

package Hum::TPF::Parser;

use strict;
use warnings;
use Carp;
use Hum::TPF;
use Hum::Sort 'ace_sort';

my (
    %file,
    %errors,
    %uniq_clone,
    %uniq_accession,
    %tpf,
    );

sub new {
    my( $pkg ) = @_;
    
    my $str = '';
    return bless \$str, $pkg;
}

sub DESTROY {
    shift->clear_data;
}

sub clear_data {
    my $self = shift;
    
    delete           $file{$self};
    delete         $errors{$self};
    delete     $uniq_clone{$self};
    delete $uniq_accession{$self};
    delete            $tpf{$self};
}

sub file {
    my( $self, $file ) = @_;
    
    if ($file) {
        my $type = ref($file);
        unless ($type and $type eq 'GLOB') {
            open my $fh, $file or confess "Can't read '$file' : $!";
            $file = $fh;
        }
        $file{$self} = $file;
    }
    return $file{$self};
}

sub parse {
    my( $self, $str ) = @_;

    local $/ = "\n";
    $tpf{$self} = Hum::TPF->new;

    if ($str) {
        if ($file{$self}) {
            confess "string argument given, but filehandle defined too!";
        }
        while ($str =~ /^(.+)$/mg) {
            # Pattern match automatically skips blank lines
            $self->parse_line($1);
        }
    } else {
        my $fh = $self->file or confess "file not set";
        while (<$fh>) {
            chomp;
            next if /^\s*$/;
            $self->parse_line($_);
        }
    }
    
    $self->check_for_repeated_clone_names_and_accessions;
    
    my $err = $errors{$self};
    my $tpf =    $tpf{$self};

    # Empty parser ready for possible re-use
    $self->clear_data;

    if ($err) {
        die "Error parsing TPF:\n", $err;
    }

    return $tpf;
}

{
    my %bio_gap_type = (CENTROMERE      => 5,
                        HETEROCHROMATIN => 6,
                        'SHORT-ARM'     => 7,
                        TELOMERE        => 8,
                        'CENTROMERE_DATA_START' => 9,
                        'CENTROMERE_DATA_END' =>   10,
                        'HETEROCHROMATIN_DATA_START' => 11,
                        'HETEROCHROMATIN_DATA_END' =>   12,
                       );
    sub parse_line {
        my ($self, $line_str) = @_;

        if ($line_str =~ s/^#+//) {
            $self->parse_comment_line($line_str);
            return;
        }
        elsif ($line_str =~ /^\s/) {
            $errors{$self} .= "Bad line in TPF: '$line_str'\n";
        }

        my @line = split /\s+/, $line_str, 4;
        unless (@line >= 2) {
            # GAP lines don't need to give a length, so can be 2 fields long
            $errors{$self} .= "Bad line in TPF: '$line_str'\n" unless @line >= 2;
        }

        my( $row );
        if ($line[0] =~ /GAP/i) {
            my ($type_str, $length_str, $remark) = @line[1..3];
            $row = Hum::TPF::Row::Gap->new;
            if ($type_str =~ /type-([1234])/i) {
                $row->type($1);
            }
            elsif (my $n = $bio_gap_type{uc $type_str}) {
                $row->type($n);
            }
            else {
                $errors{$self} .= "Can't parse gap type from '$type_str'\n";
            }
            if ($length_str and $length_str =~ /(\d+)/) {
                $row->gap_length($1);
            }
            $row->remark($remark);
        } else {
            my ($acc, $intl, $contig_name, $remark) = @line;

            if ($acc eq '?' and $intl eq '?') {
                $errors{$self} .= "Bad TPF line (accession and clone are both blank): '$line_str'\n";
            }
            elsif ($intl =~ /type/i) {
                $errors{$self} .= "Bad TPF gap line: $_\nGap lines must begin with 'GAP'\n";
            }
            if ($acc ne '?') {

                if ($acc =~ /\.\d+$/ ) {
                    $errors{$self} .= "ACC.SV not permitted in TPF files: '$line_str'\n"
                }

                $uniq_accession{$self}{$acc}++;
            }
            $row = Hum::TPF::Row::Clone->new;
            $row->accession($acc);
            if ($intl =~ /MULTIPLE/i) {
                $row->is_multi_clone(1);
                $row->sanger_clone_name($acc);
            }
            # Handle missing overlong clone-names differently
            elsif($intl eq '???') {
                $row->sanger_clone_name($acc);
                $uniq_clone{$self}{$acc}++;
            }
            else {
                if ($intl !~ /^\?+$/) {
                    $uniq_clone{$self}{$intl}++;
                }
                $row->intl_clone_name($intl);
            }
            $row->contig_name($contig_name);
            $row->remark($remark);
        }

        $tpf{$self}->add_Row($row);
    }
}

sub check_for_repeated_clone_names_and_accessions {
    my ($self) = @_;
    
    foreach my $intl (sort {ace_sort($a, $b)} keys %{$uniq_clone{$self}}) {
        my $count = $uniq_clone{$self}{$intl};
        if ($count > 1) {
            $errors{$self} .= "Clone name '$intl' occurs $count times in TPF\n";
        }
    }
    
    foreach my $acc (sort {ace_sort($a, $b)} keys %{$uniq_accession{$self}}) {
        my $count = $uniq_accession{$self}{$acc};
        if ($count > 1) {
            $errors{$self} .= "Accession '$acc' occurs $count times in TPF\n";
        }
    }
}

{
    my %accepted_field = map {$_, 1} qw{
        species chromosome subregion
        };

    sub parse_comment_line {
        my( $self, $line ) = @_;

        while ($line =~ /([^\s=]+)=([^\s=]+)/g) {
            my $field = $1;
            my $value = $2;
            if ($accepted_field{$field}) {
                $tpf{$self}->$field($value);
            } else {
                warn "Unrecognized field in TPF header: '$field=$value'\n";
            }
        }
    }
}

1;

__END__

=head1 NAME - Hum::TPF::Parser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

