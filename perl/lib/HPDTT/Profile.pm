#!/usr/bin/perl -w
# HPDTT::Profile
# -------------
# $Revision: 1566 $
# $Date: 2006-12-05 17:02:58 -0800 (Tue, 05 Dec 2006) $
# -----------------------------------------------------------------------------

package HPDTT::Profile;

=head1 NAME

 HPDTT::Profile

=cut

=head1 SYNOPSIS

 use HPDTT::Profile;

=head1 DESCRIPTION

Handy little functions for doing input verification, like checking that an email address is valid.

=cut

use strict;
use Scalar::Util qw/reftype/;

use constant DEBUG_NONE		=> 0b00000000;
use constant DEBUG_WARN		=> 0b00000001;
use constant DEBUG_DUMPER	=> 0b00000010;

use constant CONTENT_TYPE	=> 'text/html';

our ($VERSION, $debug);
BEGIN {
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 1566 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
	$debug		= DEBUG_NONE;# | DEBUG_WARN;# | DEBUG_DUMPER;
}

=head1 METHODS

=item C<handler> ( $apache_req )

Generic mod_perl Response handler

=cut

sub handler : method {
	my $class	= shift;
	my $r		= shift;
	my $self	= $class->new( $r );
	
	$self->run();
} # END of handler


=item C<new> ( $request_obj )

Base constructor.

=cut

sub new {
	my $class	= shift;
	my $r		= shift || return undef;
	my $self	= bless { _r => $r }, $class;
	return $self;
} # END of new


=item C<run> ( )

Process query

=cut

sub run {
	my $self	= shift;
	return undef unless (ref $self);
	my $r		= $self->r;
	## set the content type to text/xml ##
	$r->content_type( CONTENT_TYPE );
	$r->send_http_header();
	
	$self->print_html;
} # END of run


=item C<query> (  )

Returns the L<Gandolfini::Args|Gandolfini::Args> object for the current request.

=cut

sub query {
	my $self	= shift;
	return undef unless (ref $self);
	
	if ($self->{'query'}) {
		return $self->{'query'};
	} else {
		my %query = (($self->r->method eq 'GET') ? $self->r->args : $self->r->content);
		$self->{'query'} = Gandolfini::Args->new( \%query );
		return $self->{'query'};
	}
} # END of query


=item C<print_html> (  )

Prints the HTML for the Stored Procedure Detail.

=cut

sub print_html {
	my $self		= shift;
	return undef unless (ref $self);
	$self->sp_detail( $self->query->unescape('sp') );
	my $text		= $self->text;
	my $pcols		= join(' ', @{ $self->cols } ) if (ref $self->cols and reftype($self->cols) eq 'ARRAY' );
	my $pargs;
	if (ref $self->args and reftype($self->args) eq 'ARRAY') {
		foreach (@{ $self->args }) { $pargs .= join('=', each(%$_)) . ' ' }
	}
	print qq~
<html>
<body leftmargin="10" topmargin="10" marginheight="10" marginwidth="10">

<pre>
Stored Procedure Call:       $text
Stored Procedure Arguments:  $pargs
Returned Columns:            $pcols

~;
	$self->sp_execute;
	print qq~
</pre>

</body>
</html>
~;
} # END of print_html


=item C<sp_detail> ( $sp_text )

Returns all the information given by the stored procedure.

=cut

sub sp_detail {
	my $self	= shift;
	return undef unless (ref $self);
	my $sp_text	= shift;
	warn __PACKAGE__ . "->sp_detail: sp_text[${sp_text}]\n" if ($debug & DEBUG_WARN);
	my ($sp, $params);
	(undef, $sp, $params) = split(/\s+/, $sp_text);
	my $pdata	= Gandolfini::Data->_procs( $sp );
	$self->{'text'}		= $sp_text;
	$self->{'sp'}		= $sp;
	$self->{'args'}		= $pdata->{'args'};
	$self->{'class'}	= $pdata->{'class'};
	$self->{'cols'}		= $pdata->{'cols'};
	$self->{'db_name'}	= $pdata->{'dbh'};
} # END of sp_detail


=item C<sp_execute> ( [ $sp_text ] )

Executes and prints the data using Data::Dumper.

=cut

sub sp_execute {
	my $self	= shift;
	my $class	= ref($self) || $self;
	my $sp_text	= shift || $self->text;
	warn __PACKAGE__ . "->sp_execute: sp_text[${sp_text}]\n" if ($debug & DEBUG_WARN);
	my $dbh		= Gandolfini::Data->_dbh( $self->db_name );
	my $sth		= $dbh->prepare( $sp_text )	|| die( 'Unable to prepare statement handle: ' . $dbh->errstr );
	my $rv		= $sth->execute()			|| die( 'Unable to execute statement: ' . $sth->errstr );
	while (my $hash = $sth->fetchrow_hashref) {
		print Data::Dumper::Dumper( $hash );
	}
	$sth->finish;
	undef $sth;
} # END of sp_execute


sub r		{ $_[0]->{'_r'}			}
sub text	{ $_[0]->{'text'}		}
sub sp		{ $_[0]->{'sp'}			}
sub args	{ $_[0]->{'args'}		}
sub class	{ $_[0]->{'class'}		}
sub cols	{ $_[0]->{'cols'}		}
sub db_name	{ $_[0]->{'db_name'}	}


1;

__END__


=back

=head1 REVISION HISTORY

$Log$
Revision 1.1  2005/02/03 00:38:30  thai
 - new file for displaying stored procedure details


=head1 AUTHOR

Thai Nguyen <thai@shopzilla.com>

=cut
