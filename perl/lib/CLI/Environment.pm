# ----------------------------------------------------------------- #
# package CLI::Environment
# Environment.pm
# ----------------------------
# $Revision: 1.4 $
# $Date: 2003/01/22 00:56:51 $
# ----------------------------------------------------------------- #
# DESCRIPTION OF FILE
#	Environment.pm,  Evironment Settings class for Command Line scripts.
# ----------------------------------------------------------------- #
package CLI::Environment;

=head1 NAME

CLI::Environment

=head1 SYNOPSIS

 use Environment;
 my $env = Environment->new( \%hash, "n", "m=s", "c=s" );

=head1 DESCRIPTION

The class handles the environment variables passed from the command line.

=head1 REQUIRES

 use strict;
 use Getopt::Long qw(GetOptions);
 use Sys::Hostname;
 use Data::Dumper;
 use Class::Accessor::Fast;

 use base qw(Class::Accessor::Fast);

=head1 EXPORTS

Nothing

=cut

use strict;
use Getopt::Long qw(GetOptions);
use Cwd qw(realpath);
use Sys::Hostname;
use Data::Dumper;
use Class::Accessor::Fast;

our ($VERSION, @ISA);
use constant DEBUG_NONE     => 0b00000000;
use constant DEBUG_WARN     => 0b00000001;
use constant DEBUG_DUMPER   => 0b00000010;
use constant DEBUG_TRACE    => 0b00000100;
use constant DEBUG_INIT     => 0b00001000;
use constant DEBUG_SUBCLASS => 0b00010000;
use constant DEBUG_TEST     => 0b00100000;
use constant DEBUG_ALL      => 0b00111111;
use constant DEBUG          => DEBUG_NONE;    # | DEBUG_WARN | DEBUG_DUMPER | DEBUG_TRACE | DEBUG_INIT | DEBUG_SUBCLASS | DEBUG_TEST | DEBUG_ALL;

use constant FIELDS => [qw(_classes)];

use base qw(Class::Accessor::Fast);

# ----------------------------------------------------------------------------------------------- #

BEGIN {
	$VERSION = do { my @REV = split(/\./, (qw$Revision: 1.6 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1] / 1000)) };
	__PACKAGE__->mk_accessors(@{FIELDS()});
}

# ----------------------------------------------------------------------------------------------- #


sub CONSTRUCTORS { }

=head1 METHODS

=head2 CONSTRUCTORS

=over 4

=item C<new> ( $data )

Create a new Object.

=cut

sub new {
	my $self  = shift;
	my $class = ref($self) || $self;
	my $env   = shift || {};
	GetOptions($env, "h", "s", "l", "p", "d=s", "v=s", "e=s", "t=s", "c=s", "code=s", @_);
	## pager/editor ##
	$env->{'_pager'} = `echo \$VISUAL`;
	chomp $env->{'_pager'};
	## current user ##
	$env->{'_user'} = `echo \$USER`;
	chomp $env->{'_user'};
	## current sandbox ##
	$env->{'_sbox'} = `echo \$SANDBOX`;
	chomp $env->{'_sbox'};
	## hostname ##
	$env->{'_host'} = Sys::Hostname::hostname;
	chomp $env->{'_host'};
	## gzip ##
	$env->{'_gzip'} = `which gzip`;
	chomp $env->{'_gzip'};
	warn __PACKAGE__ . '->new: ' . Data::Dumper::Dumper($env) if (DEBUG & DEBUG_DUMPER);
	return bless $env, $class;
}    # END of new


######################################################################

sub STATIC_METHODS { }

=back

=head2 STATIC METHODS

=over 4

=item C<usage> (  )

Prints the usage content.

=cut

sub usage {
	print qq!
		-h         help
		-s         shell
		-l         write to a log file
		-p         turn on profiling
		-d=#       debug level
		-v=#       verbose level
		-t=#       test loop/iteration
		-e=string  prod|qa|dev enviroment
		-c=string  country code

!;
	exit(0);
}    # END of usage


######################################################################

sub OBJECT_METHODS { }

=back

=head2 OBJECT METHODS

=over 4

=item C<as_hash>

Returns the CLI::Environment object as a hash with internal properties filtered out

=cut

sub as_hash {
    my $self = shift;

    my @fields = qw(conf confDir); # safe to merge with config file keys
    my %fields;
    @fields{@fields} = @{$self}{@fields}; # hash slice, cloned into a new hash

    return \%fields;
}


=item C<load_classes> ( @classes )

Loads the classes on demand.

=cut

sub load_classes {
	my $self = shift;
	$self->_classes({}) unless ($self->_classes);
	if (@_) {
		foreach (@_) {
			eval "use $_;";
			$self->_classes->{$_} = 1;
		}
	} else {
		require CLI::Data;
		require CLI::Data::SQL;
		require CLI::StaticData;
		require CLI::SearchEngine;
		require CLI::Profiler;
		$self->_classes->{'CLI::Data'}         = 1;
		$self->_classes->{'CLI::Data::SQL'}    = 1;
		$self->_classes->{'CLI::StaticData'}   = 1;
		$self->_classes->{'CLI::SearchEngine'} = 1;
		$self->_classes->{'CLI::Profiler'}     = 1;
	}
}


=item C<get_data_directory> ( $file_path )

Gets the current active directory.

=cut

sub get_data_directory {
	my $self  = shift;
	my $path  = shift || return;
	## /netapp/PUB/pr/yahoo/US/20090408 ##
	my @parts = split('/', $path);
	pop @parts;
	my $dir   = join('/', @parts);
	my $list  = File::List->new( $dir );
	$list->show_only_dirs();
	my @dirs  = sort @{ $list->find( $dir ) };
	my $count = 1;
	$count    = substr($dirs[-1], -3, 2) if (@dirs);
	while (-e $path . sprintf("%02d", $count)) {
		$count++;
	}
	$path .= sprintf("%02d", $count);
	return (split('/', $path))[-1];
}


=item C<get_active_directory> ( $file_path [, $country_code ] )

Gets the current active directory.

=cut

sub get_active_directory {
	my $self = shift;
	my $path = shift || return;
	my $code = shift || $self->country_code;
	$path    = sprintf($path, $code);
	if ($self->args('top')) {
		$path =~ s!/pr/data/!/pr/data/top/!;
		$path =~ s!/active!/top!;
	}
	$path = realpath( $path ) || $path;
	return (split('/', $path))[-1];
}


=item C<user> (  )

Returns the user that executed the script as determined by the $USER environment 
variable.

=item C<pager> (  )

Returns the pager or editor of the user that executed the script as determined 
by the $VISUAL environment variable.

=item C<host> (  )

Returns the host machine that the script was executed on.

=item C<sbox> (  )

Returns the sandbox of the user that executed the script as determined by the 
$SANDBOX environment variable.

=cut

sub user  { $_[0]->{'_user'} }
sub pager { $_[0]->{'_pager'} }
sub host  { $_[0]->{'_host'} }
sub sbox  { $_[0]->{'_sbox'} }


=item C<totals> ( $type [, $count ] )

Returns the total count of the $type given.  If $count is given then it is 
incremented by that $count value.

=cut

sub totals {
	my $self  = shift;
	return unless (ref $self);
	my $type  = shift || return 0;
	my $count = shift || 0;
	return $self->{'_totals_' . $type} += $count;
}    # END of totals

=item C<debug> ( $debug )

Returns the debug level.  Returns true if the $debug value given matches the 
debug value given at startup.

=cut

sub debug {
	my $self  = shift;
	return unless (ref $self);
	my $debug = shift || 0;
	return unless ($self->{'d'});
	return ($self->{'d'} == $debug) if ($debug);
	return $self->{'d'};
}    # END of debug


=item C<verbose> ( $verbose )

Returns the verbose level.  Returns true if the $verbose value given matches the 
verbose value given at startup.

=cut

sub verbose {
	my $self    = shift;
	return unless (ref $self);
	my $verbose = shift || 0;
	return unless ($self->{'v'});
	return ($self->{'v'} >= $verbose) if ($verbose);
	return $self->{'v'};
}    # END of verbose


=item C<test> ( $test )

Returns the test level.  Returns true if the $test value given matches the 
test value given at startup.

=cut

sub test {
	my $self = shift;
	return unless (ref $self);
	my $test = shift || 0;
	return unless ($self->{'t'});
	return ($self->{'t'} == $test) if ($test);
	return $self->{'t'};
}    # END of test


=item C<env> ( $env )

Returns the environment value.  Returns true if the $env value given matches the 
environment value given at startup.

=cut

sub env {
	my $self = shift;
	return unless (ref $self);
	my $env  = shift || '';
	$self->{'e'} = 'dev' unless ($self->{'e'});
	return ($self->{'e'} eq $env) if ($env);
	return $self->{'e'};
}    # END of env


=item C<args> ( $flag [, $match ] )

Returns the environment value for the given flag.  Passing in the match param will 
attempt to match the instance data.

=cut

sub args {
	my $self  = shift;
	return unless (ref $self);
	my $flag  = shift || return '';
	my $match = shift || '';
	return ($self->{ $flag } eq $match) if ($match);
	return $self->{ $flag };
}    # END of args


=item C<set> ( $flag, $value )

Returns the environment value for the given flag.  Passing in the match param will 
attempt to match the instance data.

=cut

sub set {
	my $self  = shift;
	return unless (ref $self);
	my $flag  = shift || return '';
	my $value = shift || return '';
	return $self->{ $flag } = $value;
}    # END of set


=item C<unset> ( $flag )

Returns the environment value for the given flag.  Passing in the match param will 
attempt to match the instance data.

=cut

sub unset {
	my $self  = shift;
	return unless (ref $self);
	my $flag  = shift || return '';
	return $self->{ $flag } = undef;
}    # END of unset


=item C<server_root_relative> ( $file_path )

Returns the root path prepended to the path given.

=cut

sub server_root_relative {
	my $self = shift;
	return unless (ref $self);
	my $file_path = shift || return;
	return $file_path if ($file_path =~ m!^/!);
	return $self->root . $file_path;
}    # END of server_root_relative


=item C<gzip> ( $gzip )

Returns or sets the path to gzip.

=cut

sub gzip {
	my $self = shift;
	return unless (ref $self);
	return $self->{'_gzip'} if ($self->{'_gzip'} && !@_);
	my $gzip = shift || `which gzip`;
	return $self->{'_gzip'} = chomp $gzip;
}    # END of gzip

=item C<help> (  )

Returns true if the help flag is set.

=item C<root> (  )

Returns the root path.

=item C<shell> (  )

Initiates the shell.

=item C<logged> (  )

Returns true or false if logging is requested.

=item C<profile> (  )

Returns true or false if profiling is requested.

=item C<code> (  )

Returns the country code.  Default is US.

=item C<cluster> (  )

Returns true or false if we need to run as a cluster.

=cut

sub help         { $_[0]->{'h'} }
sub root         { $_[0]->{'r'} }
sub shell        { $_[0]->{'s'} }
sub logged       { $_[0]->{'l'} }
sub profile      { $_[0]->{'p'} }
sub code         { $_[0]->{'c'} || $_[0]->{'code'} || 'US' }
sub cluster      { $_[0]->{'cluster'} }
sub country_code { $_[0]->code }


######################################################################

sub REVISION_HISTORY { }

1;

__END__

=back

=head1 REVISION HISTORY

 $Log: Environment.pm,v $

=head1 SEE ALSO

L<perl>

=head1 KNOWN BUGS

None

=head1 AUTHORS

Thai Nguyen <thai@shopzilla.com>

=cut
