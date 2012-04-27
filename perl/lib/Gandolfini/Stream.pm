# Gandolfini::Stream
# -------------
# $Revision: 1488 $
# $Date: 2006-10-18 18:22:47 -0700 (Wed, 18 Oct 2006) $
# -----------------------------------------------------------------------------

=head1 NAME

Gandolfini::Data - Thin Database Abstraction Class

=cut

package Gandolfini::Stream;

=head1 SYNOPSIS

 use Gandolfini::Stream;
 my $stream	= Gandolfini::Stream->new( [1,2,3] );
 print $stream->next; # "1"
 $stream->close();

=head1 EXPORTS

Nothing is exported by default. The C<sgrep> function may be exported upon request.

=head1 DESCRIPTION

Data Stream objects are used to iterate the results of a proc call. Stream objects
are blessed into, or inherit from, the L<Gandolfini::Stream|Gandolfini::Stream>
class. All streams may be managed with the C<next()> and C<close()> methods.

=cut

use strict;
use warnings;
use Carp qw(carp);
use Scalar::Util qw/reftype/;

######################################################################

our ($debug, @ISA, @EXPORT_OK);
use constant DEBUG_NONE		=> 0b00000000;

BEGIN {
	$debug		= DEBUG_NONE;
	
	require Exporter;
	@ISA		= qw(Exporter);
	@EXPORT_OK	= qw(sgrep smap);
}


######################################################################

=head1 METHODS

=head2 CONSTRUCTORS

=over 4

=item C<new ( $coderef )>

Returns a new stream object. The code reference argument should return objects
until either there are no objects left on the stream, or until a TRUE value is
passed as an argument. From this point on, the stream should return C<undef>.

=cut
sub new {
	my $class	= shift;
	my $ref		= shift;
	my $count	= undef;
	my $sub;
	if (ref $ref and reftype($ref) eq 'ARRAY') {
		my $rows	= 0;
		my $open	= 1;
		$count		= scalar(@{ $ref });
		$sub	= sub {
			$open	= 0 if (@_);
			return undef unless ($open);
			my $data = shift(@{ $ref });
			return $data;
		};
	} elsif (ref $ref and reftype($ref) eq 'CODE') {
		$sub	= $ref;
	} else {
		carp "Don't know how to make a Stream object from $ref!";
		return undef;
	}
	
	my $self	= {
					code	=> $sub,
					peek	=> undef,
					count	=> $count,
					'open'	=> 1
				};
	return bless( $self, $class );
}

=item C<concat ($stream)>

=item C<concat ($stream, $stream)>

Concatinates two streams. If called as an object method, appends the passed
stream onto the end of the current stream. If called as a class method,
concatinates the two passed streams, and returns a new stream object.

=cut

sub concat {
	my $proto	= shift;
	my $class	= ref($proto) || $proto;
	my $stream1	= (ref($proto)) ? $class->new( delete $proto->{'code'} ) : shift;
	my $stream2	= shift;
	my $open	= 1;
	my $code	= sub {
		$open	= 0 if (@_);
		return undef unless ($open);
		my $data = $stream1->next() || $stream2->next();
		return $data;
	};
	
	my $new	= $class->new( $code );
	if (ref($proto)) {
		%{ $proto }	= %{ $new };	# evil (but it keeps the logic of construction in C<new>
	}
	return $new;
}

=back

=head2 STREAM METHODS

=over 4

=item C<next>

Returns the next object from the stream. If the stream is empty, or if the
stream has been C<close>d, returns C<undef>.

=cut

sub next {
	my $self	= shift;
	if (defined($self->{'peek'})) {
		return delete($self->{'peek'});
	} else {
		if ($self->{'open'}) {
			return $self->{'code'}->();
		} else {
			return undef;
		}
	}
}

=item C<get ( $count )>

Returns an array reference of the first $count elements from the stream.

=cut

sub get {
	my $self	= shift;
	my $count	= shift;
	my @data	= ($count > 0) ? map { $self->next() } (1 .. $count) : ();
	return \@data;
}

=item C<peek>

Returns the current object at the front of the stream, without removing it.

=cut

sub peek {
	my $self	= shift;
	if (defined($self->{'peek'})) {
		return $self->{'peek'};
	} else {
		if ($self->{'open'}) {
			return ($self->{'peek'} = $self->next());
		} else {
			return undef;
		}
	}
}

=item C<count>

Returns the maximum number of elements the stream contained since construction.

If the stream is based on a closure (and not an array), using this method will
incur a large memory hit. Be careful.

=cut

sub count {
	my $self	= shift;
	my $class	= ref($self);
	if (defined($self->{'count'})) {	# pray you take this branch... the other one is nasty
		return $self->{'count'};
	} else {
		my @data;
		while (my $data	= $self->next()) {	# spiiiiiiiin
			push(@data, $data);
		}
		my $new	= $class->new( \@data );
		%{ $self }	= %{ $new };	# more evilness
		return scalar(@data);
	}
}

=item C<skip ( $count )>

Skips the first $count elements on the stream.

=cut

sub skip {
	my $self	= shift;
	my $count	= shift;
	if ($count > 0) {
		$self->next() for (1 .. $count);
	}
}

=item C<close>

Closes the stream. Subsequent calls to C<next()> will return C<undef>.

=cut

sub close {
	my $self	= shift;
	$self->{'open'}	= 0;
	$self->{'peek'}	= undef;
	$self->{'code'}->( 1 );
	return;
}

=back

=head1 FUNCTIONS

=over 4

=item C<sgrep { COND } $stream>

Similar to the C<grep> builtin, returns a new stream which will return only
elements that satisfy the conditional code block. The code block may reference
each passed element as C<$_>, and MUST return a boolean value signifying
the elements inclusion in the final results stream.

 use Gandolfini::Stream qw( sgrep );
 $stream = Gandolfini::Stream->new( [ 1 .. 10 ] );
 $odds = sgrep { $_ % 2 } $stream;
 $evens	= sgrep { $_ % 2 == 0 } $stream;

=cut

sub sgrep (&$) {
	my $block	= shift;
	my $stream	= shift;
	my $class	= ref($stream);
	
	my $open	= 1;
	my $next;
	
	$next	= sub {
		return undef unless ($open);
		my $data	= $stream->next;
		unless ($data) {
			$open	= 0;
			return undef;
		}
		
		local($_)	= $data;
		if ($block->( $data )) {
			if (@_ and $_[0]) {
				$stream->close;
				$open	= 0;
			}
			return $data;
		} else {
			goto &$next;
		}
	};
	
	return $class->new( $next );
}

sub smap (&$) {
	my $block	= shift;
	my $stream	= shift;
	my $class	= ref($stream);
	
	my $open	= 1;
	my $next	= sub {
		return undef unless ($open);
		if (@_ and $_[0]) {
			$stream->close;
			$open	= 0;
		}
		my $data	= $stream->next;
		unless ($data) {
			$open	= 0;
			return undef;
		}
		
		local($_)	= $data;
		my ($item)	= $block->( $data );
		return $item;
	};
	
	return $class->new( $next );
}

1;

__END__

=back

=head1 REVISION HISTORY

 $Log$
 Revision 1.4  2005/08/31 04:22:14  gwilliams
 - added smap function
 - sgrep now closes enclosed stream

 Revision 1.3  2005/07/25 19:21:16  gwilliams
 - Added exportable sgrep function for grepping stream elements.

 Revision 1.2  2004/02/12 23:44:33  gwilliams
 - added get() method to return an array reference of N elements
 - added skip() method to skip N elements from head of stream
 - POD updates

 Revision 1.1  2004/02/10 00:30:42  gwilliams
 - moved Stream code into Gandolfini/Stream.pm (from Gandolfini/Data.pm)
 - added Stream tests


=head1 KNOWN BUGS

None

=head1 TO DO

None

=back

=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut
