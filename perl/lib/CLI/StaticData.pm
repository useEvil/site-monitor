# ----------------------------------------------------------------- #
# package CLI::StaticData
# StaticData.pm
# ----------------------------
# $Revision: 1.4 $
# $Date: 2003/01/22 00:56:51 $
# ----------------------------------------------------------------- #
# DESCRIPTION OF FILE
#	StaticData.pm,  Application class for Command Line scripts.
# ----------------------------------------------------------------- #
package CLI::StaticData;

=head1 NAME

CLI::StaticData

=head1 SYNOPSIS

 use CLI::StaticData;
 CLI::StaticData->init( '/path/to/static/data/info.yaml' );
 my $value	= CLI::StaticData::Category->get_data( @args );
 my $data	= CLI::StaticData::Category->get_data(  );

=head1 DESCRIPTION

Thin Database Abstraction Class for Static Data.

CLI::StaticData is a thin database abstraction class for Static Data. 
Using information about database procs from a YAML metadata file, subclasses of 
CLI::Data are generated for each proc. Objects representing the rows 
returned by these procs may be accessed using the C<get_data> methods.

=head1 REQUIRES

 use Gandolfini::StaticData;
 use YAML qw(LoadFile);

=head1 EXPORTS

Nothing

=cut

use strict;
use warnings;
use Carp qw(croak);
use base qw(Gandolfini::StaticData);

our ($VERSION, @ISA, $verbose);
use constant DEBUG_NONE		=> $ISA[0]->DEBUG_NONE;
use constant DEBUG_WARN		=> 0b00000001;
use constant DEBUG_DUMPER	=> 0b00000010;
use constant DEBUG_TRACE	=> 0b00000100;
use constant DEBUG_INIT		=> 0b00001000;
use constant DEBUG_DBI		=> 0b00010000;
use constant DEBUG_SUBCLASS	=> 0b00100000;
use constant DEBUG_TEST		=> 0b01000000;
use constant DEBUG_ALL		=> 0b01111111;
use constant DEBUG			=> DEBUG_NONE;# | DEBUG_WARN | DEBUG_DUMPER | DEBUG_TRACE | DEBUG_INIT | DEBUG_DBI | DEBUG_SUBCLASS | DEBUG_TEST | DEBUG_ALL;

######################################################################

BEGIN {
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 1.13 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
	$verbose	= 1;
}

######################################################################

sub CONSTRUCTORS { }

=head1 METHODS

=head2 CONSTRUCTORS

=over 4

=item C<new> (  )

Returns a Static Data Object.

=cut

sub new {
	my $self	= shift;
	my $class	= ref($self) || $self;
	return bless { }, $class;
} # END of new


######################################################################

sub INITIALIZATION_METHODS { }

=back

=head2 INITIALIZATION METHODS

=over 4

=cut


######################################################################

sub ITERATOR_AND_LIST_CONSTRUCTORS { }

=back

=head2 ITERATOR AND LIST CONSTRUCTORS

=over 4

=cut


######################################################################
## PRIVATE INITIALIZATION METHODS

sub PROTECTED_METHODS { }

=back

=head2 PROTECTED METHODS

These methods should only be used by CLI::StaticData subclasses.

=over 4

=cut


######################################################################

sub REVISION_HISTORY { }

1;

__END__

=back

=head1 REVISION HISTORY

 $Log: StaticData.pm,v $

=head1 SEE ALSO

L<perl>

=head1 KNOWN BUGS

None

=head1 AUTHOR

Thai Nguyen <thai@shozilla.com>

=cut
