# ----------------------------------------------------------------- #
# package CLI::Data
# Data.pm
# ----------------------------
# $Revision: 1.6 $
# $Date: 2005/07/15 18:00:52 $
# ----------------------------------------------------------------- #
# DESCRIPTION OF FILE
#	Data.pm,  Data class for Command Line scripts.
# ----------------------------------------------------------------- #
package CLI::Data;

=head1 NAME

CLI

=head1 SYNOPSIS
 
=head1 DESCRIPTION

=head1 REQUIRES

 use strict;
 use CLI::Environment;
 use CLI::Configuration;
 use CLI::Data;
 use DirHandle;
 use File::stat;
 use Term::ReadLine;
 use Gandolfini::Date;

=cut

use strict;
use warnings;
use Carp qw(croak carp);
use base qw(Gandolfini::Data);

######################################################################

our ($VERSION, @ISA, $verbose, %database_set);
use constant DEBUG_NONE		=> $ISA[0]->DEBUG;
use constant DEBUG_WARN		=> 0b00000001;
use constant DEBUG_DUMPER	=> 0b00000010;
use constant DEBUG_TRACE	=> 0b00000100;
use constant DEBUG_INIT		=> 0b00001000;
use constant DEBUG_DBI		=> 0b00010000;
use constant DEBUG_SUBCLASS	=> 0b00100000;
use constant DEBUG_TEST		=> 0b01000000;
use constant DEBUG_ALL		=> 0b01111111;
use constant DEBUG			=> DEBUG_NONE;# | DEBUG_WARN | DEBUG_DUMPER | DEBUG_TRACE | DEBUG_INIT | DEBUG_DBI | DEBUG_SUBCLASS | DEBUG_TEST | DEBUG_ALL;

BEGIN {
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 1.6 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
	$verbose	= 0;
}

##### THIS IS FOR DBIx::HA INTEGRATION ###############################
*database_set = *DATABASE::conf;
######################################################################

######################################################################
## CONSTRUCTORS

sub CONSTRUCTORS { }

=head1 METHODS

=head2 CONSTRUCTORS

=over 4

=item C<new> (  )

Returns a new Data Object.

=cut

sub new {
	my $self	= shift;
	my $class	= ref($self) || $self;
	return bless { }, $class;
} # END of new


######################################################################
## INITIALIZATION METHODS

sub INITIALIZATION_METHODS { }

=back

=head2 INITIALIZATION METHODS

=over 4

=cut


######################################################################
## ITERATOR AND LIST CONSTRUCTORS

sub ITERATOR_AND_LIST_CONSTRUCTORS { }

=back

=head2 ITERATOR AND LIST CONSTRUCTORS

=over 4

=cut


######################################################################
## OBJECT METHODS

sub OBJECT_METHODS { }

=back

=head2 OBJECT METHODS

=over 4

=item C<row> (  )

Returns the row count.

=cut

sub row {
	my $self = shift;
	return 0 unless (ref $self);
	return $self->{'_row'} + 1;
} # END of row


######################################################################
## PROTECTED ACCESSORS

sub PROTECTED_METHODS { }

=back

=head2 PROTECTED METHODS

These methods should only be used by Gandolfini::Data subclasses.

=over 4

=item C<_cols_order ( [ $col ] )>

Returns a LIST of column names in order.

=cut

sub _cols_order {
	my $proto	= shift;
	return $proto->__cols_order( @_ );
}


=item C<_non_persistent (  )>

Returns true or false if the db connection should be non-persistent.

=cut

sub _non_persistent {
	my $proto	= shift;
	if ($proto->can('_name') && ($proto->_name =~ /^iq_\w+/o)) {
#		warn "IQ CONNECTIONS ARE NON-PERSISTENT: " . $proto->_name . "\n";
		return 1;
	} else {
		return $proto->SUPER::_non_persistent;
	}
}


######################################################################
## ATTRIBUTES

sub ATTRIBUTES { }

=back

=head1 ATTRIBUTES

=over 4

=cut


######################################################################
## REVISION HISTORY

sub REVISION_HISTORY { }

1;

__END__


=back

=head1 REVISION HISTORY

 $Log: Data.pm,v $

=head1 SEE ALSO

L<perl>

=head1 KNOWN BUGS

None

=head1 AUTHOR

Thai Nguyen <thai@shozilla.com>

=cut
