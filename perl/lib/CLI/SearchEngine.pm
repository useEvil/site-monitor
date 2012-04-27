# ----------------------------------------------------------------- #
# package CLI::SearchEngine
# SearchEngine.pm
# ----------------------------
# $Revision: 1.4 $
# $Date: 2003/01/22 00:56:51 $
# ----------------------------------------------------------------- #
# DESCRIPTION OF FILE
#	SearchEngine.pm,  Search Engine class for Command Line scripts.
# ----------------------------------------------------------------- #
package CLI::SearchEngine;

=head1 NAME

CLI::SearchEngine

=head1 SYNOPSIS

 use CLI::SearchEngine;
 my $search = CLI::SearchEngine->new( );

=head1 DESCRIPTION

The is the super class for the command line interface.

=head1 REQUIRES

 use strict;
 use DeVito::Search::Request::Basic;

=head1 EXPORTS

Nothing

=cut

use strict;
use Data::Dumper;
use Gandolfini::Stream;
use DeVito::Search::UIDInfo;
use DeVito::Search::Request::Basic;


######################################################################

our ($VERSION, $debug);
use constant DEBUG_NONE		=> 0b00000000;
use constant DEBUG_WARN		=> 0b00000001;
use constant DEBUG_DUMPER	=> 0b00000010;
use constant DEBUG_ALL		=> 0b00000111;

BEGIN {
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 1.6 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
	$debug		= DEBUG_NONE;# | DEBUG_WARN | DEBUG_DUMPER | DEBUG_ALL;
}

######################################################################


sub CONSTRUCTORS { }

=head1 METHODS

=head2 CONSTRUCTORS

=over 4

=item C<new> ( $slu_params )

Returns a CLI::SearchEngine object.

=cut

sub new {
	my $self	= shift;
	my $class	= ref($self) || $self;
	my $hash	= shift || { };
	return bless { _slu_params => $hash }, $class;
} # END of new


######################################################################


sub OBJECT_METHODS { }

=head2 OBJECT METHODS

=over 4

=item C<slu_params> ( $slu_params )

Returns or sets the Search Engine parameters.

=cut

sub slu_params {
	my $self	= shift;
	return undef unless (ref $self);
	my $params	= shift;
	$self->{'_slu_params'} = $params if ($params);
	return $self->{'_slu_params'};
} # END of slu_params


=item C<search_result> ( [ $slu_params ] )

Executes the search engine with the given SLU params.

=cut

sub search_result {
	my $self		= shift;
	return undef unless (ref $self);
	my $slu_params	= shift || $self->slu_params;
	my ($search_req, $search_resp, $results);
	warn __PACKAGE__ . '->search_result: ' . Data::Dumper::Dumper( $slu_params ) if ($debug & DEBUG_DUMPER);
	eval {
		local $SIG{__WARN__} = sub { my $err = shift; die if ($err =~ /SLU API ERROR STATE/); };
		$search_req		= DeVito::Search::Request::Basic->new( $slu_params ) || return undef;
		$search_resp	= ref($search_req) ? $search_req->get_response : undef;
		$results		= $search_resp->execute_search if (ref $search_resp);
	};
	return undef if ($@);
	warn __PACKAGE__ . '->search_result: ' . Data::Dumper::Dumper( $search_req, $search_resp, $results ) if ($debug & DEBUG_DUMPER);
	$self->{'_search_resp'}	= $search_resp;
	$self->{'_search_req'}	= $search_req;
	return $results;
} # END of search_result


=item C<search_resp> (  )

Returns the Search Response Object.

=item C<search_req> (  )

Returns the Search Request Object.

=cut

sub search_resp	{ return $_[0]->{'_search_resp'} }
sub search_req	{ return $_[0]->{'_search_req'} }



=item C<stream_product_data> ( [ $slu_params ] )

Returns the Offer data hash.

=cut

sub stream_product_data {
	my $self			= shift;
	return undef unless (ref $self);
	my $slu_params		= shift || $self->slu_params;
	unless ($self->search_resp) {
		$self->search_result( $slu_params );
	}
	my $search_result	= $self->search_resp;
	my $stream			= $search_result->stream_product_data();
	if (ref $stream) {
		return Gandolfini::Stream->new( sub {
			my $data = shift()
				? return (ref($stream) && $stream->close())
				: ((ref($stream) && $stream->next()) || return (undef $stream) );
			return $data;
		} );
	}
	return undef;
} # END of stream_product_data


=item C<stream_offer_data> ( $pid, [ $slu_params ] )

Returns the Offer data hash.

=cut

sub stream_offer_data {
	my $self			= shift;
	return undef unless (ref $self);
	my $pid				= shift || return undef;
	my $slu_params		= shift || $self->slu_params;
	unless ($self->search_resp) {
		$self->search_result( $slu_params );
	}
	my $search_result	= $self->search_resp;
	my $stream			= $search_result->stream_offer_data( $pid );
	if (ref $stream) {
		return Gandolfini::Stream->new( sub {
			my $data = shift()
				? return (ref($stream) && $stream->close())
				: ((ref($stream) && $stream->next()) || return (undef $stream) );
			return $data;
		} );
	}
	return undef;
} # END of stream_offer_data


=item C<stream_attribute_data> ( [ $slu_params ] )

Returns the Attribute data hash.

SLU Params:

 {
	ATT_server	=> [ "sdtcluster01.bizrate.com:7295" ],
	show_attrs	=> [ '259--', '259818--', '265558--', '296935--' ]
 }

=cut

sub stream_attribute_data {
	my $self			= shift;
	return undef unless (ref $self);
	my $slu_params		= shift || $self->slu_params;
	my ($search_result);
	warn __PACKAGE__ . '->search_result: ' . Data::Dumper::Dumper( $slu_params ) if ($debug & DEBUG_DUMPER);
	eval {
		local $SIG{__WARN__} = sub { my $err = shift; die if ($err =~ /API ERROR STATE/); };
		$search_result		= DeVito::Search::AttrInfo->new( $slu_params->{'ATT_server'}, $slu_params->{'show_attrs'} ) || return undef;
	};
	return undef if ($@);
	warn __PACKAGE__ . '->search_result: ' . Data::Dumper::Dumper( $search_result ) if ($debug & DEBUG_DUMPER);
	$self->{'_search_resp'}	= $search_result;
	my $stream				= $search_result->stream_attribute_data;
	if (ref $stream) {
		return Gandolfini::Stream->new( sub {
			my $data = shift()
				? return (ref($stream) && $stream->close())
				: ((ref($stream) && $stream->next()) || return (undef $stream) );
			return $data;
		} );
	}
	return undef;
} # END of stream_attribute_data


######################################################################

sub REVISION_HISTORY { }

1;

__END__

=back

=head1 REVISION HISTORY

 $Log: SearchEngine.pm,v $

=head1 SEE ALSO

L<perl>

=head1 KNOWN BUGS

None

=head1 AUTHOR

Thai Nguyen <thai@shozilla.com>

=cut
