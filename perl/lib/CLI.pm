# ----------------------------------------------------------------------------------------------- #
# package CLI
# CLI.pm
# ----------------------------
# $Revision: 1.4 $
# $Date: 2003/01/22 00:56:51 $
# ----------------------------------------------------------------------------------------------- #
# DESCRIPTION OF FILE
#	CLI.pm,  Application class for Command Line scripts.
# ----------------------------------------------------------------------------------------------- #

=head1 NAME

CLI

=head1 SYNOPSIS

 use CLI;
 my $conf = CLI->new( \%hash, "n", "m=s", "c=s" );

=head1 DESCRIPTION

The is the super class for the command line interface.

=head1 REQUIRES

 use strict;
 use CLI::Environment;
 use CLI::Configuration;
 use CLI::Data;
 use CLI::Data::SQL;
 use CLI::StaticData;
 use CLI::SearchEngine;
 use CLI::Profiler;
 use Gandolfini::Date;
 use DirHandle;
 use File::stat;
 use Term::ReadLine;
 use Term::ANSIColor;
 use Data::Dumper;
 use Time::HiRes;
 use Class::Accessor::Fast;
 use Class::Fields;
 use Encode qw(decode encode);
 use Scalar::Util qw(reftype blessed);

=head1 EXPORTS

Nothing

=cut

package CLI;

use strict;
use CLI::Environment;
use CLI::Configuration;
use Gandolfini::Date;
use DirHandle;
use File::stat;
use Term::ReadLine;
use Term::ANSIColor;
use Data::Dumper;
use Time::HiRes;
use Class::Accessor::Fast;
use Class::Fields;
use Encode qw(decode encode);
use Scalar::Util qw(reftype blessed);
use Log::Log4perl qw(:easy);

our ($VERSION);
use constant DEBUG_NONE		=> 0b00000000;
use constant DEBUG_WARN		=> 0b00000001;
use constant DEBUG_DUMPER	=> 0b00000010;
use constant DEBUG_TRACE	=> 0b00000100;
use constant DEBUG_INIT		=> 0b00001000;
use constant DEBUG_DBI		=> 0b00010000;
use constant DEBUG_SUBCLASS	=> 0b00100000;
use constant DEBUG_TEST		=> 0b01000000;
use constant DEBUG_ALL		=> 0b01111111;
use constant DEBUG_CLASS	=> DEBUG_NONE;# | DEBUG_WARN | DEBUG_DUMPER | DEBUG_TRACE | DEBUG_INIT | DEBUG_DBI | DEBUG_SUBCLASS | DEBUG_TEST | DEBUG_ALL;

use constant FIELDS => [ qw(_env _conf _log _data _data_sql _static_data _search _terminal _date _stdout _profile) ];

use base qw(Class::Accessor::Fast);

# ----------------------------------------------------------------------------------------------- #

BEGIN {
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 1.5 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
	__PACKAGE__->mk_accessors( @{ FIELDS() } );
}

# ----------------------------------------------------------------------------------------------- #


sub CONSTRUCTORS { }

=head1 METHODS

=head2 CONSTRUCTORS

=over 4

=item C<new> ( $env [, $params ] [, $data ] )

Returns a CLI object.

=cut

sub new {
	my $proto   = shift;
	my $class   = ref($proto) || $proto;
	my $env     = shift || { };
	my @args    = @_;
	my($params, $data);
	if ($class->is_reftype( $args[0], 'ARRAY' )) {
		$params = shift @args || [ ];
		$data   = shift @args;
	} elsif ($class->is_reftype( $args[0], 'HASH' )) {
		$params = [ ];
		$data   = shift @args;
	} else {
		$params = [ @args ];
	}
	my $self    = $class->SUPER::new( $data );
	$self->_env( CLI::Environment->new( $env, @$params ) ) unless ($self->_env);
	$self->_conf( CLI::Configuration->new( { env => $self->environment->env } ) ) unless ($self->_conf);
	$self->_date( Gandolfini::Date->new( time, '%b %e %Y %T' ) ) unless ($self->_date);
	unless ($self->_log) {
		Log::Log4perl->easy_init( $INFO );
		$self->_log( get_logger() ) ;
	}
	if ($self->environment->_classes->{'CLI::Data'}) {
		$self->_data( CLI::Data->new( ) ) unless ($self->_data);
	}
	if ($self->environment->_classes->{'CLI::Data::SQL'}) {
		$self->_data_sql( CLI::Data::SQL->new( ) ) unless ($self->_data_sql);
	}
	if ($self->environment->_classes->{'CLI::StaticData'}) {
		$self->_static_data( CLI::StaticData->new( ) ) unless ($self->_static_data);
	}
	if ($self->environment->_classes->{'CLI::SearchEngine'}) {
		$self->_search( CLI::SearchEngine->new( ) ) unless ($self->_search);
	}
	if ($self->environment->_classes->{'CLI::Profiler'}) {
		$self->_profile( CLI::Profiler->new( ) ) unless ($self->_profile);
	}
	if ($self->environment->_classes->{'Term::ReadLine'}) {
		$self->_terminal( Term::ReadLine->new( 'Command Line' ) ) unless ($self->_terminal);
	}
	return $self;
} # END of new


# ----------------------------------------------------------------------------------------------- #

sub INITIALIZATION_METHODS { }

=back

=head2 INITIALIZATION METHODS

=over 4

=item C<init> ( $filename )

Takes a list of Constants and creates a virtual method.

=cut

sub init {
	my $self    = shift;
	return unless (ref $self);
	my $file    = shift || 'apps/cli/conf/cli.yaml';
	my $dbh_set = shift || $self->environment->env;
	
	## Initialize Date and Configuration Object ##
	$self->date;
	
	## Initialize Configuration ##
	$self->conf->init( $self->environment->server_root_relative( $file ) );
	
	## DBH file paths ##
	my $dbh_file    = $self->conf->get_dbh_file( $self->environment->root );
	my $auth_file   = $self->conf->get_auth_file( $self->environment->root );
	my $dbh_yaml    = $self->conf->load_encoded_file( $dbh_file, $auth_file );
	
	## Initialize Data classes ##
	if ($self->conf->can('proc_files')) {
		$self->logger->debug( '->init: data: proc_files: ' . Data::Dumper::Dumper( $self->conf->proc_files ) );
		foreach my $key (keys %{ $self->conf->proc_files }) {
			$self->logger->debug( "->init: data: key[${key}]\n" );
			my $procs        = $self->conf->proc_files->{$key}->{'procs'};
			my $classes     = exists($self->conf->proc_files->{$key}->{'class'}) ? $self->conf->proc_files->{$key}->{'class'} : [ ];
			my $proc_file   = $self->environment->server_root_relative( $procs );
			$self->logger->debug( "->init: data: proc_file[${proc_file}]\n" );
			$self->data->init( [ { $proc_file => $classes }, $dbh_yaml ], $dbh_set ) if ($proc_file);
		}
	} else {
		$self->data->init( [ $dbh_yaml ], $dbh_set ) if ($dbh_yaml);
	}
	## Initialize DBH ##
	$self->data->connect_all;
	
	## Initialize Static Data ##
	if ($self->conf->can('static_files')) {
		$self->logger->debug( '->init: static: static_files: ' . Data::Dumper::Dumper( $self->conf->static_files ) );
		foreach my $key (keys %{ $self->conf->static_files }) {
			$self->logger->debug( "->init: static: key[${key}]\n" );
			my $procs       = $self->conf->static_files->{$key}->{'procs'};
			my $classes     = exists($self->conf->static_files->{$key}->{'class'}) ? $self->conf->static_files->{$key}->{'class'} : [ ];
			my $static_file = $self->environment->server_root_relative( $procs );
			$self->logger->debug( "->init: static: static_file[${static_file}]\n" );
			$self->static_data->init( [ { $static_file => $classes } ] ) if ($static_file);
		}
	}
	
} # END of init


# ----------------------------------------------------------------------------------------------- #

sub OBJECT_METHODS { }

=back

=head2 OBJECT METHODS

=over 4

=item C<run> (  )

Process the script.

=cut

sub run {
	my $self = shift;
	return unless (ref $self);
	
	## print usage information ##
	$self->usage if ($self->environment->help);
	
	## init and print the configuration and environment ##
	$self->init( );
	$self->print_stdout( "\n##Script started [" . $self->date->as_string . "]##\n\n" );
	$self->print_stdout( "Configuration:\n" );
	$self->print_stdout( "\tEnvironment:      " . ($self->environment->env     || '') . "\n" );
	$self->print_stdout( "\tVerbose Level:    " . ($self->environment->verbose || '') . "\n" );
	$self->print_stdout( "\tDebug Level:      " . ($self->environment->debug   || '') . "\n" );
	$self->print_stdout( "\tTest Loop:        " . ($self->environment->test    || '') . "\n" );
	$self->print_stdout( "\tProfile:          " . ($self->environment->profile ? 'On' : 'Off') . "\n" );
	$self->print_stdout( "\tLogging:          " . ($self->environment->logged  ? 'On' : 'Off') . "\n" );
	
	## execute the main function ##
	$self->main;
	
	## print to a log file ##
	$self->print_log( $self->conf->path_to_log, $self->conf->log_cleanup ) if ($self->environment->logged);
	
	$self->print_stdout( "\n\n##Script ended [" . $self->date(time)->as_string . "]##\n\n" );
} # END of run


=item C<shell> (  )

Runs the shell environment.

=cut

sub shell {
	my $self = shift;
	while (1) {
		my $cmd = $self->terminal->readline( 'command> ' );
		$self->cmd( $cmd ) if ($cmd ne '');
	}
} # END of shell


=item C<cmd> (  )

Runs the commands given.

=cut

sub cmd {
	my $self	= shift;
	my $cmd		= shift;
	
	if ($cmd =~ /^(q|quit|exit)$/i) {
		print "\nGood Bye...\n\n";
		exit;
	} elsif ($cmd =~ /^(\w+)\s*(.*)/) {
		if ($self->can( $1 )) {
			$self->$1( split(/\s+/, $2) );
		}
	}
} # END of cmd


=item C<exit> ( [ $exit_code ] )

Exits the script.

=cut

sub exit {
	my $self	= shift;
	my $code	= shift || 0;
	exit( $code );
} # END of exit


=item C<date> ( $timelocal [, $format ] )

Returns a date object.

=cut

sub date {
	my $self = shift;
	if (@_) {
		my $time = shift || time;
		my $type = shift || '%d %b %Y %T';
		if ($time =~ /\D+/) {
			$self->_date( $self->_date->new_by_string( $time, $type ) );
		} else {
			$self->_date( $self->_date->new( $time, $type ) );
		}
	}
	return $self->_date;
} # END of date


=item C<environment> (  )

Returns the Environment Object.

=item C<conf> (  )

Returns the Configuration Object.

=item C<data> (  )

Returns the Data Object.

=item C<data_sql> (  )

Returns the SQL Data Object.

=item C<search> (  )

Returns the Search Engine Object.

=item C<static_data> (  )

Returns the Static Data Object.

=item C<terminal> (  )

Returns the Term ReadLine Object.

=item C<profile> (  )

Returns the Profile Object.

=item C<logger> (  )

Returns the Log4Perl logging object.

=cut

sub environment { $_[0]->_env         }
sub conf        { $_[0]->_conf        }
sub data        { $_[0]->_data        }
sub data_sql    { $_[0]->_data_sql    }
sub search      { $_[0]->_search      }
sub static_data { $_[0]->_static_data }
sub terminal    { $_[0]->_terminal    }
sub profile     { $_[0]->_profile     }
sub logger      { $_[0]->_log         }


=item C<print_stdout> (  )

Prints the messages to the screen.
(Revised to use Log::Log4perl.)

=cut

sub print_stdout {
	my $self    = shift;
	return unless (ref $self);
	my $text    = shift;
	my $verbose = shift || 0;

	if ($self->environment->verbose( $verbose )) {
            my $trimmed = $text;
            $trimmed =~ s/^\s*//; # remove leading whitespace
            $trimmed =~ s/\s*$//; # remove trailing whitespace
            $trimmed =~ tr/\t / /s; # compress repeated whitespace to a single space

            local $Log::Log4perl::caller_depth = $Log::Log4perl::caller_depth + 1; # set stack frame to caller
	    $self->logger->info($trimmed) 
        }

	return unless ($self->environment->logged);
	# accumulate output, if 'logged' is set
	my $stdout  = $self->_stdout || '';
	$self->_stdout( $stdout . $text );
} # END of print_stdout


=item C<print_log> ( [ $filename ] [, $days_old ] )

Prints the messages to the log.

=cut

sub print_log {
	my $self    = shift;
	return unless (ref $self);
	my $file    = shift || $self->conf->path_to_log;
	my $days    = shift || $self->conf->log_cleanup;
	my $logfile = $self->environment->server_root_relative( $self->date->as_string( $file ) );
	$self->print_stdout( "\n\tPrinting Log File:\t[${logfile}]##\n" );
	open(LOG, ">$logfile") || $self->print_stdout( "\t\tFailure: Couldn't open file:  ${logfile}, $!\n\n" );
		print LOG $self->_stdout;
	close(LOG);
	## gzip the file so that it's not so big ##
	my $gzip;
	chomp($gzip = `which gzip`);
	system($gzip, $logfile)  == 0
	    or die "$gzip $logfile: $!\n";
	die "$gzip: non-zero exit\n" if $?;
	$self->cleanup_logs( $file, $days );
} # END of print_log


=item C<print_elapsed> ( $start, $end )

Returns the elapsed time with seconds, minutes or hours.

=cut

sub print_elapsed {
	my $self    = shift;
	my $start   = shift || 0;
	my $end = shift || 0;
	return unless ($start && $end);
	my $total   = $end - $start;
	if ($total >= 3600) {
		return sprintf("%0.3f", ($total * 3600)) . 'min';
	} elsif ($total >= 60) {
		return sprintf("%0.3f", ($total * 60)) . 'min';
	} else {
		return sprintf("%0.3f", $total) . 'sec';
	}
}


=item C<cleanup_logs> ( [ $filename ] [, $days_old ] )

Remove the logs that are older than conf->log_cleanup.

=cut

sub cleanup_logs {
	my $self    = shift;
	return unless (ref $self);
	my $file    = shift || $self->conf->path_to_log;
	my $days    = shift || $self->conf->log_cleanup;
	$self->cleanup_files( $file, $days );
} # END of cleanup_logs


=item C<cleanup_files> ( [ $filename ] [, $days_old ] )

Remove the logs that are older than conf->log_cleanup.

=cut

sub cleanup_files {
	my $self    = shift;
	return unless (ref $self);
	my $file    = shift || $self->conf->path_to_file;
	my $days    = shift || $self->conf->file_cleanup;
	my $date    = $self->date->new();
	$date       -= $date->day2sec( $days );
	$self->print_stdout( "\tPurging Files Prior to:\t[${date}]\n", 4 );
	my $path    = $self->environment->server_root_relative( $self->date->as_string( $file ) );
	$path       =~ m!(.+)/([^/]+)!;
	my $pdir    = $1;
	my $dh      = DirHandle->new( $pdir );
	$self->print_stdout( "\tPurging Files in:\t[${pdir}]\n", 4 );
	if (defined $dh) {
		my $ls;
		while (defined($ls = $dh->read)) {
			chomp $ls;
			next unless ($ls);
			next if ($ls =~ /^\./);
			next if ($ls =~ /CVS/);
			my $full  = join('/', $pdir, $ls);
			$self->print_stdout( "\n\tChecking File:\t\t[${file}]\n", 4 );
			my $stats = stat( $full );
			if ($stats) {
				my $ddate = $date->new( $stats->mtime );
				$self->print_stdout( "\tCreated On:\t\t[${ddate}]\n", 4 );
				if ($ddate < $date) {
					unless (system( 'rm', '-Rf', $full )) {
						$self->print_stdout( "\tRemoved\n", 4 );
					}
				}
			}
		}
		undef $dh;
	}
}


=item C<gzip_file> ( $file )

gzip the file and return the file size.

stat()
   0 dev      device number of filesystem
   1 ino      inode number
   2 mode     file mode  (type and permissions)
   3 nlink    number of (hard) links to the file
   4 uid      numeric user ID of file's owner
   5 gid      numeric group ID of file's owner
   6 rdev     the device identifier (special files only)
   7 size     total size of file, in bytes
   8 atime    last access time in seconds since the epoch
   9 mtime    last modify time in seconds since the epoch
  10 ctime    inode change time in seconds since the epoch (*)
  11 blksize  preferred block size for file system I/O
  12 blocks   actual number of blocks allocated


functions:
  namely
  dev
  ino
  mode
  nlink
  uid
  gid
  rdev
  size
  atime
  mtime
  ctime
  blksize
  blocks

=cut

sub gzip_file {
	my $self    = shift;
	return unless (ref $self);
	$self->profile->start('gzip_file') if ($self->environment->profile);
	my $file    = shift or $self->logger->logdie("file: parameter required");

	my $command = $self->environment->gzip . " $file";
	system( $command ) == 0 or $self->logger->logdie("Can't perform: $command");
	my $stats   = stat( $file . '.gz' );
	$self->profile->stop('gzip_file') if ($self->environment->profile);
	return $self->_file_size( $stats->size );
}


=item C<is_reftype> ( $object, $reftype [, $isa ] )

Checks to see if the object/hash/array is of the same $reftype.

=cut

sub is_reftype {
	my $self    = shift;
	my $object  = shift || return;
	my $reftype = shift || return;
	my $isa     = shift || 0;
	return unless (ref $object);
	if (my $ref = blessed($object)) {
		return UNIVERSAL::isa( $object,  $reftype ) if ($isa);
		return ($ref eq $reftype);
	}
	if (my $ref = reftype($object)) {
		return ($ref eq $reftype);
	}
}


# ----------------------------------------------------------------------------------------------- #

sub INTERNAL_METHODS { }

# remove unwanted characters and make the content UTF-8

sub _wash {
	my $self = shift;
	my $data = shift || return '';
	my @matches = ($data =~ /(\&.+?;)/g);
	foreach my $match (@matches) {
		next if (($match =~ /\&\#?\d+?;/)
			  || ($match eq '&gt;')
			  || ($match eq '&lt;')
			  || ($match eq '&amp;')
			  || ($match eq '&quot;')
			  || ($match eq '&apos;'));
		$data =~ s/\Q$match\E//;
	}
	return encode('utf8', $data);
}


# change seconds to minutes or hours
# 4162.846711 secs -> 69.3807785166667 mins
# 12735.074367 secs -> 3.5375206575 hrs

sub _profile_time {
	my $self    = shift;
	my $start   = shift || 0;
	my $end     = shift || 0;
	return unless ($start && $end);
	my $total   = $end - $start;
	if ($total <= 60) {
		return sprintf("%0.3f", $total) . "sec(s)";
	} elsif ($total <= 3600) {
		return sprintf("%0.2f", ($total / 60)) . "min(s)";
	} else {
		return sprintf("%0.2f", ($total / 3600)) . "hr(s)";
	}
}


# change numbers to appropriate size values
# length > 9 is in the GB
# length > 6 is in the MB
# length > 3 is in the KB
# all else is in the Bytes

sub _file_size {
	my $self    = shift;
	my $value   = shift || 0;
	if (length($value) > 9) {
		return sprintf("%0.1fGB", $value / 1024000000);
	} elsif (length($value) > 6) {
		return sprintf("%0.1fMB", $value / 1024000);
	} elsif (length($value) > 3) {
		return sprintf("%0.1fKB", $value / 1024);
	} else {
		return sprintf("%0.1fB", $value);
	}
}

# ----------------------------------------------------------------------------------------------- #

sub REVISION_HISTORY { }

1;

__END__

=back

=head1 REVISION HISTORY

 $Log: CLI.pm,v $

=head1 SEE ALSO

L<perl>

=head1 KNOWN BUGS

None

=head1 AUTHOR

Thai Nguyen <thai@shozilla.com>

=cut
