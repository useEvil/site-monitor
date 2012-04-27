# Gandolfini::Args
# -------------
# $Revision: 1906 $
# $Date: 2008-05-07 12:59:20 -0700 (Wed, 07 May 2008) $
# -----------------------------------------------------------------------------

=head1 NAME

Gandolfini::Args - Request arguments class

=cut

package Gandolfini::Args;

=head1 SYNOPSIS

 my $args = new Gandolfini::Args ( [ \%args ] );
 my $value = $args->get( 'field' );
 my $array = $args->get_array( 'field' );
 my $hash = $args->get_hash(  );
 my $hash = $args->get_hash( with => \@fields );
 my $hash = $args->get_hash( without => \@fields );

=head1 DESCRIPTION

Abstracts access to request arguments.

=cut

use strict;
use Carp;
use URI::Escape qw(uri_escape uri_unescape);
use Scalar::Util qw/reftype/;
use warnings;
no warnings 'redefine';

######################################################################

our ($debug);
use constant DEBUG_NONE		=> 0b00000000;

BEGIN {
	$debug		= DEBUG_NONE;
}

######################################################################

=head1 METHODS

=head2 CONSTRUCTORS

=over 4

=item C<new> ( [ \%args ] )

Returns a new args object with the specified arguments.

=cut

sub new {
	my $proto	= shift;
	my $class	= ref($proto) || $proto;
	my $args	= shift;
	return undef unless (ref $args and reftype($args) eq 'HASH');
	return bless( { args => $args }, $class );
} # END of new

=item C<get> ( $field )

Returns the value(s) of the $field argument. If $field has multiple values, returns
an ARRAY reference, otherwise returns a simple SCALAR.

=cut

sub get {
	my $self	= shift;
	my $field	= shift || return undef;
	return $self->_args->{ $field };
} # END of get

=item C<get_array> ( $field )

Returns the value(s) of the $field argument as an ARRAY reference.

=cut

sub get_array {
	my $self	= shift;
	my $field	= shift;
	my $data	= $self->_args->{ $field };
	if (ref $data and reftype($data) eq 'ARRAY') {
		return $data;

	# changed this to defined so that 0 as an arg will be accepted
	# who knows what the ramifications of this will be
	# but zero should be accepted as a valid arg, anyway
	} elsif (defined($data)) {
		return [ $data ];

	} else {
		return [ ];
	}
} # END of get_array

=item C<get_hash> (  )

=item C<get_hash> ( with => \@fields )

=item C<get_hash> ( without => \@fields )

Returns a HASH reference containing arguments. Multi-valued arguments are
stored as ARRAY references. If called with no options, all arguments are
returned. If called with C<with => \@fields>, returns only those arguments
named in C<@fields>. If called with C<without => \@fields>, returns only
arguments that do not appear in C<@fields>.

=cut

sub get_hash {
	my $self	= shift;
	if (@_) {
		my $op		= shift;
		my $data	= shift;
		unless (ref $data and reftype($data) eq 'ARRAY') {
			# use carp to show where errant caller code is
			carp("Not an ARRAY reference as second argument to get_hash");
			return undef;
		}
		
		my %map		= map { $_ => 1 } @{ $data };
		my $args	= $self->_args;
		
		if ($op eq 'with') {
			return { map { $_ => $args->{ $_ } } grep { $map{ $_ } } keys %{ $args } };
		} elsif ($op eq 'without') {
			return { map { $_ => $args->{ $_ } } grep { !$map{ $_ } } keys %{ $args } };
		} else {
			carp("Unrecognized argument '$op' to get_hash");
			return undef;
		}
	} else {
		return { %{ $self->_args } };
	}
} # END of get_hash


=item C<get_deleted_hash> (  )

Returns a HASH reference containing arguments that have been deleted from the
original arguments with C<delete_fields>

=cut

sub get_deleted_hash {
    my $self = shift;
    return { %{ $self->_deleted } };
}

=item C<params> (  )

Returns the keys of the args list as a array or arrary ref.

=cut

sub params {
	my $self	= shift;
	return wantarray ? sort keys %{ $self->_args } : [ sort keys %{ $self->_args } ];
} # END of params

=item C<escape> ( $name, $value [, $params ] )

Returns the value escaped using uri_escape.

=cut

sub escape {
	my $self	= shift;
	my $name	= shift;
	my $value	= shift;
	my $param	= shift || "^a-zA-Z0-9\-_";
	
	return uri_escape( $value, $param) if ($value);
	return uri_escape( $self->get($name), $param );
} # END of escape

=item C<unescape> ( $name, $value )

Returns the value escaped using uri_escape. This method should be deprecated,
but it's called in so many places, that we should gradually phase it out.

=cut

sub unescape {
	my $self	= shift;
	my $name	= shift;
	my $value	= shift;
	#--------------------------------------------------
	# Carp::carp("Deprecated method... args should be unescaped by Translator.pm ... use args->get");
	# my $unescaped;
	#-------------------------------------------------- 
	if ($value) {
	    return($value);
	    #--------------------------------------------------
	    # $value =~ s/\+/ /g; #Hack to unescape '+' as spaces since URI::Escape doesn't handle this.
	    # $unescaped = uri_unescape( $value ) if ($value);
	    #-------------------------------------------------- 
	} else {
	    $value = $self->get( $name ) || '';
	    return($value);
	    #--------------------------------------------------
	    # $value =~ s/\+/ /g; #Hack to unescape '+' as spaces since URI::Escape doesn't handle this.
	    # $unescaped = uri_unescape( $value ); 
	    #-------------------------------------------------- 
	}

	#--------------------------------------------------
	# #sometimes $value is escaped twice "kate%2520spade" 
	# #so first unescape will produce "kate%20spade" and second unescape will produce "kate spade"
	# $unescaped = uri_unescape( $unescaped );
	# return $unescaped;
	#-------------------------------------------------- 
} # END of unescape

=item C<param> ( $field )

Forwards to the get method.

=cut

sub param {
	my $self	= shift;
	warn __PACKAGE__ . '->param has been deprecated, please use the get() method;' . join(';', caller()) . "\n";
	return $self->get( @_ );
} # END of param

=item C<delete_fields> ( \@field_names )

Delete the named fields from the arguments

=cut

sub delete_fields {
    my $self = shift;
    my $fields = shift;
    my $args_hash = $self->_args;
    my @fields = grep { exists $args_hash->{$_} } @$fields
      or return;
    my $deleted_hash = $self->_deleted;
    @{ $deleted_hash }{ @fields } = delete @{ $args_hash }{ @fields };
}

sub _args {
	return shift->{'args'};
} # END of _args

sub _deleted {
	return shift->{'deleted'} ||= {};
}

1;

__END__

=back

=head1 REVISION HISTORY

 $Log$
 Revision 1.15  2005/03/14 21:36:27  aelliston
 Last fix. Sorry.

 Revision 1.14  2005/03/14 21:33:53  aelliston
 Another stupid edit.

 DEV#2023

 Revision 1.13  2005/03/14 21:32:34  aelliston
 Oops fixed carp warning.

 DEV#2023

 Revision 1.12  2005/03/14 21:28:15  aelliston
 Deprecated method unescape. Can't remove it because it is called in too many places, but
 it should be removed eventually because Translator escapes all args before building this
 class.

 DEV#2023

 Revision 1.11  2005/03/11 03:18:14  aelliston
 Changed get_array such that it will return an array even if the arg = 0 because sfsk=0 is
 still an arg, eventhough it evaluates to false, ShopzillaLink was stripping off this arg
 since nothing was returned by get_array

 DEV#1904

 Revision 1.10  2004/09/21 20:05:01  draminiak
 return undef if no args passed into "get" method

 Revision 1.9  2004/09/11 19:44:09  urathod
 $value is uri_unescaped twice in unescape() method

 Revision 1.8  2004/05/22 01:47:53  mhynes
 make sure get array returns an array

 Revision 1.7  2004/05/13 23:34:48  mhynes
 fixed initialized warning

 Revision 1.6  2004/05/13 22:53:51  mhynes
 added hack to unescape to remove the '+' when it is used as a space

 Revision 1.5  2004/04/29 17:20:56  thai
  - removed set() and remove() methods

 Revision 1.4  2004/04/26 21:43:08  thai
  - added set(), remove(), params() and a fowarder for param() methods

 Revision 1.3  2004/04/09 22:47:16  thai
  - added escape() and unescape() methods

 Revision 1.2  2004/02/24 23:27:15  gwilliams
 - added POD

 Revision 1.1  2004/02/23 23:28:11  gwilliams
 - added Gandolfini::Args class and tests


=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut
