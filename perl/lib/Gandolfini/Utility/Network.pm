#!/usr/bin/perl -w
# Gandolfini::Utility::Network
# -------------
# $Revision: 1889 $
# $Date: 2008-04-01 13:22:27 -0700 (Tue, 01 Apr 2008) $
# -----------------------------------------------------------------------------

=head1 NAME

Gandolfini::Utility::Network

=cut

package Gandolfini::Utility::Network;

=head1 SYNOPSIS

 Gandolfini::Utility::Network->send_email ( $to_email, [$from_email, $subj, $emailmsg, $account] );

=head1 DESCRIPTION

 For any cross-network functionality (i.e. use of email server, doc server, etc.)

=cut

=head1 REQUIRES

 use strict;
 use warnings;
 use Carp qw(croak);
 use Net::SMTP;
 use MIME::Lite;

=cut

use strict;
use warnings;
use Carp qw(croak);
use Scalar::Util qw/reftype/;

use Net::SMTP;
use MIME::Lite;
use Gandolfini::Utility::ConfInit;

use constant DEBUG_NONE		=> 0b00000000;
use constant DEBUG_WARN		=> 0b00000001;
use constant DEBUG_DUMPER	=> 0b00000010;
use constant DEBUG_NET_SMTP	=> 0;

######################################################################

our ($debug);
BEGIN {
	$debug		= DEBUG_NONE;# | DEBUG_WARN;# | DEBUG_DUMPER;
}

######################################################################

=head1 METHODS

=cut

=item C<send_email> ( \@to_email|$to_email [, $from_email ] [, $subject ] [, $body ] [, $account] [, $reply_to ] )

Sends an email to $to_email - so you'd better include that.
If you don't specify an $account then it'll send it from thank_you@bizrate.com
returns 1 if ok, 0 if error.

 ACTIVE ACCOUNTS:
 - thank_you@bizrate.com (default)
 - email_this_page@bizrate.com
 - eval@bizrate.com

=cut

sub send_email {
	my $class		= shift;
	my $mail_server	= shift || 'bliss.bizrate.com';
	my $to_email	= shift || do { warn __PACKAGE__ . "->send_email: no email in\n"; return 0; };
	my $from_email	= shift || 'unknown';
	my $subject		= shift || 'subject not given';
	my $body		= shift || 'body not given';
	my $account		= shift || 'thank_you@bizrate.com';
	my $reply_to	= shift || $from_email;
	my $smtp_req	= Net::SMTP->new( $mail_server, Timeout => 10, Debug => DEBUG_NET_SMTP );

	my @to;
	if ($to_email =~ /,\s*/) {
		@to		= split(/,\s*/, $to_email);
	} elsif ((ref $to_email and reftype($to_email) eq 'ARRAY' ) || ($to_email !~ /,\s*/)) {
		@to		= ((ref $to_email and reftype($to_email) eq 'ARRAY') ? @$to_email : $to_email);
	}

	if ($ENV{'SERVER_SIGNATURE'} && isDeployMode( SZ_DEPLOY_DEV )) {
		$subject	= 'DEV/QA[' . join(", ", @to) . ']; ' . $subject;
		@to         = ( Apache->server->server_admin );
		warn $subject,"\n",$body,"\n" if DEBUG_NET_SMTP;
	}

	if (ref $smtp_req) {
		my $sent_ok = $smtp_req->mail( $account )
			&& $smtp_req->to( @to )
			&& $smtp_req->data()
			&& $smtp_req->datasend( "To: " . join(', ', @to) . "\n" )
			&& $smtp_req->datasend( "From: $from_email\n" )
			&& $smtp_req->datasend( "Reply-To: $reply_to\n" )
			&& $smtp_req->datasend( "Subject: $subject\n" )
			&& $smtp_req->datasend( "\n" )
			&& $smtp_req->datasend( "$body\n" )
			&& $smtp_req->dataend()
			&& $smtp_req->quit;
		unless ($sent_ok) {
			warn "FAILED to send email [${mail_server}] ",$smtp_req->code," ",$smtp_req->message;
		}
		return 1;
	} else {
		warn __PACKAGE__ . "->send_email: couldn't connect to email server: [${mail_server}]\n";
		return 0;
	}
} # END of send_email


=item C<send_email_mime> ( \@to_email|$to_email [, $from_email ] [, $subject ] [, $body ] [, $account] [, $reply_to ] [, $html ] [, $attachments ] [, $cc ] )

Sends an email to $to_email - so you'd better include that.
If you don't specify an $account then it'll send it from thank_you@bizrate.com
returns 1 if ok, 0 if error.

 ACTIVE ACCOUNTS:
 - thank_you@bizrate.com (default)
 - email_this_page@bizrate.com
 - eval@bizrate.com

=cut

sub send_email_mime {
	my $class		= shift;
	my $mail_server	= shift || 'bliss.bizrate.com';
	my $to_email	= shift || do { warn __PACKAGE__ . "->send_email_mime: no email in\n"; return 0; };
	my $from_email	= shift || 'unknown';
	my $subject		= shift || 'subject not given';
	my $body		= shift || 'body not given';
	my $account		= shift || 'thank_you@bizrate.com';
	my $reply_to	= shift || $from_email;
	my $html		= shift || 0;
	my $attachments	= shift;
	my $cc			= shift;
	my $type		= $html ? 'text/html' : 'text';
	
	# version 3.01 of MIME::Lite doesn't like brackets in the to or from address
	$from_email	= $class->strip_brackets( $from_email );
	$to_email	= $class->strip_brackets( $to_email );
	
	## use the server admin for development ##
	if ($ENV{'SERVER_SIGNATURE'} && isDeployMode( SZ_DEPLOY_DEV )) {
		$to_email	= [ Apache->server->server_admin ];
		$subject	= 'DEV/QA; ' . $subject;
	}
	
	## Check for backward compatibility ##
	my @all		= ((ref $to_email and reftype($to_email) eq 'ARRAY') ? @$to_email : $to_email);
	$to_email	= shift @all;
	push @all, $from_email if ($cc);
	
	# Create the initial text of the message
	my $mime_msg = MIME::Lite->new(
			From		=> $from_email,
			To			=> $to_email,
			Subject		=> $subject,
			Data		=> $body,
			Type		=> $type
	) || __PACKAGE__ . "->send_email_mime: Error creating MIME body: $!\n";
	
	$mime_msg->add( Cc => join(', ', @all) ) if (@all);
	
	$class->add_attachments( $mime_msg, $attachments );
	
	## tell it to use Net::SMTP ##
	MIME::Lite->send( 'smtp', $mail_server, Timeout => 10 );
	
	$mime_msg->send;
} # END of send_email_mime


=item C<strip_brackets> ( \@email|$email )

Strips the brackets from the email address.

=cut

sub strip_brackets {
	my $class = shift;
	my $email = shift;
	my $not_ref;
	unless (ref $email and reftype($email) eq 'ARRAY') {
		$email		= [ $email ];
		$not_ref	= 1;
	}
	foreach (@$email) {
		if (/\</) {
			s/.*?\<//;
			s/\>//;
		}
	}
	return $not_ref ? $email->[0] : $email;
} # END of strip_brackets


=item C<add_attachments> ( \@email|$email )

Strips the brackets from the email address.

=cut

sub add_attachments {
	my $class		= shift;
	my $mime_msg	= shift;
	my $attachments	= shift;
	my $type		= {
		xls => 'application/x-msexcel',
		gif => 'image/gif',
		swf => 'text/html'
	};
	
	## Attachments - list of files ##
	foreach my $attachment (@$attachments) {
		## get filename ##
		$attachment	=~ /(\w+)[.](\w+)$/;
		my $file	= $1;
		my $ext		= $2;
		warn __PACKAGE__ . "->add_attachments: ${file} ${ext}\n" if ($debug & DEBUG_WARN);
		warn __PACKAGE__ . "->add_attachments: " . $type->{$ext} . "\n" if ($debug & DEBUG_WARN);
		
		## based on file suffix, figure out type ##
		$mime_msg->attach(
			Type		=> $type->{$ext},
			Path		=> $attachment,
			Filename	=> join('.', $file, $ext),
			Disposition	=> 'attachment'
		) || warn __PACKAGE__ . "->add_attachments: Error attaching test file: $!\n";
	}
} # END of add_attachments


1;

__END__

=back

=head1 REVISION HISTORY

$Log$
Revision 1.18  2005/08/31 17:56:45  thai
 - added use blocks for dependent modules

Revision 1.17  2005/03/07 18:41:57  thai
 - added ENV check to see if the module is used under Apache or not

Revision 1.16  2004/10/07 22:32:18  draminiak
fix

Revision 1.10  2004/10/04 17:29:48  draminiak
shift in the mailserver name

Revision 1.9  2004/09/28 18:40:54  urathod
changed mail server to privatebliss.bizrate.com

Revision 1.8  2004/09/28 18:09:50  thai
 - added DEV/QA check for to email address to use the server admin

Revision 1.7  2004/09/24 17:07:13  draminiak
use bliss instead of md450 as email server

Revision 1.6  2004/09/15 00:57:16  dtopper
changed mail server to md450.bizrate.com

Revision 1.5  2004/04/29 18:46:06  thai
 - added check for $to_email if it's an array ref
 - added MIME::Lite method, send_email_mime() to support attachments

Revision 1.4  2004/04/16 23:00:31  draminiak
new Business::Help method to process email form

=head1 AUTHOR

 draminiak <draminiak@bizrate.com>

=cut
