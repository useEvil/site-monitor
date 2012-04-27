# Gandolfini::DocServer
# -------------
# $Revision: 1812 $
# $Date: 2007-08-14 06:31:54 -0700 (Tue, 14 Aug 2007) $
# -----------------------------------------------------------------------------

=head1 NAME

Gandolfini::DocServer - Thin Document Server Abstraction Class for Long Text

=cut

package Gandolfini::DocServer;

=head1 SYNOPSIS

 use Gandolfini::DocServer;
 my $content = Gandolfini::DocServer->get_content( $file_name );
 my $content = Gandolfini::DocServer->save_content( $file_name, $content );

=head1 DESCRIPTION

Gandolfini::DocServer is a thin document server abstraction class for content.

=head1 REQUIRES

L<URI::Escape|URI::Escape>

=cut

use strict;
use warnings;
use Carp qw(croak);
use URI::Escape qw(uri_escape uri_unescape);
use Gandolfini::DashProfiler extsys_profiler => [ "DocServer" ];

=head1 EXPORTS

Nothing

=cut

######################################################################

our ($debug);
use constant DEBUG_NONE		=> 0b00000000;
use constant DEBUG_WARN		=> 0b00000001;
use constant DEBUG_DUMPER	=> 0b00000010;

BEGIN {
	$debug		= DEBUG_NONE;# | DEBUG_WARN;# | DEBUG_DUMPER;
}


=head1 METHODS

=cut

######################################################################

=head2 ITERATOR AND LIST CONSTRUCTORS

=over 4

=item C<get_content> ( $file_name )

Given the file name, return the content from the doc server.

=cut
 
sub get_content {
	my $proto	= shift;
	my $class	= ref($proto) || $proto;
	my $file	= shift;
	my $server	= $ENV{'LONG_TEXT_READ_SERVER'};
	warn __PACKAGE__ . "->get_content: [${file}] [${server}]\n" if ($debug & DEBUG_WARN);
	return undef unless ($file && $server);
	
	my $url	= 'http://' . $server . '/html' . $file;
	my $ua	= new LWP::UserAgent;
	$ua->timeout(15);
	warn __PACKAGE__ . "->get_content: [${url}]\n" if ($debug & DEBUG_WARN);

	my $req	= new HTTP::Request GET => $url;
	
        my $ps = extsys_profiler($req->uri->host) if extsys_profiler_enabled();

	my $res	= $ua->request( $req );
	
	if ($res->is_success) {
		warn __PACKAGE__ . "->get_content: request was successful\n" if ($debug & DEBUG_WARN);
		my $page	= $res->content;
		warn __PACKAGE__ . "->get_content: [${page}]\n" if ($debug & DEBUG_WARN);
		$page		= undef if ($page && ($page =~ /\<\!DOCTYPE HTML PUBLIC/));
		return $page;
	}
	return undef;
} # END of get_content

=item C<save_content> ( $file_name, $content )

Given the file name and the content, save it to the doc server.

=cut

sub save_content {
	my $self	= shift;
	my $file	= shift;
	my $content	= shift;
	my $server	= $ENV{'LONG_TEXT_WRITE_SERVER'};
	warn __PACKAGE__ . "->save_content: [${file}] [${content}] [${server}]\n" if ($debug & DEBUG_WARN);
	return unless ($file && $content && $server);

	my $url	= 'http://' . $server . '/cgi-bin/save_long_text.pl';
	my $ua	= new LWP::UserAgent;
	$ua->timeout(15);
	warn __PACKAGE__ . "->save_content: ${url}?filename=${file}&long_text=" . uri_escape( $content ) . "\n" if ($debug & DEBUG_WARN);
	
	my $req = new HTTP::Request POST => $url;
	$req->content_type( 'application/x-www-form-urlencoded' );
	$req->content( 'filename=' . $file . '&long_text=' . uri_escape( $content ) );
	
        my $ps = extsys_profiler($req->uri->host) if extsys_profiler_enabled();

	my $res	= $ua->request( $req );
	
	if ($res->is_success) {
		warn __PACKAGE__ . "->save_content: request was successful\n" if ($debug & DEBUG_WARN);
		my $page	= $res->content;
		warn __PACKAGE__ . "->save_content: [${page}]\n" if ($debug & DEBUG_WARN);
		return -1;
	}
	return undef;
} # END of save_content

######################################################################

1;

__END__

=back

=head1 REVISION HISTORY

 $Log$
 Revision 1.3  2005/03/22 22:49:02  jjordan
 forgot to add date_runner.t earlier.
 Modified the manifest, annuncio_runner.t, and the docserver tests.

 Revision 1.2  2004/06/14 22:49:33  thai
  - updated warnings

 Revision 1.1  2004/04/30 20:35:15  thai
  - added Gandolfini::DocServer module


=head1 KNOWN BUGS

None

=head1 AUTHOR

 Thai Nguyen <thai@bizrate.com>

=cut
