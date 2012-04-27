#!/usr/bin/perl -w
# Gandolfini::Utility::Tools
# -------------
# $Revision: 1280 $
# $Date: 2006-06-01 11:03:09 -0700 (Thu, 01 Jun 2006) $
# -----------------------------------------------------------------------------

package Gandolfini::Utility::Tools;

=head1 NAME

 Gandolfini::Utility::Tools

=cut

=head1 SYNOPSIS

 use Gandolfini::Utility::Tools;
 Gandolfini::Utility::Tools->verify_email( email )

=head1 DESCRIPTION

Handy little functions for doing input verification, like checking that an email address is valid.

=cut

=head1 REQUIRES

 use strict;
 use Crypt::Blowfish;
 use HTTP::Cookies;
 use LWP::UserAgent;
 use HTTP::Request;

=cut

use strict;
use Crypt::Blowfish;
use HTTP::Cookies;
use LWP::UserAgent;
use Digest::MD5;

use constant DEBUG_NONE		=> 0b00000000;
use constant DEBUG_WARN		=> 0b00000001;
use constant DEBUG_DUMPER	=> 0b00000010;

use constant MAX_KEY_LENGTH			=> 10;
use constant AFFILIATE_SECRET_KEY	=> 'This is a really long 223923829382 key';

our ($debug);
BEGIN {
	$debug		= DEBUG_NONE;# | DEBUG_WARN;# | DEBUG_DUMPER;
}

=head1 METHODS

=item C<verify_email> ( $email )

Verify that a given email address is valid

=cut

sub verify_email {
	my $self			= shift;
	my $email			= shift || '';
	my $error_code 		= 'OK';
	my $is_mybizrate 	= 0;
	
	if ($email) { 
		# this pattern is a simplified form of all possible valid email addresses 
		# as defined in RFC #822
		# (available online at ftp://ftp.isi.edu/in-notes/rfc822.txt)
		if ($email !~ /^[\000-\177]+$/ ||				# must be between ASCII codes 000 and 177 octal 
			$email !~ /
				^										# start at beginning of string
				## local-part of address:
				[^\s\000-\037()<>@,;:\\".[\]]+			# exclude:
														# \s			spaces, 
														# \000-\037		ASCII controls, 
														# ()<>@,;:\\".[\]	special characters
														# but require at least one character
				([.][^\s\000-\037()<>@,;:\\".[\]]+)* 	# allow additional words in the 
														# local part, separated by periods 
				[\@]									# require '@' symbol
				## domain part of address:
				[^\s\000-\037()<>@,;:\\".[\]]+			# first sub-domain must have 
														# at least one character
				([.][^\s\000-\037()<>@,;:\\".[\]]+)+ 	# require at least one additional
														# sub-domain, separated by periods 
				$										# finish at end of string
			/x) 
		{ 
			$error_code = 'INVALID'; 
		}
		
		$is_mybizrate = 1 if ($email =~ /\@mybizrate/);
	} else {
		$error_code = 'MISSING';
	} # no email

	warn "verify_email... ERROR_CODE: $error_code - IS_MYBIZRATE: $is_mybizrate \n" if ($debug & DEBUG_WARN);
	return ($error_code, $is_mybizrate);
} # end sub verify_email


=item C<verify_url> ( $url [, $agent ] [, $timeout ] [, $max_redirect ] [, \%form | \@form ] )

Checks the url to see if it's valid.  Returns the response object.  If $form is 
passed then, the method will be a POST as opposed to the default GET.

=cut

sub verify_url {
	my $self		= shift;
	my $url			= shift || return undef;
	my $agent		= shift || 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1; .NET CLR 1.1.4322)';
	my $timeout		= shift || 15;
	my $max_redir	= shift || 7;
	my $form		= shift;
	warn __PACKAGE__ . "->verify_url: url[${url}] agent[${agent}] timeout[${timeout}] max_redir[${max_redir}]\n" if ($debug & DEBUG_WARN);
	my $cookie		= HTTP::Cookies->new( autosave => 1, ignore_discard => 1 );
	my $ua			= LWP::UserAgent->new( timeout => $timeout, max_redirect => $max_redir );
	my $res;
	$ua->agent( $agent );
	$ua->cookie_jar( $cookie );
	if (ref $form) {
		$res		= $ua->post( $url, $form );
	} else {
		$res		= $ua->get( $url );
	}
	## check for a sucessfull HTTP call ##
	warn __PACKAGE__ . '->verify_url: res: ' . Data::Dumper::Dumper( $res ) if ($debug & DEBUG_DUMPER);
	return undef unless (ref $res);
	warn __PACKAGE__ . "->verify_url: original[${url}]\n" if ($debug & DEBUG_WARN);
	warn __PACKAGE__ . "->verify_url: as_string[" . $res->as_string . "]\n" if ($debug & DEBUG_DUMPER);
	warn __PACKAGE__ . "->verify_url: is_redirect[" . $res->is_redirect . "]\n" if ($debug & DEBUG_WARN);
	warn __PACKAGE__ . "->verify_url: is_success[" . $res->is_success . "]\n" if ($debug & DEBUG_WARN);
	warn __PACKAGE__ . "->verify_url: status_line[" . $res->status_line . "]\n" if ($debug & DEBUG_WARN);
	warn __PACKAGE__ . "->verify_url: content[" . $res->content . "]\n" if ($debug & DEBUG_DUMPER);
	warn __PACKAGE__ . "->verify_url: error_as_HTML[" . $res->error_as_HTML . "]\n" if (!$res->is_success && ($debug & DEBUG_DUMPER));
	return $res;
} # ENd of verify_url


=item C<get_url> ( $url [, $agent ] [, $timeout ] [, $max_redirect ] )

Forwards to verify_url().

=cut

sub get_url {
	return shift->verify_url( @_ );
} # END of get_url


=item C<post_url> ( $url, $form [, $agent ] [, $timeout ] [, $max_redirect ] )

Forwards to verify_url().

=cut

sub post_url {
	my $self			= shift;
	my $url				= shift || return undef;
	my $form			= shift || return undef;
	my $agent			= shift;
	my $timeout			= shift;
	my $max_redirect	= shift;
	return $self->verify_url( $url, $agent, $timeout, $max_redirect, $form );
} # END of post_url


=item C<encrypt> ( $string, $key )

Encrypt the string with Crypt::Blowfish.

=cut

sub encrypt {
	my $class	= shift;
	my $str		= shift;
	my $key		= shift;
	my $ed;
	my $i;
	
	my $len = length($key);
	if ($len == 0) {
		warn __PACKAGE__ . "->encrypt: empty key passed\n";
		return undef;
	}
	
	# make key length between 8 and max_key_len bytes
	if ($len >= 8) {
		$key = substr($key, 0, ($len >= MAX_KEY_LENGTH) ? MAX_KEY_LENGTH : $len);
	} else {
		$key = $key . (' ' x (8-$len));
	}
	
	$len = length($str);
	warn __PACKAGE__ . "->encrypt: len = $len \n" if ($debug & DEBUG_WARN);
	my $cstr;
	my $k;
	my $clen;
	my $cipher = new Crypt::Blowfish $key;
	# encrypt 8 bytes at a time
	for ($i = 0; $i < $len; $i += 8) {
		$clen = ($len - $i) >= 8 ? 8 : ($len - $i);
		warn __PACKAGE__ . "->encrypt: clen = $clen \n" if ($debug & DEBUG_WARN);
		if ($clen < 8) {
			$cstr = substr($str, $i, ($len - $i));
			# pad the string to make it 8 bytes
			$cstr = $cstr . ("\f" x (8-($len-$i)));
		} else {
			$cstr = substr($str, $i, 8);
		}

		my $l1 = length($cstr);
		my $ciphertext = $cipher->encrypt( $cstr );  # NB - 8 bytes
		$ed = $ed . unpack("H16", $ciphertext);
	}

	return $ed;
} # END of encrypt


=item C<decrypt> ( $string, $key )

Decrypt the string with Crypt::Blowfish.

=cut

sub decrypt {
	my $class	= shift;
	my $str		= shift;
	my $key		= shift;
	my $cd;
	my $i;
	
	my $len = length($key);
	if ($len == 0) {
		warn __PACKAGE__ . "->decrypt: empty key passed\n";
		return undef;
	}
	
	# make key length between 8 and max_key_len bytes
	if ($len >= 8) {
		$key = substr($key, 0, ($len >= MAX_KEY_LENGTH) ? MAX_KEY_LENGTH : $len);
	} else {
		$key = $key . (' ' x (8-$len));
	}
	
	$len = length($str);
	warn __PACKAGE__ . "->decrypt: len = $len \n" if ($debug & DEBUG_WARN);
	my $cstr;
	my $k;
	my $clen;
	my $cipher = new Crypt::Blowfish $key;
	for ($i = 0; $i < $len; $i += 16) {
		$clen = ($len - $i) >= 16 ? 16 : ($len - $i);
		warn __PACKAGE__ . "->decrypt: clen = $clen\n" if ($debug & DEBUG_WARN);
		if ($clen < 16) {
			return undef;
		} else {
			$cstr = substr($str, $i, 16);
			$cstr = pack("H16", $cstr);
		}
		
		my $cleartext = $cipher->decrypt( $cstr );  # NB - 8 bytes
		my $p = index($cleartext, "\f");
		if ($p > 0) {
			# remove padding chars
			$cd = $cd . substr($cleartext, 0, $p);
		} else {
			$cd = $cd . $cleartext;
		}
	}
	return $cd;
} # END of decrypt


sub md5_hexdigest {
	my $self	= shift;
	my $md5		= Digest::MD5->new;
	$md5->add( @_ );
	return $md5->hexdigest;
}


sub md5_b64digest {
	my $self	= shift;
	my $md5		= Digest::MD5->new;
	$md5->add( @_ );
	return $md5->b64digest;
}


sub encrypted {
	my $self	= shift;
	my $pass	= shift || return undef;
	my $secret	= shift || AFFILIATE_SECRET_KEY;
	return $self->md5_b64digest( $pass, $secret );
}

1;

__END__


=back

=head1 AUTHOR

draminiak <draminiak@bizrate.com>

=cut
