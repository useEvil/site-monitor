#
# Cookie.pm
#
# ---------------------------------------------------------
# Gandolfini::Session::Cookie
# Cookie.pm
# -----------------
# $Revision: 1937 $
# $Date: 2008-06-17 14:52:08 -0700 (Tue, 17 Jun 2008) $
# ---------------------------------------------------------
# DESCRIPTION OF FILE
# 	Handles the user session cookies.
# ---------------------------------------------------------
package Gandolfini::Session::Cookie;

=head1 NAME

Gandolfini::Session::Cookie Module

=head1 SYNOPSIS

use Gandolfini::Session::Cookie;

=head1 REQUIRES

 Apache
 CGI::Cookie
 MD5

=head1 DESCRIPTION

Used to make session cookies which can later be verified by 
verify_session().  Removes necessity to make database access 
after each click.

=head1 METHODS

=over 4

=cut


# Borrowed liberally from 'Apache::TicketTool', 
# _Writing Apache Modules with Perl and C_ by L. Stein and D. MacEachern

use strict;
use MD5;
use Carp;
use CGI::Cookie;
use Apache;
use Time::HiRes qw(gettimeofday tv_interval);
use Time::Local;
use Gandolfini::Utility::UniqueID qw( session_unique_id global_unique_id is_valid_session_unique_id is_valid_global_unique_id );

# Set constants
use constant DEFAULT_EXP	=> '+10y';						# default expiration
use constant SECRET			=> 'THIS IS A BIZRATE SECRET!';	# secret
use constant DEBUG_NONE		=> 0b00000000;
use constant DEBUG_WARN		=> 0b00000001;
use constant DEBUG_DUMPER	=> 0b00000010;
use constant DEBUG			=> DEBUG_NONE;# | DEBUG_WARN;# | DEBUG_DUMPER;

# Allow a global prefix on all cookies to prevent cookie collisions between sites
our $COOKIE_PREFIX = "";

######################################################################

our ($VERSION);
BEGIN {
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 1937 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
}

######################################################################


=item C<new> ( [ $r ] )

Returns Display::DisplaySessionCookie object

=cut

sub new {
	my $class 	= shift;
	my $r		= shift || Apache->request;

	warn "$class->new for r$$r\n" if DEBUG & DEBUG_WARN;

	my $self	= { _r => $r };
	# Create a happy hostname, include the leading dot, drop the port number

	my $hostname = $r->hostname;
	my $domain;
	
	if ($hostname =~ /^(?:merchanteu0[1-9]|merchant00[1-9].shopzilla.lax|merchant00[1-9].sl2.shopzilla.lax)/) {
	  $domain = "merchant.shopzilla.com";
	} elsif ($hostname =~ /^(?:merchantqa00[1-9]|merchdev00[1-9])/) {
		$domain = $hostname;
	} elsif ($hostname =~ /([^\.]+\.)(com|net|org|be|dk|gs|jp|kz|ms|fm|sh|st|ws|ac|ca|de|fr)$/) {
		$domain = '.' . $1 . $2;
	} elsif ($hostname =~ /([^\.]+)(\.[^\.]+\.)(uk|il|nz)$/) {
		$domain = '.' . $1 . $2 . $3;
	}
	$self->{'domain'} = $domain;
	
	bless $self, $class;
} # END of new


=item C<r> (  )

=item C<secret> (  )

 r returns the Apache request object
 secret returns the secret, used for the cookie

=cut

sub r		{ $_[0]->{'_r'} ||= Apache->request	}
sub secret	{ $_[0]->{'_secret'} ||= SECRET		}


=item C<make_key> ( $userid | $User [ , $expires, $path ] )

Returns CGI::Cookie object with MD5-MAC session ID.  
Optional arguments should be supplied for admin sessions.

=cut

sub make_key {
	my $self	= shift;
	return undef unless ref($self);	
	my $br		= shift || return undef;
	my $expires	= shift || DEFAULT_EXP;
	my $path	= shift || '/';
	my $time	= time;
	warn __PACKAGE__ . "->make_key\n" if (DEBUG & DEBUG_WARN);

	my $secret	= $self->secret || return undef;
	my $hash	= MD5->hexhash(
					$secret .
					MD5->hexhash(join $;,	$secret,
											$time,
											$expires,
											$br)
				);

	return $self->make_cookie(	'user_key',
								{
									_TIME			=> $time,
									_EXPIRES		=> $expires,
									_BR				=> $br,
									_HASH			=> $hash
								},
								$expires,
								$path
							);
} # END of make_key


=item C<verify_cookie> ( $cookie_name, $hash_name, $data )

Validates a cookie. Expects three parameters the cookies name, 
the name of the hash stored in the cookie, and an arrayref of 
the data to be validated.

=cut

sub verify_cookie {
	my $self	= shift;
	return undef unless (ref $self);
	my $cname	= shift;
	my $hname	= shift;
	my $data	= shift;
	return undef unless ( $cname && $hname && ref($data) );
	return $self->{$cname.'_session'} if ($self->{$cname.'_verified'});
	my $r = $self->r;
	my $cookies	= $self->cookies;
	return undef unless ($cookies->{$cname});
	my %session	= $cookies->{$cname}->value;
	foreach (@$data) {
		return undef unless (exists $session{$_});
	}
	my $secret	= $self->secret || return undef;
	my $newhash	= MD5->hexhash(
					$secret .
					MD5->hexhash( join $;, $secret, @session{ @$data } )
				);
	
	## Verify MD5 hash ##
	warn __PACKAGE__ . "->verify_cookie: checking authenticity\n" if (DEBUG & DEBUG_WARN);
	warn __PACKAGE__ . '->verify_cookie:   hname[' . $hname . "]\n" if (DEBUG & DEBUG_WARN);
	warn __PACKAGE__ . '->verify_cookie: newhash[' . $newhash . "]\n" if (DEBUG & DEBUG_WARN);
	warn __PACKAGE__ . '->verify_cookie: oldhash[' . $session{$hname} . "]\n" if (DEBUG & DEBUG_WARN);
	return undef unless ($newhash eq $session{$hname});
	warn __PACKAGE__ . "->verify_cookie: verified\n" if (DEBUG & DEBUG_WARN);
	## Verified! ##
	
	$self->{$cname.'_verified'} = 1;
	$self->{$cname.'_session'} = \%session;
	return $self->{$cname.'_session'};
} # END of verify_cookie


=item C<verify_user> ( $userid )

Verifies that session in cookie is valid.  
Returns undef if not verified.

=cut

sub verify_user {
	my $self	= shift;
	return undef unless ref($self);
	my $br		= shift;
	my $session;
	return undef unless (
		$session = $self->verify_cookie(
			'user_key','_HASH',
			[ qw(_TIME _EXPIRES _BR) ]
		)
	);
	return $session;
} # END of verify_user


=item C<make_cookie> ( $name, $value [, $expires [, $path [, $domain] ] ] )

Creates a CGI Cookie object.

=cut

sub make_cookie {
	my $self	= shift;
	return undef unless ref($self);
	my $name	= shift || return undef;
	my $value	= shift || 0;
	my $expires	= shift;
	my $path	= shift;
	my $domain = shift || $self->{'domain'};

# warn "setting cookie [$name] with prefix [$COOKIE_PREFIX]" if (DEBUG & DEBUG_DUMPER);
  $name = $COOKIE_PREFIX . $name;

  return CGI::Cookie->new(-NAME		=> $name,
							-EXPIRES	=> $expires,
							-PATH		=> $path,
							-DOMAIN		=> $domain,
							-VALUE		=> $value
						);
} # END of make_cookie


=item C<add_cookie> ( $cookie )

Adds the cookie to Apache request headers.

=cut

sub add_cookie {
	my $self	= shift;
	return undef unless (ref $self);
	my $cookie	= shift;

	my $cookie_name = $cookie->name;

	my $r = $self->r;
	# set the cookies in the latest/deepest request as that's what gets
	# sent back to the client
	$r = $r->next while $r->next && $r->next->is_main;
	warn "Setting $cookie_name in r$$r" if DEBUG & DEBUG_WARN and $r != $self->r;

	warn __PACKAGE__ . "->add_cookie " . Data::Dumper::Dumper($cookie) if(DEBUG & DEBUG_DUMPER);

	# check of already existing cookies, and set them back to the headers array
	# this may seem incredibly stupid, but it's the only way to get cookies to work, seems to me
	# that you should be able to set an array of cookie values in the set method of headers_out
	# or at least modify the values as if it were a true hash table
	my $headers_out = $r->err_headers_out;
	if (my @cookies = $headers_out->get('Set-Cookie')) {

		# delete old values
		$headers_out->unset('Set-Cookie');

		# add back all except the one we're updating
		foreach my $cookie_str (@cookies) {
			$headers_out->add('Set-Cookie', $cookie_str)
			    unless $cookie_str =~ /^$cookie_name=/;
		}
	}
    else { # first time setting cookies
        # When setting cookies we do not want public caches to store the page because they cache the Set-Cookie headers
        $headers_out->set('Cache-Control', 'private');
    }

	# add the cookie to the apache headers
	$headers_out->add('Set-Cookie', $cookie);

	# add the cookie to our cache
	$self->cookies->{$cookie_name} = $cookie;

	warn __PACKAGE__ . "->add_cookie new cookies in r$$r: "
					. Data::Dumper::Dumper([$headers_out->get('Set-Cookie')])
					if(DEBUG & DEBUG_DUMPER);

	return undef;

} # END of add_cookie


=item C<sessionid> (  )

Caches the sessionid and returns the sessionid if the sessionid exists.

=cut

sub sessionid {
	my $self	= shift;
	return undef unless (ref $self);
	return $self->{'sessionid'} if ($self->{'sessionid'});
	my $cookies	= $self->cookies;
	return undef unless (defined $cookies->{'sessionid'});
	my $sessionid = $cookies->{'sessionid'}->value;
	if (!$sessionid or !is_valid_session_unique_id($sessionid)) {
		warn "Invalid sessionid cookie = '$sessionid'";
		return undef;
	}
	$self->{'sessionid'} = $sessionid;
	return $self->{'sessionid'};
} # END of sessionid


=item C<new_session> (  )

Creates a new session id and caches it in the Apache notes and returns 
the sessionid if the sessionid exists.

=cut

sub new_session {
	my $self		= shift;
	warn __PACKAGE__ . "->new_session\n" if (DEBUG & DEBUG_WARN);
	my $sessionid	= session_unique_id;
	$self->r->notes('sessionid', $sessionid);
	return $sessionid;
} # END of new_session


=item C<br> (  )

Grabs the br from the cookie or creates a new one, then returns it.

=cut

sub br {
	my $self	= shift;

	return $self->{'br'} if exists $self->{'br'};

	my $cookies = $self->cookies;
	my $br      = $cookies->{'br'} && $cookies->{'br'}->value;

	if ($br and !is_valid_global_unique_id($br)) {
		warn "Invalid br cookie = '$br'";
		delete $cookies->{'br'};    # Will force the Set-Cookie header to be sent
		$br = undef;                # force creating a new br value
	}

	$br ||= $self->identity_number;
	$self->{'br'} = $br;
	$self->r->notes('br', $br);
	return $br;
} # END of br


=item C<identity_number> (  )

Creates a new br and returns it.

=cut

sub identity_number {
	my $self		= shift;
	my $precision	= shift || 2; ### 1 is low, 2 is high
	my $ident = global_unique_id;
	warn "Identity Number " . $ident if (DEBUG & DEBUG_WARN);
	return $ident;
} # END of identity_number


=item C<cookies> (  )

Caches the cookies and returns the cookie hash if cookies exists.

=cut

sub cookies {
	my $self = shift;
	return undef unless (ref $self);
	return $self->{'cookies'} ||= $self->get_cookies();
} # END of cookies


=item C<get_cookies> (  )

Returns the cookie hash if cookies exists.

=cut

sub get_cookies {
	my $r = shift->r;
	warn __PACKAGE__."->get_cookies from r$$r header\n" if DEBUG & DEBUG_WARN;
	# S1096:  CGI::Cookies does not parse cookies separated by , correctly, so we change to the char it does support 
	(my $cookie = $r->header_in('Cookie')) =~ tr/,/;/;
	my %cookies = CGI::Cookie->parse( $cookie );

    return \%cookies if $COOKIE_PREFIX eq "";

	my %processed_cookies = ();

	# remove prefix and cookies without prefix
  	foreach (keys %cookies) {
  	  next unless $_ =~ /^$COOKIE_PREFIX(.*)$/; # remove prefix before passing back, ignore cookies w/out the prefix
  	  $processed_cookies{$1} = $cookies{$_};
  	}
	
    return \%processed_cookies;
} # END of get_cookies


=begin comment

Returns the remote IP

=end comment

=cut

sub _remote_ip_address {
	my $self 	= shift;
	return undef unless ref($self);	
	my $r 		= $self->r;

	unless (exists $self->{'_remote_ip'}) {
		my $header 	= $r->headers_in->{'X-Forwarded-For'};
		if ( my $ip = (split /,\s*/, $header)[-1] ) {	# /
			$r->connection->remote_ip($ip);				# This MODIFIES remote_ip to value of last proxy forward
		}
	}
	$self->{'_remote_ip'} ||= $r->connection->remote_ip;
} # END of _remote_ip_address


1;

__END__

=back

=head1 REVISION HISTORY

 $Log$
 Revision 1.8  2005/11/02 02:43:51  aelliston
 Added 'fr' to the list of cookie suffixes so that testing on dante.shopzilla.fr,
 hackmandev.shopzilla.fr, etc. will have the same cookie as the live site
 DT3381

 Revision 1.7  2005/09/01 14:58:43  thai
  - added better warnings to verify_cookie()

 Revision 1.6  2005/04/20 23:25:01  aelliston
 add_cookie: modified method so that all cookies are added throughout the request and added
 correctly at that

 DT 2223

 Revision 1.5  2005/04/14 23:18:21  aelliston
 Turned off warn

 Revision 1.4  2005/04/14 23:08:59  aelliston
 Fixed DEBUG and warnings

 Revision 1.3  2004/08/16 19:30:18  dpisoni
 add_cookie() - put cookies in err_headers_out in addition to normal headers_out

 Revision 1.2  2004/04/09 22:49:47  thai
  - added more POD
  - added add_cookie() method

 Revision 1.1  2003/12/17 23:47:16  draminiak
 New Session.pm and supporting modules


=head1 PREVIOUS REVISION HISTORY

 Revision 1.26  2003/06/25 23:29:28  mhynes
 fixing bad domain for international cookie

 Revision 1.25  2003/06/17 18:00:26  matthew
 added support for international sites

 Revision 1.24  2002/04/05 22:52:47  fred
 this is much better in terms of creating decent identifiers

 Revision 1.21  2001/11/19 22:50:47  fred
 that a ref not a value!

 Revision 1.20  2001/11/09 22:43:12  fred
 oops warnings

 Revision 1.19  2001/11/09 22:14:07  fred
 that was a bad mistake, poorly localized var

 Revision 1.18  2001/11/09 03:06:38  fred
 travolta/modules/Travolta/Session.pm

 Revision 1.17  2001/11/02 00:52:52  fred
 moved br to notes

 Revision 1.16  2001/04/13 20:01:02  jcfant
 make the merchants use the same secret as the dantes have been using, so that
 they share sessions (since they share a database)

 Revision 1.15  2000/09/28 17:15:58  sarab
 change for merchant servers

 Revision 1.14  2000/09/27 22:17:30  sarab
 make $secret server dependent

 Revision 1.13  2000/09/26 18:03:01  cnation
 This should fix the bizrate.com Cookie problem.

 Revision 1.12  2000/08/31 18:54:15  cnation
 Doh! fixed regex problem.

 Revision 1.11  2000/08/31 07:14:47  cnation
 Fixed the domain regex for cookies, let me know if your still having troubles.

 Revision 1.10  2000/08/16 04:36:26  cnation
 - made the $r argument optional for new() to compensate for
 	broken bs login code
 - modified the hostname substitution to include the leading
 	dot (it's a cookie thing)

 Revision 1.9  2000/08/04 22:04:59  cnation
 Using $r->host_name for the cookies domain, this is vhost safe.
 I also modified the regex a bit so that it only uses the two
 top-level domains i.e. bizrate.com and parses out a possible port
 number.

 Revision 1.8  2000/08/04 13:54:24  cnation
 Some small changes to handle hash keys without values. Like type at the moment.

 Revision 1.7  2000/08/03 22:14:36  cnation
 Using the new cookie handling to support agents, soon to come

 Revision 1.6  2000/07/26 00:00:45  cnation
 removed infinite loop between userid and verify_user (again)

 Revision 1.5  2000/07/25 21:02:52  cnation
  - added POD
  - removed _IP from verify_user(), can't see how it ever worked
  - removed the rest of the user fields from the hash in make_user()

 Revision 1.4  2000/07/25 16:01:59  cnation
  removed reminent else block in verify_user

 Revision 1.3  2000/07/25 16:00:18  cnation
  - removed infinite loop between userid and verify_user

 Revision 1.2  2000/07/24 20:59:17  cnation
 removed IP from cookie certificate.

 Revision 1.4  2000/07/24 19:21:17  zack
 new() drops the port number from the cookie domain, it was breaking the
 Mozilla/sandbox combo

 Revision 1.3  2000/07/24 19:19:58  adam
  took out warn

 Revision 1.2  2000/07/24 18:42:43  adam
 added methods
  - userid
  - sessionid
  - cookies
  - session

 Optimized verify_user
 Added sanity

 Revision 1.1  2000/07/21 22:47:11  thai
  - initial commit
  - user verification/authentication/certificate

=cut

vim: ts=4:sw=4
