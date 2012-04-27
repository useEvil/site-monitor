package RISock;

# Package that implements a socket subclass for the reverse index in-memory server
# This uses the binary communication protocol with prepended packet length

use IO::Socket;
use vars qw(@ISA);

use Gandolfini::DashProfiler extsys_profiler => [ "RISock" ];

BEGIN {
	@ISA	= qw(IO::Socket::INET);
	$|	= 1;

	foreach (@INC) {
		if (-f "$_/Time/HiRes.pm") {
			use Time::HiRes qw(time); # if we have Time::HiRes all the better
			last;
		}
	}
} # BEGIN

our $VERSION = '1.09';

########################
#### PUBLIC METHODS ####
########################

sub new {
# just blesses the socket into this class
	my $class = shift;
	my $self = { };
	bless ($self, $class);
	$self->{sock} = undef;
	return $self;
}

sub sock {
	my $self = shift;
	return $self->{sock};
}

sub open_sock {
# connects the socket
	my $self = shift;
	my $peer = shift || 'localhost';
	my $port = shift || 6666;
	my $timeout = shift || 5;
	my $class = ref($self);
	$self->_clear_error('');

        $self->{PeerAddr} = $peer;
        my $ps = extsys_profiler($self->{PeerAddr}) if extsys_profiler_enabled();

	$self->{sock}=$class->SUPER::new(
		PeerAddr=>$peer,
		PeerPort=>$port,
		Timeout=>$timeout,
		Proto=>"tcp") or return ($self->_store_error(join(' ; ',$@,$^E)));
#		Proto=>"tcp") or return;
#	$self->{sock}->autoflush(1);
	return 1;
}

sub close_sock {
# closes the socket
	my $self = shift;
	eval { $self->cmd('CLS:') };
	$self->{sock}->close or return ($self->_store_error($@));
#	$self->{sock}->close or return;
	return 1;
}

sub cmd {
# send a command through the socket
# make sure you always get results;
# WARNING: does not open or close the socket
	my $self = shift;
	my $cmd = shift;	# command
	my $resp;
	my @data;
	$self->_clear_error('');

        my $ps = extsys_profiler($self->{PeerAddr}) if extsys_profiler_enabled();

	$cmd = pack("N1", length($cmd)).$cmd;				# prepends to $cmd the length of cmd in network byte order
	$self->{sock}->syswrite($cmd,32000) or return ($self->_store_error(join(' ; ',$@,$^E)));	# sends length+cmd
	$self->{sock}->sysread($resp, 32000) or return ($self->_store_error(join(' ; ',$@,$^E))); # read data back, putting it in $resp
#	$self->{sock}->sysread($resp, 32000) or return; # read data back, putting it in $resp
	@data = unpack("N1 A*", $resp);					# split the response into its length ($data[0]) and actual response string ($data[1])
#	warn "COUNT: $data[0]\n";
	return $data[1];						# return response string
}

sub error { $_[0]->{'_err'}; } # retrieves the error 

sub _store_error {
# private method that stores an error
# in the error field for later retrieval
	my $self = shift;
	$self->{'_err'} = shift;
	return 0;
}

sub _clear_error {
# private method to clear the error field
	my $self = shift;
	$self->{'_err'} = undef;
	return 1;
}

# stubs

sub init_hash		{ return $_[0]->cmd('INI:') };
sub close_connection	{ return $_[0]->cmd('CLS:') };
sub add			{ return $_[0]->cmd(join(':', 'ADD', $_[1], $_[2])) };
sub update		{ return $_[0]->cmd(join(':', 'ADD', $_[1], $_[2])) };
sub get			{ return $_[0]->cmd(join(':', 'GET', $_[1])) };
sub current		{ return $_[0]->cmd('CUR:') };
sub first		{ return $_[0]->cmd('FST:') };
sub next		{ return $_[0]->cmd('NXT:') };
sub previous		{ return $_[0]->cmd('PRV:') };
sub last		{ return $_[0]->cmd('LST:') };
sub count_keys		{ return $_[0]->cmd('CNT:') };
sub debug_toggle	{ return $_[0]->cmd('DBG:') };
sub load_hash		{ return $_[0]->cmd('LFD:') };
sub save_hash		{ return $_[0]->cmd('STD:') };
sub version		{ return $_[0]->cmd('VER:') };
sub statistics		{ return $_[0]->cmd('STS:') };
sub help		{ return $_[0]->cmd('HLP:') };

1;
__END__

=head1 NAME

RISock - API to the reverse index in-memory server

=head1 SYNOPSIS

 $sock = RISock->new();
 $sock->open_sock($host, $port, $timeout);
 die "Error!" if ($sock->error);
 $res = $sock->cmd('ADU:this_is_the_key:this_is_the_value');
 $sock->close_sock;

=head1 DESCRIPTION

This module implements the C<RISock> class. Objects of this class
are used to communicate with the reverse index in-memory server riserv.

The C<RISock> objects use a binary communication protocol with
prepended packet length to communicate with riserv. The communication
is done over standard I<IO::Socket> sockets.

Objects in the C<RISock> class are persistent, even when the
underlying communication sockets are destroyed.

=head1 CONSTRUCTOR

=item new()

The new() method creates a new RISock object which is simply a
persistent container for the IO::Socket sockets.

=head1 METHODS

=item open_sock($host, $port, $timeout)

Opens a new socket to $host on $port, with a timeout of $timeout.
Returns 0 on error, 1 on success. The error can be retrieved with error().
Note that only one socket can be active per RISock object.

=item close_sock()

Closes the socket that was opened with open_sock.
Returns 0 on error, 1 on success. The error can be retrieved with error().

=item cmd($command)

Sends a command to riserv. Make sure you a socket has previously been opened.
Returns the response string or 0.
If 0 is returned, check for an error by using error().

=item init_hash()

Initializes and clears the riserv hash. Wipes everything.
Returns the response string or 0.
If 0 is returned, check for an error by using error().

=item close_connection()

Asks the riserv to close the connection from its end.
Do not call this method directly. Use instead close_sock().
This method is available for completeness only.
Returns the response string or 0.
If 0 is returned, check for an error by using error().

=item add($key, $value)

Adds a (key, value) pair to the hash.
Returns the response string or 0.
If 0 is returned, check for an error by using error().

=item update($key, $value)

Updates a key with a value. The key is added if it doesn't exist.
Returns the response string or 0.
If 0 is returned, check for an error by using error().

=item get($key)

Gets a value for a key.
Returns the response string or 0.
If 0 is returned, check for an error by using error().

=item current()

Retrieves the (key, value) pair at the pointer's current position.
Returns the response string or 0.
If 0 is returned, check for an error by using error().

=item first()

Retrieves the first (key, value) pair in the hash and resets the
pointer's position.
Returns the response string or 0.
If 0 is returned, check for an error by using error().

=item last()

Retrieves the last (key, value) pair in the hash and sends the pointer
to the last position.
Returns the response string or 0.
If 0 is returned, check for an error by using error().

=item next()

Retrieves the next (key, value) pair and increments the pointer's position.
Returns the response string or 0.
If 0 is returned, check for an error by using error().

=item previous()

Retrieves the previous (key, value) pair and decrements the pointer's position.
Returns the response string or 0.
If 0 is returned, check for an error by using error().

=item count_keys()

Gets the total number of (key,value) pairs in the hash.
Returns the response string or 0.
If 0 is returned, check for an error by using error().

=item debug_toggle()

Toggles debugging mode (on/off) on the riserv.
Debugging info is sent as part of the response strings.
Returns the response string or 0.
If 0 is returned, check for an error by using error().

=item load_hash( [ $path_to_file ] )

Loads a file into riserv. The file must be located on a mounted filesystem
of the machine that is running riserv.
The file format is KEY:VALUE on each line. The file must have Unix line endings.
If no filename is passed, riserv will load RIServ.dat from its working directory.
Returns the response string that includes the total number of keys loaded or 0.
If 0 is returned, check for an error by using error().

=item save_hash( [ $path_to_file ] )

Saves a file into riserv. The filesystem is one mounted on
the machine that is running riserv.  The file format is KEY:VALUE on each line.
If no filename is passed, riserv will save RIServ.dat in its working directory.
Returns the response string that includes the total number of keys loaded or 0.
If 0 is returned, check for an error by using error().

=item version()

Returns the riserv version information or 0.
If 0 is returned, check for an error by using error().

=item statistics()

Returns basic statistics on riserv's in-memory hash.
If 0 is returned, check for an error by using error().

=item help()

Returns help information regarding riserv.
If 0 is returned, check for an error by using error().

=head1 COPYRIGHT

Copyright 2003, BizRate.com

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHORS / ACKNOWLEDGMENTS

The I<riserv> reverse index in-memory server was developed by Sandy Ganz.
C<RISock> was developed by Henri Asseily.

=cut
