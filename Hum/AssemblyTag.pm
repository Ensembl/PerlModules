=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


### Hum::AssemblyTag

package Hum::AssemblyTag;

use strict;
use warnings;
use Carp;

sub new {
    my ($pkg, $arg_ref) = @_;

	my @required_variables = qw(start end type component);
	my @optional_variables = qw(comment dbi);

	foreach my $required_variable (@required_variables) {
		if(!exists($arg_ref->{$required_variable})) {
			die "$required_variable required for $pkg\n";
		}
	}

	my $self = {};
	foreach my $variable (@required_variables, @optional_variables) {
		if(exists($arg_ref->{$variable})) {
			$self->{uc($variable)} = $arg_ref->{$variable};
		}
		else {
			$self->{uc($variable)} = '';
		}
	}

    return bless $self, $pkg;
}

sub start {
	my ($self) = @_;
	
	return $self->{START};
}

sub end {
	my ($self) = @_;
	
	return $self->{END};
}

sub type {
	my ($self) = @_;
	
	return $self->{TYPE};
}

sub comment {
	my ($self) = @_;
	
	return $self->{COMMENT};
}


sub offset {
	my ($self, $left_coordinate) = @_;
	
	$self->{START} -= ($left_coordinate - 1);
	$self->{END} -= ($left_coordinate - 1);
	
	return;
}

sub flip {
	my ($self, $left_coordinate) = @_;
	
	warn "Flipping coordinates: Not sure if this works, it might be out by 1\n";
	
	my $length = $self->{END} - $self->{START} + 1; 
	
	$self->{START} = $left_coordinate - $self->{START} + 1;
	$self->{END} = $self->{START} + $length - 1;
	
	return;
}

sub tab_separated_output {
	my ($self) = @_;
	
	my $tab_separated_line = join(
		"\t",
		$self->{COMPONENT},
		$self->{START},
		$self->{END},
		$self->{TYPE},
		$self->{COMMENT},
	) . "\n";
	
	return $tab_separated_line;
}

sub old_style_output {
	my ($self) = @_;
	
	return {
		VALUE => $self->{COMMENT},
		START => $self->{START},
		END => $self->{END},
	};
}

1;

__END__

=head1 NAME - Hum::AssemblyTag

=head1 AUTHOR

James Torrance B<email> jt8@sanger.ac.uk

