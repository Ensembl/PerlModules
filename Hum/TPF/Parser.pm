
### Hum::TPF::Parser

package Hum::TPF::Parser;

use strict;
use warnings;
use Carp;
use Hum::TPF;
use Symbol 'gensym';

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub file {
    my( $self, $file ) = @_;
    
    if ($file) {
        my $type = ref($file);
        unless ($type and $type eq 'GLOB') {
            my $fh = gensym();
            open $fh, $file or confess "Can't read '$file' : $!";
            $file = $fh;
        }
        $self->{'_file'} = $file;
    }
    return $self->{'_file'};
}

sub parse {
    my( $self, $str ) = @_;

    local $/ = "\n";
    my $tpf = Hum::TPF->new;

    if ($str) {
        if ($self->{'_file'}) {
            confess "string argument given, but filehandle defined too!";
        }
        while ($str =~ /^(.+)$/mg) {
            # Pattern match automatically skips blank lines
            $self->parse_line($tpf, $1);
        }
    } else {
        my $fh = $self->file or confess "file not set";
        while (<$fh>) {
            chomp;
            next if /^$/;
            $self->parse_line($tpf, $_);
        }
    }

    # Empty parser for re-use
    $self->{'_file'}            = undef;
    $self->{'_uniq_clone'}      = undef;
    $self->{'_uniq_accession'}  = undef;

    return $tpf;
}

{
    my %bio_gap_type = (CENTROMERE      => 5,
                        HETEROCHROMATIN => 6,
                        'SHORT-ARM'     => 7,
                        TELOMERE        => 8
                       );
    sub parse_line {
        my ($self, $tpf, $line_str) = @_;

        if ($line_str =~ /^#/) {
            $self->parse_comment_line($tpf, $line_str);
            return;
        }
        if ($line_str =~ /^\s/){
          return;
        }

        my @line = split /\s+/, $line_str, 4;

        #confess "Bad line in TPF: $_" unless @line >= 3;
        # now this is allowed
        confess "Bad line in TPF: $line_str" unless @line >= 2;

        my( $row );
        if ($line[0] =~ /GAP/i) {
            my $identifier = uc $1;
            my( $type_str, $length_str, $method, $remark ) = @line[1..4];
            $row = Hum::TPF::Row::Gap->new;
            if ($type_str =~ /type-([1234])/i ){
                $row->type($1);
            }
            elsif ( $bio_gap_type{uc($type_str)} ){
              $row->type($bio_gap_type{uc($type_str)});
            }
            else {
                confess "Can't parse gap type from '$type_str'";
            }
            if ($length_str =~ /(\d+)/) {
                $row->gap_length($1);
                #confess "GAP length given but no method is specified" unless $method;
                #$row->method($method);
            }
            $row->remark($remark);
        } else {
            my( $acc, $intl, $contig_name ) = @line;

            if ($acc eq '?' and $acc eq $intl) {
                die "Bad TPF line (accession and clone are both blank): $line_str\n";
            }
            elsif ($intl =~ /type/i) {
                die "Bad TPF gap line: $_\nGap lines must begin with 'GAP'\n";
            }
            if ($acc ne '?') {

              # prevent loading with acc.sv
              if ($acc =~ /(.*)\.\d+/ ){
                $acc = $1;
              }

                die "Accession '$acc' appears twice in TPF\n"
                    if $self->{'_uniq_accession'}{$acc};
                $self->{'_uniq_accession'}{$acc}++;
            }
            $row = Hum::TPF::Row::Clone->new;
            $row->accession($acc);
            if ($intl =~ /MULTIPLE/i) {
                $row->is_multi_clone(1);
                $row->sanger_clone_name($acc);
            } else {
                if ($intl ne '?') {
                    die "Clone name '$intl' appears twice in TPF\n"
                        if $self->{'_uniq_clone'}{$intl};
                    $self->{'_uniq_clone'}{$intl}++;
                }
                $row->intl_clone_name($intl);
            }
            $row->contig_name($contig_name);
            $row->remark($line[3]);
        }

        $tpf->add_Row($row);
    }
}


{
    my %accepted_field = map {$_, 1} qw{
        species chromosome subregion
        };

    sub parse_comment_line {
        my( $self, $tpf, $line ) = @_;

        while ($line =~ /(\S+)=(\S+)/g) {
            my $field = $1;
            my $value = $2;
            if ($accepted_field{$field}) {
                $tpf->$field($value);
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

