=head1 NAME

Gandolfini::Session - Handles session persistence

=head1 SYNOPSIS

 my $s = new Gandolfini::Session ( $r );

 $s->cookie;
 $s->sessionid;
 $s->date;
 $s->br;
 $s->cs_id;
 $s->get_data( key )
 $s->put_data( key [,value])

=head1 DESCRIPTION

Provides methods specific to the Session Object.

=head1 REQUIRES

 L<Time::Local|Time::Local>
 L<Time::HiRes|Time::HiRes>
 L<Storable|Storable>
 L<Apache::Constants|Apache::Constants>
 L<MIME::Base64|MIME::Base64>

=cut

package Gandolfini::Session;
use strict;
use warnings;

#use trace;
use Time::Local;
use Apache::Constants qw(:response);
use Time::HiRes qw( gettimeofday );
use Scalar::Util qw/reftype blessed/;
use Data::Dumper;
use Error ':try';
use Gandolfini::Error::RedirectRequired;

# Set constants
use constant DEBUG_NONE	        	=> 0b00000000;
use constant DEBUG_WARN	        	=> 0b00000001;
use constant DEBUG_DUMPER       	=> 0b00000010;
use constant DEBUG_GET           	=> 0b00000100;
use constant DEBUG_PUT           	=> 0b00001000;
use constant DEBUG			        => DEBUG_NONE;# | DEBUG_WARN;# | DEBUG_DUMPER;
use constant SESSION_MAX_DURATION	=> 1800;	# max elapsed time for session persistance
use constant SESSION_MAX_DATALENGTH	=> 2048;	# max size of session data
use constant TRACKERS		        => {
                                            rf		=> 1,
                                            mkt_id	=> 1,
                                            url_id	=> 1,
                                            eml_id	=> 1
                                        };

our $cookie_expiry_override; # for STABLE_FOR_TESTING mode


######################################################################

=item C<handler> ( $apache_req )

PerlAccessHandler call.
Establishes new sessions, or loads existing sessions.


=cut

sub handler : method {
	my $class	= shift;
	my $r		= shift;

	if (! defined ($r)) {
		warn Carp::longmess;
		kill('HUP',$$);
	}

	return DECLINED unless ($r->is_main());
	my $self = $class->new($r);

    # a redirect may be triggered during login
    my $redirect_code;
    try {
	    $self->valid_login();
    } catch Gandolfini::Error::RedirectRequired with {
        my $e = shift;
        $redirect_code = $e->status;
        $r->err_header_out(Location => $e->location);
    };
    return $redirect_code if defined $redirect_code;

	# what I'm seeing is the need for a 'notes' class, or at least a 'set_notes' method:
	my $remote_ip = $r->header_in('Client_ip') || $r->connection->remote_ip;
	$r->notes(Client_ip => $remote_ip) 								if (!$r->notes->{'Client_ip'});
	$r->notes(sessionid => $self->{'_sc'}->sessionid)				if (!$r->notes->{'sessionid'});
	$r->notes(br => $self->{'_sc'}->br)								if (!$r->notes->{'br'});

	$r->notes(htcnt => $self->get_data('tracker','htcnt'))	if ((!$r->notes->{'htcnt'}) && ($self->get_data('tracker','htcnt')));

	if (!$r->notes->{'time_hires'}) {
		my @uniquetime	= gettimeofday;
		$r->notes(time_hires => $uniquetime[0].$uniquetime[1]);
	}

	if (!$r->notes->{'cs_id'}) {
		my $cs_id = $self->cs_id || 0;
		$r->notes(cs_id => $cs_id) if ($cs_id);
	}

	if (!$r->notes->{'userzip'}) {
		my $userzip;
		my $cookies = $self->{'_sc'}->cookies;
		if ($cookies->{'userzip'}->{'value'}->[0] && ($cookies->{'userzip'}->{'value'}->[0] =~ /^\d{4,5}$/)) {
			$userzip = $cookies->{'userzip'}->{'value'}->[0];
		} else {
			$userzip = '0';
		}
		$r->notes(userzip => $userzip);
	}

	return OK;
} # END of handler

=item C<new> ( $apache_req )

Creates a new session object.

=cut

sub new {
	my $self	= shift;
	my $class	= ref($self) || $self;
	my $r		= shift || return undef;
	return $r->pnotes('_session') if (ref( $r->pnotes('_session') ));

	$cookie_expiry_override = "Thu Oct 22 13:55:01 2037" if $main::STABLE_FOR_TESTING;

	$self = bless( {}, $class );
	$self->_set_init($r);
	$r->pnotes( '_session', $self );

	$r->register_cleanup(sub { $self->cleanup });

	return $self;
} # END of new



=item C<valid_login> ( )

Checks to see if there is a valid session id.

=cut

sub valid_login {
	my $self	= shift;
	return undef unless (ref $self);
	my $scookie = $self->cookie();

	### if we don't know who it is, we better make a new user
	my $sessionid	= shift || $scookie->sessionid;
	my $br			= shift || $scookie->br;

	if ($sessionid) {
		warn __PACKAGE__ . "->valid_login: verified: SESSIONID ==> $sessionid, BR => $br\n" if (DEBUG & DEBUG_WARN);
		
		my $elapsed = $self->_load_data( $sessionid );
		if (defined $elapsed) {
			if ($elapsed <= SESSION_MAX_DURATION or $main::STABLE_FOR_TESTING) {
				## session is still good. ##
				my $htcnt = $self->get_data('tracker','htcnt') || 0;
				$self->put_data('tracker','htcnt', ($htcnt + 1))
					if $htcnt and not $main::STABLE_FOR_TESTING;
				warn __PACKAGE__ . "->valid_login: session $sessionid is still good ($elapsed <= ".SESSION_MAX_DURATION.")\n" if (DEBUG & DEBUG_WARN);
			} else {
				## session has expired. ##
				warn __PACKAGE__ . "->valid_login: session $sessionid is expired ($elapsed > ".SESSION_MAX_DURATION.")\n" if (DEBUG & DEBUG_WARN);
				delete $self->{_data};	# Don't want the old session data!
				$self->new_user();
			}
		} else {
			## we did not get back a session from the sessionserver. ##
			warn __PACKAGE__ . "->valid_login: session $sessionid is unknown to sessionserver\n" if (DEBUG & DEBUG_WARN);
			$self->new_user();
		}
	} else {
		## Need new user
		warn __PACKAGE__ . "->valid_login: missing session id or failed key validation (br $br)\n" if (DEBUG & DEBUG_WARN);
		$self->new_user();
	}
	$self->_set_cookies;

	return 1;
} # END of valid_login


=item C<new_user> ( )

Doh! user is new or invalid so lets make a new one.

=cut

sub new_user {
	my $self	= shift;
	return undef unless (ref $self);
	warn __PACKAGE__ . "->new_user have to reload session\n" if (DEBUG & DEBUG_WARN);

	delete $self->{'_data'} if(exists($self->{'_data'}));
	my $time = time;

	my $scookie	= $self->cookie();
	$self->put_data('_time', 'start_time', $time);
	$self->put_data('_time', 'timestamp', $time);
	$self->{'start_time'}	= $time;
	$self->{'sessionid'}	= $scookie->new_session;
	$self->{'br'}			= $scookie->br;
	$self->{'is_new_user'}	= 1;
	$self->put_data('tracker','htcnt',1);
	$self->_set_cookies;

	return 1;
} # END of new_user

=item C<create_session_cookie>

Create a new session cookie.

=cut

sub create_session_cookie {
    my $self = shift;
    my $r = $self->r;
    warn __PACKAGE__."->create_session_cookie for r$$r\n" if (DEBUG & DEBUG_WARN);
    return Gandolfini::Session::Cookie->new($r);
}

=item C<cookie> ( )

Returns the Session Cookie object.

=cut

sub cookie {

	my $self = shift;

	# if this is an instance than return the cookie in order of preference:
	# 1) _sc cookie (instance of this class)
	# 2) pnotes session cookie (set in previous handler)
	# 3) make new cookie and saves it to _sc
	if(ref($self)){
		$self->{'_sc'} ||= $self->_cookie_cached_or_new;
		return $self->{'_sc'};
	}

	# else return pnotes cookie or make a new one
	my $cookie = $self->_cookie_cached_or_new;

} # END of cookie


sub _cookie_cached_or_new {
	my $self = shift;	# class or instance
	my $r = $self->r;

	# return session cookie cached in current request
	my $cookie = $r->pnotes('_session_cookie');
	return $cookie if $cookie;

	# search up r->prev chain for session cookie
	for (my $prev = $r->prev; $prev && !$cookie; $prev = $prev->prev) {
		$cookie = $prev->pnotes('_session_cookie');
		warn "Adopting _session_cookie in r$$prev for r$$r"
			if $cookie and DEBUG & DEBUG_WARN;
	}

	# if we couldn't find an existing one the create a new one
	$cookie ||= $self->create_session_cookie;

	# cache session cookie in current request
	$r->pnotes('_session_cookie', $cookie);

	return $cookie;
}

=item C<sessionid> ( )

Returns the session id.

=cut

sub sessionid		{ $_[0]->{'sessionid'}	}


=item C<br> ( )

Returns the BR value from the coookie.

=cut

sub br				{ $_[0]->cookie->br		}

=item C<is_new_user> ( )

Returns true or false if the user is new or not.

=cut

sub is_new_user		{ $_[0]->{'is_new_user'}	}

=item C<r> ()

Returns the Apache request object.

=cut

sub r {
	ref($_[0]) && (return $_[0]->{'_r'} ||= Apache->request());
	Apache->request();
} # END of r

=item C<get_data> ( $key )

=item C<get_data> ( $namespace , $key )

Returns the value of $key from session data.
If $namepace is provided, return $key from that $namespace, otherwise, from the null namespace.

=cut

sub get_data {
	my $self	= shift;
	my $class	= ref($self) || do { warn __PACKAGE__ . "->get_data $self is not an object"; return undef; };
	my($namespace, $key);
	if (@_ == 2) {
		($namespace, $key) = @_;
	} elsif (@_ == 1) {
		$namespace = '';
		$key = $_[0];
	} else {
		return undef;
	}
	return undef unless (exists($self->{'_data'}) && exists($self->{'_data'}->{$namespace})); # No Data (sanity)
	return undef unless (exists $self->{'_data'}->{$namespace}->{$key});	# No Value

	warn __PACKAGE__ . "->get_data returning for $namespace->$key: "
		. $self->{'_data'}->{$namespace}->{$key} . "\n" if(DEBUG & DEBUG_GET);

	return $self->{'_data'}->{$namespace}->{$key};							# Success
} # END of sub get_data


=item C<put_data> ( $key [, $value ] )

=item C<put_data> ( $namespace , $key [, $value ] )

Replaces (or creates) the value of $key from session data with $value. Returns the new value.
If $value is undefined, removes the value.  If $namespace is undefined, uses the null namespace.

=cut

sub put_data {
	my $self	= shift;
	$self->_init_data();
	my($key, $namespace, $value);
	if (@_ == 3) {								# set value for key in namespace
		($namespace, $key, $value) = @_;
	} elsif (@_ == 2) {
		if (exists $self->{_data}->{$_[0]}) {	# delete value for key in namespace
			($namespace, $key) = @_;
		} else {								# set value for key in null namespace
			$namespace = '';
			($key, $value) = @_;
		}
	} elsif (@_ == 1) {							# delete value for key in null namespace
		$namespace = '';
		$key = $_[0];
	} else {									# wrong number of arguments
		return undef;
	}

	if($key =~ /;|\|::/ || $namespace =~ /;|\|::/){
		my $text =  "Bad call to put_data in Gandolfini::Session, key or namespaces cannot ";
		$text .= "contain the following chars: ; | ::"; 
		Error->throw(-text => $text);
	}

	if ((exists($self->{'_data'}->{$namespace})
				&& exists($self->{'_data'}->{$namespace}->{$key})
				&& $value)
			&& ($self->{'_data'}->{$namespace}->{$key} eq $value)) {
		warn __PACKAGE__ . "->put_data returning value [$namespace][$key][$value]\n" if (DEBUG & DEBUG_PUT);
		return $self->{'_data'}->{$namespace}->{$key};

	} elsif (!defined($value)) {

		warn __PACKAGE__ . "->put_data removing value [$namespace][$key]["
						. $self->{'_data'}->{$namespace}->{$key} . "]\n" if (DEBUG & DEBUG_PUT);

		delete $self->{'_data'}->{$namespace}->{$key};
		$self->save_session_to_cookie(); 

	} else {

		warn __PACKAGE__ . "->put_data replacing value [$namespace][$key][$value]\n" if (DEBUG & DEBUG_PUT);
		$self->{'_data'}->{$namespace}->{$key} = $value;
		$self->save_session_to_cookie(); 

	}

	return undef;

} # END of sub put_data

=item C<save_session_to_cookie>

Public method that will save the session to the cookie header after the lifespan of the request

=cut
sub save_session_to_cookie {
	my $self = shift;
	return undef unless(ref($self));

	warn __PACKAGE__ . "->save_session_to_cookie: " . Data::Dumper::Dumper($self->{'_data'}) if(DEBUG & DEBUG_DUMPER);

	my $cookie_str = $self->_create_string_from_namespaces([sort keys %{$self->{'_data'}}]);

	warn __PACKAGE__ . "->save_session_to_cookie: " . $cookie_str . " hostname: " . $self->r->hostname . "\n" if(DEBUG & DEBUG_PUT);

	if ( length $cookie_str > SESSION_MAX_DATALENGTH) {
		warn "[alert]: session cookie string is over " . int(SESSION_MAX_DATALENGTH / 1024) . "k: " . $cookie_str;
	}

	my $scookie = $self->cookie();
	my $data_cookie = $scookie->make_cookie( '_data', $cookie_str, $cookie_expiry_override || '+24h', '/');
	$scookie->add_cookie($data_cookie);
}

=item C<userzip> ( )

 Returns the user zip

=cut

sub userzip {
	my $self = shift;
	return $self->r->notes->{'userzip'};
}

=item C<cs_id> ( )

 Returns the user's contactsysid

=cut

sub cs_id {
	my $self	= shift;
	my $cookies	= $self->cookie->cookies;
	my $cs_id 	= $self->get_data( 'reg', 'cs_id' );
	$cs_id 		= $cookies->{'cs_id'}->value if ( !$cs_id && (blessed $cookies->{'cs_id'} and $cookies->{'cs_id'}->isa('CGI::Cookie')) );
	return $cs_id;
} # END of cs_id

=item C<total_elapsed_time> ( )

 Returns total elapsed time in session (from inception), in seconds.

=cut

sub total_elapsed_time {
	my $self = shift;
	return 0 unless defined $self->{start_time};
	return 1 if $main::STABLE_FOR_TESTING;
	return time() - $self->{start_time};
}

=item C<cleanup> ( )

This handles the cleanup for Gandolfini::Session. It's called by 

=cut

sub cleanup {
	my $self = shift;
	return undef unless (ref $self);
	return undef unless (ref($self->{'_data'}) && %{$self->{'_data'}});
	delete $self->{'_data'};
} # END of cleanup

=item C<_parse_cookie_str> ($unparsed_str)

Helper method to take our format and unparse it into a usable hash

=cut

sub _parse_cookie_str{

	my $self = shift;
	my $unparsed_str = shift;
	my $parsed_hash = {};

	# lookbehinds are for cases in which the value escapes our delemiters with a \
	my @namespaces = split(/(?<!\\)\|/, $unparsed_str);
	foreach my $namespace_data (@namespaces){

		$namespace_data =~ /(?<!\\)(\w+)::(.*)/;
		my $namespace = $1;
		my $pair_data = $2;
		# split on ; into pairs
		my @pairs = split(/(?<!\\);/, $pair_data);
		# iterate through all the pairs and parse out key=value
		foreach my $pair(@pairs){
			my ($key, $value) = split(/(?<!\\)=/, $pair, 2);
			# strip off the \ for escaped data
			# \\ should be converted to \
			$value = $self->_cookie_unescape( $value ) if $value;
			$parsed_hash->{$namespace}->{$key} = $value;
		}
	}

	return $parsed_hash;

}

sub _cookie_unescape {
	my $self = shift;
	my $value = shift;
	# take off escape characters in reverse order from putting them on:
	$value =~ s/(?<!\\)\\//go;
	$value =~ s/\[backslash\]/\\/go;
	$value =~ s/\[\+backslash\+\]/[backslash]/go;
	return $value;
}

=item C<_create_string_from_namespace> ( $namespaces )

Converts all the namespaces into a well-formatted cookie string
format: namespace::key=value;key=value|namespace::key=value

=cut

sub _create_string_from_namespaces{

	my $self = shift;
	my $namespaces = shift;
	my $cookie_str = "";
	# parse self (namespace, key, value) triples into a nice, cookie format
	if (defined($namespaces) && (ref($namespaces) eq 'ARRAY')) {
		foreach my $namespace (@$namespaces){
			next if($namespace eq '');
			next if((scalar (keys %{$self->{'_data'}->{$namespace}})) < 1); # skip if empty namespace

			$cookie_str .= $namespace . "::";

			foreach my $key (sort keys %{$self->{'_data'}->{$namespace}}){

				# empty data should be ignored
				next if(!defined($self->{'_data'}->{$namespace}->{$key}));
				$cookie_str .= $self->_cookie_escape( $namespace, $key );

			}
			# strip off last ; and replace with | 
			$cookie_str =~ s/;$/|/o;
		}
	}
	# strip of last |
	$cookie_str =~ s/\|$//o;

	return $cookie_str;
}

=item C<_cookie_escape> ($namespace, $key)

Escapes characters which create the serialized datastructure.

=cut

sub _cookie_escape {
	my $self = shift;
	my $namespace = shift;
	my $key = shift;
	# we should escape the values that have ; :: \ or | with \ 
	# and because of that, we first escape all \ characters:
	my $value = $self->{'_data'}->{$namespace}->{$key};
	$value =~ s/\[backslash\]/[+backslash+]/go;
#	$value =~ s/\[/[+/go;
#	$value =~ s/\]/+]/go;

	$value=~ s/\\/[backslash]/go;
	$value =~ s/;/\\;/go;
	$value =~ s/\|/\\|/go;
	$value =~ s/::/\\::/go;
	$value =~ s/=/\\=/go;
	return $key . "=" . $value . ";";
}


=item C<_set_init> ( $r )

Sets the data in the instance data of the Session Object..

=cut

sub _set_init {
	my $self	= shift;
	my $r		= shift;
	$self->{'_r'}		= $r;
	$self->{'_sc'}		= $self->_cookie_cached_or_new;
	$self->{'is_new_user'}	= 0;	# assume not a new user
} # END of _set_init

=item C<_init_data> ( )

Initializes internal data structure.

=cut

sub _init_data {

	my $self = shift;

	warn __PACKAGE__ . "->_init_data returned session data: "
					. Dumper( $self->{_data} ) . "\n" if (DEBUG & DEBUG_DUMPER);

	return undef if (exists($self->{_data}) && exists($self->{_data}->{''}));

	warn __PACKAGE__ . "->_init_data resetting _data\n" if (DEBUG & DEBUG_WARN);

	$self->{_data} = { '' => { } };

}


=item C<_load_data>

Gets the data object from a cookie
format: namespace::key=value;key=value|namespace::key=value

=cut

sub _load_data {
	my $self = shift;
	my $sessionid = shift;

	if(!ref($self)){
		Error->throw(-text => "Can't call _load_data not as a class method");
	}

	# reassemble the data from the unparsed string
	my $data_cookie = $self->cookie()->cookies->{'_data'};
	if (!$data_cookie) {
		warn __PACKAGE__."->_load_data: _data cookie not found\n" if DEBUG & DEBUG_WARN;
		return undef;
	}

	# set the session id for this object
	$self->{'sessionid'} = $sessionid;

	my $unparsed_str =  $data_cookie->value();

	warn __PACKAGE__ . "->_load_data cookie str: " . $unparsed_str . "\n" if(DEBUG & DEBUG_WARN);

	$self->{'_data'} = $self->_parse_cookie_str($unparsed_str);
	my $delta = 0;
	if ($self->valid_times) {

		# need to add this for the _init_data method, it's what says whether or not
		# this data object is defined or not
		$self->{'_data'}->{ '' } = { } ;

		my $time = $self->r->request_time;

		$self->{'start_time'} = $self->{'_data'}->{'_time'}->{'start_time'} || $time;
		$self->put_data('_time', 'start_time', $self->{'start_time'});

		# get old and make new stamp for elapsed time information
		my $old_time = $self->{'_data'}->{'_time'}->{'timestamp'} || $time;
		$time = $old_time if $main::STABLE_FOR_TESTING;
		$self->put_data('_time', 'timestamp', $time);
		$delta = $time - $old_time;
	} else {
		$delta = SESSION_MAX_DURATION + 1;
	}

	warn __PACKAGE__ . "->_load_data loaded data: " .  Data::Dumper::Dumper($self->{'_data'})
		if(DEBUG & DEBUG_DUMPER);

	# return the elapsed time
	return $delta;
}

sub valid_times {
	my $self = shift;
	my $valid = 1;
	unless ((exists($self->{_data}{_time}{timestamp})) && 
			(defined($self->{_data}{_time}{timestamp}))){
		$valid = 0;
	}
	unless ((exists($self->{_data}{_time}{start_time})) && 
			(defined($self->{_data}{_time}{start_time}))){
		$valid = 0;
	}
	return $valid;
}


=item C<_set_cookies>

Sets the sessionid and userid cookie if they need to be set.
Must be called as an object method against session.

=cut

sub _set_cookies {
	warn __PACKAGE__ . "->_set_cookies in _set_cookies\n" if (DEBUG & DEBUG_WARN);
	my $self	= shift;
	my $r		= $self->r;
	return undef unless (ref $self);

	my $scookie		= $self->cookie;
	my %incookies	= %{ $scookie->cookies };	# Cookies in header
	my $br			= $scookie->br;

	# use eq for sessionid here to silence warnings from corrupt cookies
	unless ($incookies{'sessionid'} && ($incookies{'sessionid'}->value eq $self->sessionid)) {
		warn __PACKAGE__ . "->_set_cookies \tsessionid in cookie doesn't match session in self\n" if (DEBUG & DEBUG_WARN);
		$scookie->add_cookie( $scookie->make_cookie(
									'sessionid',
									$self->sessionid,
									$cookie_expiry_override || '+1d',
									'/'
								)
							);
		warn __PACKAGE__ . "->_set_cookies adding sessionid cookie: " . $self->sessionid
			if(DEBUG & DEBUG_WARN);
	}
	unless ($incookies{'br'}) {
		warn __PACKAGE__ . "->_set_cookies setting new br\n" if (DEBUG & DEBUG_WARN);
		$scookie->add_cookie( $scookie->make_cookie(
									'br',
									$br,
									$cookie_expiry_override || '+10y',
									'/'
								)
							);
	}
	unless ($self->{'user_key_verified'} && $self->{'user_key_verified'} == 1) {
		warn __PACKAGE__ . "->_set_cookies setting key verification\n" if (DEBUG & DEBUG_WARN);
		### create the encrypted cookie for verification if br has changed
		#--------------------------------------------------
		# $scookie->add_cookie( $scookie->make_key( $br ) );
		#-------------------------------------------------- 
	}
} # END of _set_cookies


1;

__END__
vim: ts=4:sw=4
