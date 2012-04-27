#!/usr/bin/perl -w
# Gandolfini::Annuncio
# -------------
# $Revision: 1812 $
# $Date: 2007-08-14 06:31:54 -0700 (Tue, 14 Aug 2007) $
# -----------------------------------------------------------------------------

=head1 NAME

Gandolfini::Annuncio

=cut

package Gandolfini::Annuncio;

=head1 SYNOPSIS

 use Gandolfini::Annuncio;
 Gandolfini::Annuncio->annuncio( \@args );
 Gandolfini::Annuncio->get_url( $LW_call_type [ ,$get_with_std_params_flag ] );

=head1 DESCRIPTION

Provides methods to create and send annuncio calls via LWP.

=head1 REQUIRES

L<LWP::UserAgent|LWP::UserAgent>
L<HTTP::Request|HTTP::Request>

=cut

use strict;
use warnings;
use Carp qw(croak);
use URI::Escape qw(uri_escape);
use Gandolfini::DashProfiler extsys_profiler => [ "Annuncio" ];

use LWP::UserAgent;
use HTTP::Request;

use constant DEBUG_NONE		=> 0b00000000;
use constant DEBUG_WARN		=> 0b00000001;
use constant DEBUG_DUMPER	=> 0b00000010;

use constant ESCPAE	=> '#';

######################################################################

our ($debug);
BEGIN {
	$debug		= DEBUG_NONE;# | DEBUG_WARN;# | DEBUG_DUMPER;
}

######################################################################

=item C<annuncio_send> ( $url )

live wire annuncio calls

=cut

sub annuncio_send {
	my $self	= shift;
	my $url		= shift;
	warn __PACKAGE__ . "->annuncio_send: [${url}] \n" if ($debug & DEBUG_WARN);
	
	my $ua = new LWP::UserAgent;
	$ua->timeout(15);
	
	my $req		= new HTTP::Request GET => $url;
	$req->content_type( 'application/x-www-form-urlencoded' );

        my $ps = extsys_profiler($req->uri->host) if extsys_profiler_enabled();

	my $res		= $ua->request( $req );
	my $page	= $res->content;
	my $cs_id	= ($page =~ /CS_ID=\s*(\d+)/i) ? $1 : 0;
	my $result	= $self->annuncio_status( $res, $req->uri );
	
	warn __PACKAGE__ . "->annuncio_send: failed[${url}]\n" unless ($res->is_success);
	warn __PACKAGE__ . "->annuncio_send: [${url}]\n" if ($debug & DEBUG_WARN);
	warn __PACKAGE__ . "->annuncio_send: no cs_id returned\n" if (!$cs_id && ($debug & DEBUG_WARN));
	warn __PACKAGE__ . "->annuncio_send: CS ID returned by annuncio [${cs_id}]\n" if ($debug & DEBUG_WARN);
	warn __PACKAGE__ . "->annuncio_send: result: [${result}]\n" if (!$cs_id && ($debug & DEBUG_WARN));
	
	return ($cs_id ? $cs_id : $result);
} # END of annuncio_send

=item C<annuncio_status> ( $response )

Checks the WireStatusCode of the annuncio result

=cut

sub annuncio_status {
	my $self		= shift;
	my $response	= shift;
	my $uri			= shift;
	my $content		= $response->content;
	## check for a sucessfull Livewire call ##
	warn __PACKAGE__ . "->annuncio_status: Check status of LiveWire call\n" if ($debug & DEBUG_WARN);
	warn __PACKAGE__ . "->annuncio_status: [${uri}]\n" if ($debug & DEBUG_WARN);
	warn __PACKAGE__ . "->annuncio_status: [${content}]\n" if ($debug & DEBUG_WARN);
	warn __PACKAGE__ . "->annuncio_status: [" . $response->is_success . "]\n" if ($debug & DEBUG_WARN);
	if ($response->is_success) {
		if ($content =~ /WireStatusCode:\s*(\d+)/) {
			my $code = $1;
			warn __PACKAGE__ . "->annuncio_status: code[${code}]\n" if ($debug & DEBUG_WARN);
			unless ($code == 0) {
				warn __PACKAGE__ . "->annuncio_status: Sending Notify Email\n" if ($debug & DEBUG_WARN);
				my $body = qq!
-------------------------------------------------------
LiveWire Call Failed:

$content
$uri

-------------------------------------------------------
!;
				Gandolfini::Utility::Network->send_email(
					undef,						# mail server
					'dweinrot@bizrate.com',		# to email
					'support@bizrate.com',		# from email
					'LiveWire Call Failed',		# email subject
					$body,						# email body
					'support@bizrate.com',		# active account
					'support@bizrate.com'		# reply-to email
				) || warn __PACKAGE__ . "->annuncio_status: Failed to send LiveWire Failed Email\n";
				return undef;
			}
		}
	} else {
		warn __PACKAGE__ . "->annuncio_status: Could not send DATA to LiveWire\n";
		warn __PACKAGE__ . "->annuncio_status: [${uri}]\n";
		return undef;
	}
	return 1;
} # END of annuncio_status

=item C<annuncio_server_LW> ( )

Base URL for all LW calls

=cut

sub annuncio_server_LW { return 'http://em.bizrate.com/Apps/DCS/wire?'; }

=item C<get_url> ( $LW_call_type, $use_params )

Returns the url for the particular annuncio link.

=cut

sub get_url {
	my $self			= shift;
	my $LW_call_type	= shift || '';
	my $use_params		= shift || '';
	
	# REPLACE WITH CONF IN FUTURE BY COBRAND & COUNTRY
	my $type			= shift || $self->bizrate_type;
	my $params			= [ ];
	$params				= $self->std_params if ($use_params);
	warn __PACKAGE__ . '->get_url: No Base URL for type: ' . $LW_call_type unless(defined $type->{$LW_call_type});
	unshift @$params,  $type->{$LW_call_type} || '';
	warn __PACKAGE__ . '->get_url: ' . join('&', @$params) if ($debug & DEBUG_WARN);
	return join('&', @$params);
} # END of get_url

=item C<bizrate_type> ()

Returns the type hash for BizRate.

=cut

sub bizrate_type {
	return {
		b2b_reg_validation		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST2M03eTGH7a1Rw',
		b2b_reg_validated		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST2M03jTGH7a5TT',
		b2b_reg_match_email		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST2NG0fTGHCKzmu',
		b2b_reg_hijack			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST2M03oTGH7a8eQ',
		
		cc_ctp_charge			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STw6LTFtV0g1Z',
		b2b_cc_decline_expire	=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STam2wTG7_U_2v',
		b2b_cc_delist_alert		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST30ByTG8ePMeQ',
		b2b_cc_deposit			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STM07vTFzIl3gL',
		b2b_cc_pre_unbid_alert	=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST1yn$TG7$5Aj1',
		b2b_cc_recurring_bill	=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST1lgiTG7rb9UF',
		b2b_cc_unbid_alert		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST305uTG8eDQHo',
		b2b_cc_winback_alert	=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST328NTG8sk9x_',
		
		b2b_forgot_password		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STJTDTFzrWxZH',
		b2b_special_offer		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST1hm2sTFkyibdT',
		b2b_merchant_listings	=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STfW3sTFWP1jb_',
		b2b_advertise			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST_G1zTFXcV3b4',
		b2b_login_password		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STfW4NTFWP2fL8',
		b2b_duplicate_email		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STQG4CTFVI19Nk',
		b2b_duplicate_name_url	=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST1o1BTFXRsc0d',
		oa_application			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STZW23TFxbteAK',
		submit_feed				=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STm3rTFzmx_3W',
		disengage				=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST1j85TFpYEAlR',
		sweeps					=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST1mGCTFLsXB_S',
		new_account				=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STDm1LTFLIlWMm',
#		review_thanks			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST8W04TF1zzeTG',
		confirm_account			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STDm4LTFLH2XXL',
		review_confirm			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STDm4STFLH2eBk',
		review_validation		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STFW3KTFLiNjGP',
		forgot_password			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STfm0iTFp2l0LL',
		car_quotes				=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST_G1vTG9gvTYn',
	};
} # END of bizrate_type

=item C<shopzilla_us_type> ()

Returns the type hash for Shopzilla US.

=cut

sub shopzilla_us_type {
	return {
		b2b_reg_validation		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST2M03eTGH7a1Rw',
		b2b_reg_validated		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST2M03jTGH7a5TT',
		b2b_reg_match_email		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST2NG0fTGHCKzmu',
		b2b_reg_hijack			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST2M03oTGH7a8eQ',
		
		cc_ctp_charge			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STw6LTFtV0g1Z',
		b2b_cc_decline_expire	=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STam2wTG7_U_2v',
		b2b_cc_delist_alert		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST30ByTG8ePMeQ',
		b2b_cc_deposit			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STM07vTFzIl3gL',
		b2b_cc_pre_unbid_alert	=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST1yn$TG7$5Aj1',
		b2b_cc_recurring_bill	=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST1lgiTG7rb9UF',
		b2b_cc_unbid_alert		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST305uTG8eDQHo',
		b2b_cc_winback_alert	=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST328NTG8sk9x_',
		
		b2b_forgot_password		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STJTDTFzrWxZH',
		b2b_special_offer		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STJeJTFzroV_7',
		b2b_merchant_listings	=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STfW3sTFWP1jb_',
		b2b_advertise			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST_G1zTFXcV3b4',
		b2b_login_password		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STfW4NTFWP2fL8',
		b2b_duplicate_email		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STQG4CTFVI19Nk',
		b2b_duplicate_name_url	=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST1o1BTFXRsc0d',
		oa_application			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STZW23TFxbteAK',
		submit_feed				=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STm3rTFzmx_3W',
		sweeps					=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST1mGCTFLsXB_S',
		new_account				=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STmI4TFwIyqNV',
#		review_thanks			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST8W04TF1zzeTG',
		confirm_account			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STmLXTFwIyzDR',
		review_confirm			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STmRwTFwIzBR7',
		review_validation		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STmgnTFwIzJ35',
		forgot_password			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STmNWTFwIz4Jp',
	};
} # END of shopzilla_us_type

=item C<shopzilla_uk_type> ()

Returns the type hash for Shopzilla UK.

=cut

sub shopzilla_uk_type {
	return {
		b2b_reg_validation		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST2M03eTGH7a1Rw',
		b2b_reg_validated		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST2M03jTGH7a5TT',
		b2b_reg_match_email		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST2NG0fTGHCKzmu',
		b2b_reg_hijack			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST2M03oTGH7a8eQ',
		
		cc_ctp_charge			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STw6LTFtV0g1Z',
		b2b_cc_decline_expire	=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STam2wTG7_U_2v',
		b2b_cc_delist_alert		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST30ByTG8ePMeQ',
		b2b_cc_deposit			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STM07vTFzIl3gL',
		b2b_cc_pre_unbid_alert	=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST1yn$TG7$5Aj1',
		b2b_cc_recurring_bill	=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST1lgiTG7rb9UF',
		b2b_cc_unbid_alert		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST305uTG8eDQHo',
		b2b_cc_winback_alert	=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST328NTG8sk9x_',
		
		b2b_forgot_password		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STJTDTFzrWxZH',
		b2b_special_offer		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STJeJTFzroV_7',
		oa_application			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STZW23TFxbteAK',
		submit_feed				=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STm3rTFzmx_3W',
		sweeps					=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST1mGCTFLsXB_S',
		new_account				=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STfIbTFvvGCWL',
#		review_thanks			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=ST8W04TF1zzeTG',
		confirm_account			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STfJdTFvvGi3V',
		review_confirm			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STfMbTFvvGz4n',
		review_validation		=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STfRRTFvvIDzP',
		forgot_password			=> 'lpurl=http://em.bizrate.com/Apps/DCS/mcp?q=STfKmTFvvGqzt',
	};
} # END of shopzilla_uk_type

=item C<std_params> ( $other_params )

Use common annuncio args for the url.  Pass in an array for the other params.

=cut

sub std_params {
	return [
		'method=processtrxn',
		'returntype=2',
		'externid=email_subs'
	];
} # END of std_params

=item C<annuncio> ( $url, \@parms )

build annuncio url with passed in parameters and make LW call 

=cut

sub annuncio {
	my $self	= shift;
	my $params	= shift;
	warn __PACKAGE__ . '->annuncio: params[' . join('&', @$params) . "]\n" if ($debug & DEBUG_WARN);
	my $url		= $self->annuncio_server_LW . (join '&', @$params);
	warn __PACKAGE__ . "->annuncio: url[${url}]\n" if ($debug & DEBUG_WARN);
	## escape certain characters: ( # )
	$url		= uri_escape( $url, ESCPAE );
	warn __PACKAGE__ . "->annuncio: url[${url}]\n" if ($debug & DEBUG_WARN);
	my $result	= $self->annuncio_send( $url );
	warn __PACKAGE__ . "->annuncio: result[${result}]\n" if ($debug & DEBUG_WARN);
	return $result;
} # END of annuncio


1;

__END__

=back

=head1 REVISION HISTORY

$Log$
Revision 1.35  2005/09/15 20:31:05  draminiak
remove warn

Revision 1.34  2005/09/13 18:01:30  thai
 - fixed double semi-colon typo

Revision 1.33  2005/09/12 23:37:53  thai
 - added warn for unsuccessful

Revision 1.32  2005/09/08 00:57:03  thai
 - put the characters in a constant

Revision 1.30  2005/08/31 17:55:59  thai
 - removed b2b_payment_plan_email because it's not used anymore

Revision 1.29  2005/07/13 18:50:35  thai
 - updated LW urls

Revision 1.28  2005/06/28 00:44:30  thai
 - b2b registration livewires added

Revision 1.27  2005/06/08 20:07:30  thai
 - cleaned up warnings

Revision 1.26  2005/05/03 22:34:20  thai
 - added Registration LW information

Revision 1.25  2005/04/02 01:01:21  thai
 - updated returns to send back a value

Revision 1.24  2005/03/19 02:14:48  jjordan
I modified the 'get_url' method slightly to make it easier to test.
I added the test class and test runner script for it.

Revision 1.23  2005/03/18 02:36:19  aelliston
Fixed warning for calls without a cid returned.

DEV#2035

Revision 1.22  2005/03/15 00:58:27  aelliston
Added car quotes url

DEV#1980

Revision 1.21  2005/03/07 18:26:39  thai
 - added LW urls for the new UK B2B site

Revision 1.20  2004/10/25 21:19:58  sneweissman
added submit_feed and disengage calls

Revision 1.19  2004/10/22 18:27:21  thai
 - added LW lpurls for B2B UK

Revision 1.18  2004/10/15 00:30:24  thai
 - updated LW lpurls for B2B

Revision 1.17  2004/10/15 00:01:10  thai
 - added livewire lpurls for B2B UK forgot password

Revision 1.16  2004/10/09 01:00:14  thai
 - removed lead email

Revision 1.15  2004/10/04 19:49:12  thai
 - added special offer lw url

Revision 1.14  2004/09/28 18:08:00  thai
 - added oa_application LiveWire lpurl

Revision 1.13  2004/09/09 23:22:27  draminiak
LW call not used

Revision 1.12  2004/09/07 17:13:35  dstanchfield
added US and UK annucio livwire calls.

Revision 1.11  2004/08/06 21:37:21  thai
 - updated LW base url to the most current value

Revision 1.10  2004/07/20 00:27:45  thai
 - added review_validation purl

Revision 1.9  2004/06/30 01:48:42  thai
 - turned off warnings

Revision 1.8  2004/06/08 19:01:48  thai
 - added LW params for forgot password

Revision 1.7  2004/05/25 01:13:51  thai
 - added Annuncio urls for review thanks and confirm

Revision 1.6  2004/05/14 07:51:09  draminiak
fix uri error in annuncio_status && take new-lines out of warns

Revision 1.5  2004/04/29 18:54:45  thai
 - fixed variable name error

Revision 1.4  2004/04/29 18:43:10  thai
 - added warnings
 - added WireStatusCode check to send email when the status is not 0

Revision 1.3  2004/04/05 23:19:58  draminiak
*** empty log message ***

Revision 1.2  2004/03/15 18:30:54  draminiak
*** empty log message ***


=head1 AUTHOR

 draminiak <draminiak@bizrate.com>

=cut
