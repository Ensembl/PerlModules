package Hum::CloneConverter;

### Author: jt8@sanger.ac.uk

use vars qw{ @ISA @EXPORT_OK };
use Hum::Tracking qw(clone_from_project prepare_track_statement clone_from_accession);
use strict;
use warnings;

@ISA = ('Exporter');
@EXPORT_OK = qw(
    convert
    internal2external
    external2internal
    accession2internal
    accession2external
    internal2accession
    external2accession
);

sub convert {
    my ($input_name, $input_format, $output_format) = @_;
    
    my @valid_formats = qw(external internal accession);
    my %is_valid_format = map {$_=>1} @valid_formats;
    
    if(
        !exists($is_valid_format{$input_format})
        or !exists($is_valid_format{$output_format})
    ) {
        die "The only valid formats are " . join(', ', @valid_formats) . "\n";
    }
    
    my $conversion_subroutine = $input_format . '2' . $output_format;
    no strict 'refs';
    if(defined(&$conversion_subroutine)) {
        return &$conversion_subroutine($input_name);
    }
    else {
        die "Cannot convert from $input_format to $output_format\n";
    }
}

sub accession2internal {
    my ($accession) = @_;
    return clone_from_accession($accession);
}

{
    my ($get_accession);

    sub internal2accession {
        my ($internal) = @_;

        $get_accession ||= prepare_track_statement(
            q{
            SELECT s.accession
            FROM sequence s
              , clone_sequence cs
            WHERE s.id_sequence = cs.id_sequence
              AND cs.is_current = 1
              AND cs.clonename = ?
            }
        );
        $get_accession->execute($internal);

        if (my ($accession) = $get_accession->fetchrow) {
            return $accession;
        }
        else {
            return;
        }
    }
}


sub accession2external {
    my ($accession) = @_;
    return internal2external(accession2internal($accession));
}

sub external2accession {
    my ($external) = @_;
    return internal2accession(external2internal($external));
}

our $international_name_sth;
sub internal2external {
	my ($sanger_name) = @_;
	
	if(!defined($international_name_sth)) {
		my $sql = q{
        	SELECT 
        	  l.internal_prefix
        	  , l.external_prefix
        	FROM
        	  clone c
        	  , library l
        	WHERE
        	  c.libraryname = l.libraryname
        	  AND c.clonename=?
        	};
		$international_name_sth = prepare_track_statement($sql);
	}

	my ($international_name, $stem);

    $international_name_sth->execute($sanger_name);
    my $library_result_ref = $international_name_sth->fetchrow_arrayref;
    if(defined($library_result_ref) and ref($library_result_ref) eq 'ARRAY' and scalar(@$library_result_ref) == 2) {
    	my($int_pre, $ext_pre) = @$library_result_ref;
		($international_name, $stem) = set_intl_clone_name_from_sanger_int_ext($sanger_name, $int_pre, $ext_pre);
    } 

	return ($international_name);	
}

sub set_intl_clone_name_from_sanger_int_ext {
    my($clonename, $int_pre, $ext_pre ) = @_;

    $clonename = uc $clonename;
    $int_pre ||= '';
    $ext_pre ||= '';
	my $stem;
    if ($ext_pre =~ /^XX/ or $int_pre eq 'NONE') {
		$stem = $clonename;
        $clonename = "$ext_pre-$clonename";
    }
    elsif ($ext_pre) {
		$stem = substr($clonename, length($int_pre));
        substr($clonename, 0, length($int_pre)) = "$ext_pre-";
    }
    return ($clonename, $stem);
}

sub external2internal {
    my ($external) = @_;
    my ($internal, $library) = get_sanger_clone_and_libraryname_from_intl_name($external);
    return $internal;
}

{
    my( %intl_sanger, %sanger_info );
    my $init_flag = 0;
    
    sub _init_prefix_hash {
        my $sth = prepare_track_statement(q{
            SELECT libraryname
              , internal_prefix
              , external_prefix
              , first_plate
              , last_plate
            FROM library
            ORDER BY libraryname
              , first_plate
            });
        $sth->execute;
        my( $libname, $sang, $intl, $first, $last );
        $sth->bind_columns(\$libname, \$sang, \$intl, \$first, \$last);
        while ($sth->fetch) {
            next unless $sang and $intl;
			if($sang eq 'NONE') {$sang = ''}
            if ($intl =~ /^XX/) {
                my $uc_sang = uc $sang;
                if ($sanger_info{$uc_sang}) {
                    # If more than one XX* library shares a Sanger prefix, we can't use it.
                    delete($sanger_info{$uc_sang});
                } else {
                    $sanger_info{$uc_sang} = [$sang, $libname];
                }
            } else {
                my $lib_info = $intl_sanger{$intl} ||= [];
                push(@$lib_info, [$sang, $libname, $first, $last]);
            }
        }
        $init_flag = 1;
    }
    
    sub get_sanger_clone_and_libraryname_from_intl_name {
        my( $intl ) = @_;
        
        _init_prefix_hash() unless $init_flag;
        
        ### Tread XX* clones differently - should be able
        ### to just knock off the XX- prefix, but make an
        ### attempt to identify the library from the start
        ### of the remaining name.
        if (defined($intl) and $intl =~ /^XX.*-(.+)/) {
            my $rest = $1;
            if (my ($prefix) = $rest =~ /^([A-Za-z]+)/) {
                if (my $info = $sanger_info{uc $prefix}) {
                    my ($sanger, $libname) = @$info;
                    substr($rest, 0, length($sanger)) = $sanger;
                    return($rest, $libname);
                }
            }
            return $rest;
        } else {

            my ($intl_prefix, $plate, $rest);
            if(defined($intl)) {($intl_prefix, $plate, $rest) = $intl =~ /^([^-]+)-(\d*)(.+)$/;}
            $intl_prefix ||= '';
            $plate       ||= '';
            if(!defined($intl)) {$intl = ''};
            if(!defined($rest)) {$rest = $intl};
            if (my $lib_info = $intl_sanger{$intl_prefix}) {
                if ($plate) {
                    foreach my $inf (@$lib_info) {
                        my ($sang, $libname, $first, $last) = @$inf;
                        if ($plate >= $first and $plate <= $last) {
                            return($sang . $plate . $rest, $libname);
                        }
                    }
                    warn "Couldn't place plate from '$intl' in any of:\n",
                        map "  [@$_]\n", @$lib_info;
                }
                # Just take the first
                my ($sang, $libname) = @{$lib_info->[0]};
                return($sang . $plate . $rest, $libname);
            } else {
                return($plate . $rest);
            }
        }
    }
}


    my $sql;
    sub USE_AS_ORACLE_TEMPLATE {
        my ($acc) = @_;
     
        if(!defined($sql)) {   
            my $dbi;
            
            eval {
              $dbi = WrapDBI->connect('reports',{RaiseError => 1});
              $dbi->{autocommit} = 0;
            };
            
            if($@) {
              die"ERROR: Unable to connect to oracle.$@\n";
            }
            
            $sql = $dbi->prepare(qq[
            			   SELECT A.PROJECTNAME
            			   FROM FINISHED_SUBMISSION A
            			   WHERE A.ACCESSION = ?
            			   UNION
                                       SELECT B.PROJECTNAME
                                       FROM UNFINISHED_SUBMISSION B
                                       WHERE B.ACCESSION = ?
                                       ]);
        }
        
        $sql->execute($acc,$acc);
        my ($accession) = $sql->fetchall_arrayref;
        
        if (scalar @$accession != 1){
            warn "No unique project obtained for $acc\n";
            return undef;
        }
        else{
            return $accession->[0][0];
        }
    }

1;

__END__

=head1 AUTHOR

James Torrance email B<jt8@sanger.ac.uk>

