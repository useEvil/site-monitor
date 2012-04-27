# Gandolfini::Data
# -------------
# $Revision: 1924 $
# $Date: 2008-05-20 11:23:00 -0700 (Tue, 20 May 2008) $
# -----------------------------------------------------------------------------

=head1 NAME

Gandolfini::Data - Thin Database Abstraction Class

=cut

package Gandolfini::Data;

=head1 SYNOPSIS

 use Gandolfini::Data;
 Gandolfini::Data->init( '/path/to/database/info.yaml' );
 my $s = Gandolfini::Data::Proc->stream_obj( @args );
 my $row = $s->next();
 $s->close();

=head1 DESCRIPTION

Gandolfini::Data is a thin database abstraction class. Using information about
database procs from a YAML metadata file, subclasses of Gandolfini::Data are
generated for each proc. Objects representing the rows returned by these procs
may be accessed using the C<stream_*> and C<list_*> methods.

=head1 REQUIRES

perl 5.6.0 or greater

L<DBI|DBI>

L<YAML|YAML>

L<Attribute::Handlers|Attribute::Handlers>

L<Gandolfini::Stream|Gandolfini::Stream>

L<Scalar::Util>

=head1 EXPORTS

Nothing

=cut

use strict;
use warnings;
use Carp qw(croak carp);
use Scalar::Util qw/reftype/;
require v5.6.0;	# for Attribute::Handlers

use DBI;
use DBIx::HA;
use YAML qw();
use Attribute::Handlers;
use Gandolfini::Stream;
use Gandolfini::DataDebugDupSQL qw(sql_execute_count_use);
use Sys::Hostname qw();
use Data::Dumper qw();
use Scalar::Util qw(reftype looks_like_number);
use Storable qw(dclone);

use Gandolfini::DashProfiler extsys_profiler => [ "Database", undef,
    context2edit => sub {
	# convert $dbh->{Name} values like
	# "server=dev_log01;database=logging;hostname=consumerdev.shopzilla.com"
	# into "logging.dev_log01", and, for gofer,
	# "url=http://pr-dbproxy-lb01:19000/pr_barbiedb;dsn=dbi:Sybase:database=prodep"
	# into "pr-dbproxy-lb01:19000/pr_barbiedb"
	local $_ = shift
        or return "error"; # e.g., $dbh was undef so $dbh->{Name} was undef
	$_ = $_->() if ref $_ eq 'CODE';
	our %context2edit_cache;
	return $context2edit_cache{$_} if $context2edit_cache{$_};
	my %kv = map { (split /=/, $_, 2)[0,1] } split /;/, $_;
	if ($kv{url}) { # gofer
	    $kv{url} =~ s{^https?://}{};
	    return $context2edit_cache{$_} = $kv{url};
	}
	return $context2edit_cache{$_} = $_ if !$kv{database}; # not a sane Sybase DSN
	return $context2edit_cache{$_} = "$kv{database}.$kv{server}";
    },
];

use MIME::Base64;

# for *_cached methods
use Storable qw(dclone);
our $get_default_cache;


######################################################################

our ($verbose, @ISA, @EXPORT_OK);

use constant DEBUG_NONE		=> 0b00000000;
use constant DEBUG_INIT		=> 0b00000001;
use constant DEBUG_DBI		=> 0b00000010;
use constant DEBUG_SUBCLASS	=> 0b00000100;
use constant DEBUG_SQL   	=> 0b00001000; # log executed sql statements 
use constant DEBUG_CACHE	=> 0b00010000;
use constant DEBUG			=> DEBUG_NONE; # | DEBUG_INIT | DEBUG_DBI;# | DEBUG_SUBCLASS;


BEGIN {
	@ISA		= qw(Exporter);
	require Exporter;
	@EXPORT_OK	= qw(DEBUG DEBUG_NONE DEBUG_INIT DEBUG_DBI DEBUG_SUBCLASS);
}

######################################################################

##### THIS IS FOR DBIx::HA INTEGRATION #####
our %database_set;
*database_set = *DATABASE::conf;
#####

=head1 METHODS

=head2 STATIC INITIALIZATION METHODS

=over 4

=item C<init ( \@data_sets, $dbh_mode )>

Reads the database meta information from the specified data sets.  Data sets
can be either filenames of YAML files or pre-loaded data structures., Generates
proc classes and initializing class variables. Returns TRUE if sucessful and
FALSE on failure.

=cut

sub init {
	my $proto	 = shift;
	my $class	 = ref($proto) || $proto;
	my $data_set = shift;
	my $dbh_mode = shift || 'dev';
	my $hostname = Sys::Hostname::hostname;

	# Data set can be a single filename or ref to a list of files
	if ( defined $data_set ) {
		if ( not ref($data_set) or reftype($data_set) ne 'ARRAY' ) {
			$data_set = [ $data_set ];
		}
	} else { # DEFAULT data set
		$data_set = [ 'data.yaml' ];
	}
    warn __PACKAGE__ . " $proto->init([@$data_set],$dbh_mode)\n" if (DEBUG & DEBUG_INIT); 

	our %dbh;								# Database handles and init string
	our %procs;								# procs and proc data
	our $default_dbh_set = $dbh_mode;		# De-implemented set-switching feature. May bring back later.

	# Load @dbdesc YAML data files specified by @$data_set
	our @dbdesc;
	foreach my $data_item (@$data_set) {

		my $dbdesc = '';

		# If the data item is a ref, we just include it since we probably did the parsing 
		# outside of here
		if ( ref($data_item) ) {
			$dbdesc = $data_item;
		}
		else {
		# Its a regular file, we load it as a normal yaml file
			$dbdesc = YAML::LoadFile($data_item) || do {
				warn __PACKAGE__ . " - failed to load YAML file $data_item, $!" if (DEBUG & DEBUG_INIT); 
				next; 
			};
		}

		push @dbdesc, $dbdesc;
		warn __PACKAGE__ . " - loaded DB config file $data_item\n" if (DEBUG & DEBUG_INIT);
	}
	return (carp(__PACKAGE__ . ' aborting: no files to load!') && undef) unless (@dbdesc);

	# Find "latest" desired block (iterate through files in reverse order)
	my($dbhdata, $procdata, $dbi_defaults, $dsn_rewrite);
	for my $dbdesc (reverse @dbdesc) {
		$dbhdata      ||= $dbdesc->{'dbh'};
		$dbi_defaults ||= $dbdesc->{'dbi_defaults'};
		$dsn_rewrite  ||= $dbdesc->{'dsn_rewrite'};
		if ($dbdesc->{'procs'}) {
			$procdata = { %{$procdata||{}}, %{$dbdesc->{'procs'}} };
		}
	}
	return (carp(__PACKAGE__ . " - Insufficient configuration in files (" . join(', ', @$data_set) . ")\n") && undef)
		unless (defined($dbhdata) && defined($procdata) && defined($dbi_defaults));

	# Establish DBH to databases defined in $dbh_mode
	my $handles = $dbhdata->{$dbh_mode} || $dbhdata->{DEFAULT};
	return (carp("Invalid database set specified: $dbh_mode") && undef)
		unless (ref $handles and reftype($handles) eq 'HASH');

	# drill-down into dsn_rewrite to pick set applicable to this $dbh_mode
	if ($dsn_rewrite) {
	  $dsn_rewrite = $dsn_rewrite->{$dbh_mode} || $dsn_rewrite->{DEFAULT};
	  # if there's a dsn_rewrite section, but we didn't use one, then mention it
	  print STDERR "No dsn_rewrite rules for $dbh_mode (and no DEFAULT rules)\n"
		if $verbose && not $dsn_rewrite;
	}
	if ($dsn_rewrite) {
		# make domain name available to the rewrite expression
		(my $domain = $hostname) =~ s/^.*?\.//; # remove hostname part
		# convert the rewrite expression into a subroutine
		while ( my ($name, $rule) = each %$dsn_rewrite ) {
			next unless $rule;
			print STDERR "dsn_rewrite rule $dbh_mode $name: $rule\n"
				if $verbose;
			die "dsn_rewrite $dbh_mode rule name '$name' doesn't match a $dbh_mode dbh section database name (misspelt?)\n"
				if not $handles->{$name};
			$dsn_rewrite->{$name} = eval qq{ use strict;
				sub { my (\$dsn,\$attr)=\@_; local \$_=\$dsn; $rule; return \$_ }
			};
			die "Unable to compile dsn_rewrite $dbh_mode $name rule: $@ (rule: $rule)"
				if $@;
		}
	}

	while (my($name, $db_stack) = each(%{ $handles })) {
		$database_set{$name} = {
					%{ $dbi_defaults->{DBIxHA} },			# Copy settings
					db_stack			=> [ ],				# DBI setting list
					callback_function	=> \&_callback_HA,	# How to reconnect
					failtest_function	=> \&DBIx::HA::FTF_SybaseASE,
		};
		foreach my $db (@$db_stack) {
			my $username = $db->{'username'};
			my $password = $db->{'password'};
			my $dsn      = $db->{'dsn'};
			
			# update settings if non_persistent (not using dbix-ha, override dbix-ha defaults)
			my $attr;
			if (exists $db->{'non_persistent'}) {
				$attr = $dbi_defaults->{DBI_non_persistent};
				$database_set{$name}->{dbi_connect_method}	= 'connect';
				$database_set{$name}->{connectoninit}		= 0;
				$database_set{$name}->{max_retries}			= 0;
				$database_set{$name}->{non_persistent}		= 1;
			}			
			else {
				$attr = $dbi_defaults->{DBI};
			}
			$attr = { %$attr }; # shallow copy

			$dsn =~ s/\$hostname/$hostname/;  # Replace $hostname value in DSN
			$dsn = $dsn_rewrite->{$name}->($dsn, $attr) || $dsn
				if $dsn_rewrite->{$name};

			push @{ $database_set{$name}->{db_stack} }, [ $dsn, $username, $password, $attr ];

			if ($verbose) {
				print STDERR "$dsn \n" if ($dsn);
				print STDERR "username: $username \n" if ($username);
			}
		}
	}

	#--------------------------------------------------
	# if ($verbose) {
	# 	local $Data::Dumper::Terse = 1;
	# 	warn 'dbh: ' . Data::Dumper::Dumper(\%database_set);
	# }
	#-------------------------------------------------- 

	# initialize and cache handles
	DBIx::HA->initialize();
	$dbh{$dbh_mode} = { map { $_ => undef } keys %$handles };

	while (my($proc, $pdata) = each(%$procdata)) {
		warn "-> $proc\n" if (DEBUG & DEBUG_INIT);
		
		#verify procdata dbh is valid
		if(!defined $database_set{$pdata->{'dbh'}}) {
			warn __PACKAGE__ . ": No dbh handle defined for '" . $pdata->{'dbh'} . "', cannot configure proc $proc";
			next;
		}
		
		
		$procs{$proc} = $pdata;
		$class->_subclass_init( $proc, $pdata );
	}
	
	return 1;
}


=item C<connect_all>

Connects to all persistent databases in the designated set, and caches DBHs for later use.
It will not connect handles specified as 'non_persistent'.

=cut

sub connect_all {
	our %dbh;
	our $default_dbh_set;
	
	my $connectct = 0;
	
	foreach my $handle (keys %{ $dbh{$default_dbh_set} }) {
	    $connectct += _connect($handle, $default_dbh_set);
	}
	
	return $connectct;
} # END of connect_all


=item C<disconnect_all>

Disconnects from all cached databases, clearing DBH cache.

=cut

sub disconnect_all {
	my $disconnectct = 0;
	our %dbh;
	foreach my $set (keys %dbh) {
		foreach my $handle (keys %{ $dbh{$set} }) {
		    $disconnectct += _disconnect($handle,$set);
		}
	}
	$disconnectct;
}

=back

=cut

######################################################################

=head2 ITERATOR AND LIST CONSTRUCTORS

=over 4

=item C<stream_obj ( @args )>

Returns an Gandolfini::Stream iterator object. This iterator will
return data objects representing rows returned by the referant's class'
proc given the arguments in @args.

N.B. - The database statement isn't prepared/executed until the stream is first initiated.
If next() is never called on the stream, the statement will not be needlessly executed.

=cut
sub stream_obj {
	my $proto	= shift;
	my $class	= ref($proto) || $proto;
	my @args	= @_;
	my $execute = sub { $proto->_execute( @args ) };
	
	my($rv, $sth, $dbh);
	my $rows	= 0;
	my $finished = 0;
	return Gandolfini::Stream->new( sub {
	    my $finish_flag = shift;
	    
		do { ($rv, $sth, $dbh) = $execute->(); undef $execute } if (defined $execute);
		
		if($finish_flag) {
		    if(!$finished) {
                my $finish_status = $proto->_finish( $dbh, $sth );
                $finished = 1;
                return $finish_status;
		    }
		    else {
		        return 0;
		    }
		}
		else {
            my $ps = extsys_profiler($dbh->{Name}) if extsys_profiler_enabled();
            my $data = (ref($sth) && $sth->fetchrow_hashref);
            undef $ps; # end sample
            
            if(!$data) {
                # if this is a non-persistent connection, then need to finish here
                if($proto->_non_persistent() && !$finished) {
                    $proto->_finish( $dbh, $sth );
                    $finished = 1;
                }
                return (undef $sth);
            }
            
            $data->{'_row'} = $rows++;
            return bless($data, $class);
        }
	});
}


=item C<stream_hash ( @args )>

Returns an Gandolfini::Stream iterator object. This iterator will
return hashrefs containing the columns and DataFields for each row returned
by the referant's class' proc given the arguments in @args.

=cut
sub stream_hash {
	my $proto	= shift;
	my $stream	= $proto->stream_obj( @_ ) or return;
	my @cols	= $proto->_cols();
	my $closed	= 0;
	return Gandolfini::Stream->new( sub {
		return undef if ($closed);
		if (scalar(@_)) {
			$stream->close();
			$closed	= 1;
			return undef;
		}
		my $obj	= $stream->next() || do { $closed = 1; return };
		my %hash	= map { $_ => $obj->$_() } @cols;
		return \%hash;
	} );
}

=item C<list_obj ( @args )>

Returns a LIST of objects. See C<stream_obj> for details on arguments
and the returned data objects.

=cut
sub list_obj {
	my $proto	= shift;
	my $stream	= $proto->stream_obj( @_ ) or return;
	my @array;
	while (my $obj = $stream->next()) {
		push(@array, $obj);
	}
	$stream->close();
	return @array;
}
*list_obj_cached = _make_cache_wrapper("list_obj");

=item C<list_hash ( @args )>

Returns a LIST of hashrefs. See C<stream_hash> for details on arguments
and the returned hashrefs.

=cut
sub list_hash {
    return shift->_list_hash_helper("list_obj", @_);
}
sub list_hash_cached {
    return shift->_list_hash_helper("list_obj_cached", @_);
}
sub _list_hash_helper {
	my $proto	= shift;
	my $method_name	= shift;
    my @objs = $proto->$method_name(@_); # list context
	my @cols = $proto->_cols();
    my @array;
	while (my $obj = shift @objs) {
		push @array, { map { $_ => $obj->$_() } (@cols) };
	}
	return @array;
}

sub get_obj {
	my $proto	= shift;
	my $stream	= $proto->stream_obj( @_ ) or return;
	my $obj		= $stream->next();
	$stream->close();
	return $obj;
}
*get_obj_cached = _make_cache_wrapper("get_obj");

sub get_hash {
	my $proto	= shift;
	my $stream	= $proto->stream_hash( @_ ) or return;
	my $hash	= $stream->next();
	$stream->close();
	return $hash;
}
*get_hash_cached = _make_cache_wrapper("get_hash");

=item C<_make_cache_wrapper ( $method_name )>

  *foo_cached = _make_cache_wrapper("foo");

  $obj->foo_cached($cache_info, @original_args_to_foo);

Returns a code reference that adds caching around a call to the named method.

The call takes an additional first $cache_info parameter which is removed
before calling the wrapped mathod. $cache_info is a hash reference which
defines the caching behaviour.  The elements of $cache_info are:

    cache => hash reference
    clone => boolean

If $cache_info is false then the wrapped method is transparent (it just calls $method_name).

If $cache_info->{cache} is true then it must be a reference to a hash that will
be used to cache the results of calling $method_name.

If $cache_info->{cache} is false and the package variable $get_default_cache is
true, then $get_default_cache->($proto,$cache_info) is called. If the return
value is true then it is used at the cache for this call. This allows a default
cache to be setup easily. For example:

  $Gandolfini::Data::get_default_cache = sub {
    return Hackman::RequestStash->get_namespace_dataref("gandolfini_data_cache");
  }

The cache key includes the class name, method_name, and wantarray, as well as
the arguments, so the same cache can be used and shared by different callers.

If $cache_info->{clone} is true then Storable::dclone() is used when storing or
retrieving the data to/from the cache. This must be true whenever there is a
risk that the contents of the returned data will be modified.

=cut

sub _make_cache_wrapper {
    my ($method_name) = @_;

    my $sub = sub {
        my $proto = shift;
        my $cache_info = shift;
        # @_ contains args for method

        my ($ret, $cache, $cache_key);
        if ($cache_info and
            $cache = $cache_info->{cache} || ($get_default_cache && $get_default_cache->($proto,$cache_info))
        ) {
            $cache_key = join "\001",
                "cache_for_$method_name", wantarray, $proto,
                map { (defined $_) ? "($_)" : "undef" } @_;

            if (exists $cache->{$cache_key}) {
                warn "$proto->$method_name returned result from cache\n" if DEBUG & DEBUG_CACHE;
                $ret = ($cache_info->{clone})
                    ? dclone($cache->{$cache_key})
                    :        $cache->{$cache_key};
            }
        }

        if (!$ret) {
            $ret = (wantarray) ? [        $proto->$method_name(@_) ]
                               : [ scalar $proto->$method_name(@_) ];

            $cache->{$cache_key} = ($cache_info->{clone}) ? dclone($ret) : $ret
                if $cache;
        }

        return @$ret if wantarray;
        return $ret->[0];
    };
    return $sub;
}

=item C<verbose ( mode )>

Sets the verbose output mode.

=cut

sub verbose {
	my $proto = shift;
	my $mode = shift;
	$verbose = $mode;
}

=back

=head2 SCALAR PROC METHODS

=over 4

=item C<run ( @args )>

=cut

sub run {
	my $proto	= shift;
	
	my ($rv, $sth, $dbh)	= $proto->_execute( @_ );
	
    # if non_persistent, then need to finish and disconnect	
    if($proto->_non_persistent()) {
	   _finish($dbh, $sth);
    }
	
	return $rv;
}

=item C<row (  )>

=cut

sub row {
	my $self	= shift;
	return undef unless (ref($self));
	return $self->{'_row'};
} # END of row


=item C<error_msg (  )>

Returns the error message from the stored procedure.

=cut

sub error_msg {
	my $self	= shift;
	return undef unless (ref $self);
	return $self->{'error_msg'};
} # END of error_msg


=item C<error_msg (  )>

Returns the error type from the stored procedure.

=cut

sub error_type {
	my $self	= shift;
	return undef unless (ref $self);
	return $self->{'error_type'};
} # END of error_type


=item C<error_msg (  )>

Returns the error code from the stored procedure.

=cut

sub error_code {
	my $self	= shift;
	return undef unless (ref $self);
	return $self->{'error_code'};
} # END of error_code


######################################################################
## PROTECTED ACCESSORS

=head2 PROTECTED METHODS

These methods should only be used by Gandolfini::Data subclasses.

=over 4

=item C<_args ( [ $arg ] )>

If $arg is present, returns the argument's type.
Otherwise, returns a LIST of argument names.

=cut
sub _args {
	my $proto	= shift;
	return $proto->__args( @_ );
}

=item C<_cols ( [ $col ] )>

If $col is present, returns TRUE if $col is a returnable column, FALSE otherwise.
If $col is not present, returns a LIST of column names.

=cut
sub _cols {
	my $proto	= shift;
	return $proto->__cols( @_ );
}

=item C<_prepare_attr ( $dbh )>

Returns undef or a hash ref of attribute values to be passed to the DBI prepare() method.

=cut
sub _prepare_attr {
    return undef;
}


######################################################################
## PRIVATE ACCESSORS

sub _proc {
	my $proto	= shift;
	return $proto->__proc( @_ );
}

sub _procs {
	my $proto	= shift;
	my $proc	= shift || return undef;
	our %procs;
	return $procs{$proc};
}

sub _connect {
	my $handle	= shift;
    my $set = shift;
    my $non_persistent_ok = shift;
    
    if(!$set) {
        $set = our $default_dbh_set;
    }

	our %dbh;
	our %database_set;
	
    # use $dbh->{Name} as context2 to match _execute
    my $ps = extsys_profiler( sub {
        my $dbh = $dbh{$set}{$handle};
        return $dbh->{Name} if $dbh; # Name, if connected, else:
        my $dsn = $database_set{$handle}->{db_stack}->[0][0] || "";
        #warn "extsys_profiler $handle: $dsn";
        return (DBI->parse_dsn($dsn))[4] || $dsn || "(db handle $handle not connected)";
    }) if extsys_profiler_enabled();

    if(defined $database_set{$handle}->{non_persistent}) {
        if(!$non_persistent_ok) {
            return 0;
        }
		elsif($dbh{$set}->{$handle} = DBI->connect( @{ $database_set{$handle}->{db_stack}->[0] } )) {
		    return 1;
		}
		else {
			# log the error condition
			# (need to handle higher level application handling of failed connection!)
			if(defined $DBI::errstr) {
			    warn __PACKAGE__ . " [$$] : non-persistent connection failed to '" . 
			    	$database_set{$handle}->{db_stack}->[0][0] .  "\n: " . $DBI::errstr;
			}
			
		    return 0;
		}
	}
	else {
        my ($dsn, $username, $password, $attr) = @{ $database_set{$handle}->{db_stack}->[0] };
        my $via = $attr->{RootClass} || 'DBI';
        warn __PACKAGE__ . " [$$] : Making persistent connection via $via to '$dsn'\n"
            if (DEBUG & DEBUG_DBI);
            
        $dbh{$set}->{$handle} = ($via eq 'DBIx::HA')
            ? DBIx::HA->connect($handle)
            : DBI->connect( $dsn, $username, $password, $attr );

        return 1 if $dbh{$set}->{$handle};

        # log the error condition
        # (need to handle higher level application handling of failed connection!)
        warn __PACKAGE__ . " [$$] : persistent connection via $via failed to '$dsn'\n";
        return 0;
	}
}

sub _disconnect {
    my $handle = shift;
    my $set = shift;
    
    if(!$set) {
        $set = our $default_dbh_set;
    }
    
	our %dbh;
	my $dbh = $dbh{$set}->{$handle};
	$dbh{$set}->{$handle} = undef;
    if (ref($dbh) && $dbh->can('disconnect')) {
        if($dbh->disconnect()) {
            return 1;
        }
	}
	
    return 0;
}

sub _finish {
	my $proto	= shift;
	my $dbh		= shift || return undef;
	my $sth		= shift || return undef;
	
        my $ps = extsys_profiler($dbh->{Name}) if extsys_profiler_enabled();
	my $finish_status = (ref($sth) && $sth->finish);
	
    # if non_persistent, then need to disconnect after finish	
    if( $finish_status && ref($dbh) && $proto->_non_persistent()) {
		my $status = _disconnect($proto->_name,$proto->_dbh_set);
	}
	
	return $finish_status;
}

# this is overridden for sub-classes that require non-persistent connections
sub _non_persistent() {
    return 0;
}

sub _dbh {
	my $proto	= shift;
	my $name	= shift || $proto->_name;
	my $set		= $proto->_dbh_set;
	our %dbh;
	
	# if it's a non-persistent dbh, need to connect here.
	#  check that it isn't already created, to prevent 
	#  duplicate connections for nested calls.
	if( $proto->_non_persistent() ) {
	    if(!$dbh{ $set}{$name}) {
	       _connect($name, $set, 1);
	    }
	}
	
	return $dbh{ $set }{ $name };
}

sub _dbh_set {
	my $proto	= shift;
	our $default_dbh_set;
	if (scalar(@_)) {
		$default_dbh_set = shift;
	}
	return $default_dbh_set;
}


sub _check_data_type {
	my $proto	= shift;
	my $class	= ref($proto) || $proto;
	my $data	= shift;
	my $type	= shift || '';
	my $dbh		= shift || $proto->_dbh();
	my $name    = shift;
	
	## Not sure if this would ever happen ##
	## = it shouldn't happen ##
	$data		= $data->[0] if (ref $data and reftype($data) eq 'ARRAY');
	
	if (defined $data) {
		if ($type eq 'string') {
			## quote the string ##
                        # arguably this should have a call to extsys_profiler() but we know
                        # that Sybase uses the cheap default quote() method and that Gofer
                        # detects and optimizes for that, so it's not worth calling extsys_profiler.
			$data = $dbh->quote( $data );
		} elsif ($type =~ /^(?:int|money|numeric|decimal|float)\b/o) {
			## remove all non-digit characters except '.' or '-' ##
			if ($data =~ /[^-.0123456789]/) {
				warn "Removing non-numeric characters from $name = '$data'\n";
				$data =~ tr/-.0123456789//cd; # transliterate the complement and delete
			}
			if ($type eq 'int') {
				## for int remove decimal point and anything after it ##
				$data =~ s/\..*//;
			}
			## set to zero unless there's an int ##
			$data = 0 unless (looks_like_number( $data ));
			## Throw exception instead?  Set to null? ##
		}
	} else {
		$data	= 'null';
	}
	return $data;
}

######################################################################
## PRIVATE DBIx::HA callback function

=begin private

=item C<_callback_HA> ( $dbh , $dbname )

Callback function for the High Availability module (DBIx::HA).
It simply resets the $dbh pointer in the local cache.

=end private

=cut

sub _callback_HA {
	my $dbh = shift;
	my $dbname = shift;
	our %dbh;
	our $default_dbh_set;
	
    my $prefix = "[$$] Got DBIx::HA callback";
	my $new_dbh_dsn = $dbh->{Name};
	my $curr_dbh = $dbh{$default_dbh_set}->{$dbname};
	if(!$curr_dbh) {
	    warn __PACKAGE__ . "$prefix: Initial connection to " . $dbname . " as " . $new_dbh_dsn . "\n";
	}
	else {
	    my $curr_dbh_dsn = $curr_dbh->{Name};
	    if($curr_dbh_dsn eq $new_dbh_dsn) {
	        warn __PACKAGE__ . "$prefix: Connecting to " . $dbname . " as " . $new_dbh_dsn . "\n";   
	    }
	    else {
	        # note, I don't expect this to occur for DBIx::HA >= 0.9x
	        warn __PACKAGE__ . "$prefix: Changing connection for " . $dbname . " to " . $new_dbh_dsn . "\n";
	    }
	}			
	
	# this should be a no-op for DBIx::HA > 0.9x (e.g. $dbh is same as curr_dbh)
	if($DBIx::HA::VERSION < 0.9) {
	   $dbh{$default_dbh_set}->{$dbname} = $dbh;
	}
} 

######################################################################
## PRIVATE INITIALIZATION METHODS

sub _subclass_init {
	my $proto	= shift;
	my $class	= ref($proto) || $proto;
	my $proc		= shift;
	my $procdata	= shift;
	
	our %dbh;
	our (%_handles);
	
	my $classname	= $procdata->{ 'class' };
	my $args		= $procdata->{ 'args' } || [];
	my $colsref		= $procdata->{ 'cols' } || [];
	my $dbh_name    = $procdata->{ 'dbh' };
	
	my $subclass	= join('::', $class, $classname);
	my @args		= map { (%$_)[0] } @$args; # an array of hashes with only one key-value pair.
	my %args		= (ref($args) eq 'HASH') ? %{ $args } : map { %$_ } @$args;
	my $cols		= {};
	
	no strict 'refs';
	foreach (@$colsref, @{ $subclass . '::__cols' }) {
		$cols->{ $_ }++;
	}
	
    # I can't see any value in the use of _foo and __foo (e.g., _proc and __proc)
    # I think it would be better to setup an extra level of class hirearchy instead.
    # i.e., "${subclass}" ISA "${subclass}_base" ISA Hackman::Data ISA Gandolfini::Data
    # Then remove the _proc defined above and change this code to define
    # a _proc method in "${subclass}_base" instead of __proc. Same for __args etc.
    # That would be simpler, more efficient, and easier to work with if a $subclass.pm
    # file is needed for any reason.
	warn "subclass: $subclass for proc $proc\n" if (DEBUG & DEBUG_INIT);
	@{ "${subclass}::ISA" }		= ($class)	unless (@{ "${subclass}::ISA" });
	${ "${subclass}::VERSION" }	||= 1.00	unless (${ "${subclass}::VERSION" });
	*{ "${subclass}::__proc" }	= sub { return $proc };
	*{ "${subclass}::__args" }	= sub {
		my $key = $_[1] || '';
		return (scalar(@_) > 1) ? (exists($args{ $key }) ? $args{ $key } : ()) : @args;
	};
	*{ "${subclass}::__cols" }	= sub {
		return (scalar(@_) > 1) ? exists($cols->{ $_[1] }) : keys( %{ $cols } );
	};
	*{ "${subclass}::_name" }	= sub { return $dbh_name };
	*{ "${subclass}::_proc" }	= sub { return $proc };
	*{ "${subclass}::_procdata" } = sub { return $procdata };
    
	our %database_set;
	if ( exists $database_set{$procdata->{'dbh'}}->{non_persistent} ) {
		*{ "${subclass}::_non_persistent" } = sub {
			return 1;
		};    		
	}

    *{ "${subclass}::_execute" } = sub {
        my $proto   = shift;
        my $class   = ref($proto) || $proto;

        my $dbh = $proto->_dbh($dbh_name)
            or die "Not connected to a $dbh_name database so can't call $proc\n";
        my @params;
        for (0 .. $#_) {
            my $data     = shift;
            my $arg_name = $args[$_] || '';
            my $type     = $args{ $arg_name };
            $data        = $proto->_check_data_type( $data, $type, $dbh, $arg_name );
            warn __PACKAGE__ . "->_execute arg $_: $arg_name = $data (type $type)\n" if (DEBUG & DEBUG_DBI);
            push( @params, $data );
        }

        my $sql = join(' ', 'exec', $proc, join(',', @params));
        warn "$class->_execute: $sql\n" if DEBUG & (DEBUG_DBI|DEBUG_SQL);
        sql_execute_count_use($sql);

        my $ps = extsys_profiler($dbh->{Name}) if extsys_profiler_enabled();

        my $sth = $dbh->prepare($sql, $proto->_prepare_attr($dbh))
            || die( 'Unable to prepare statement handle: ' . $dbh->errstr );
        my $rv = $sth->execute()
            || $proto->_die_override($sql, $sth);

        return ($rv, $sth, $dbh);
    };

	eval "require ${subclass}";
	warn "require ${subclass}... " . (($@) ? "failed.\n" : "ok.\n") if (DEBUG & DEBUG_SUBCLASS);
	warn $@ if $@ && $@ !~ /Can't locate/;
	$@	= '';	# We don't care about a failed require

	warn "Creating accessors for $subclass\n" if (DEBUG & DEBUG_SUBCLASS);
	foreach my $col (keys %$cols) {
		$subclass->_accessor_method_init($col);
	}

	return 1;
}

sub _accessor_method_init {
	my $proto	= shift;
	my $class	= ref($proto) || $proto;
	my $method	= shift;
	if ($class->can($method)) {
		warn 'Not creating ' . $class . '::' . $method . ", as it already exists.\n" if (DEBUG & DEBUG_SUBCLASS);
		return undef;
	}
	no strict 'refs';
	*{ "${class}::${method}" } = sub {
		use strict;
		return shift->{ $method };
	};
	1;
}

sub _die_override {
	my $proto = shift;
	my $sql = shift;
	my $sth = shift;
	my $errstr = $sth->errstr || '(no error message given)';
	
	die "Unable to execute statement: [$sql] $errstr\n";
}


=back

=cut

######################################################################

=head1 ATTRIBUTES

=over 4

=item DataField

DataField defines a CODE attribute that will define a new data field (column) for
Gandolfini::Data subclasses. Accessor methods in the subclass should be defined
with the DataField attribute in order to maintain class metadata; After an
accessor is defined as a DataField, it's return value will be available in the
objects returned by the C<*_hash> constructors, and as an object method on objects
returned by the C<*_obj> constructors.

For example, defining this accessor:

 package Data::Gandolfini::MyClass;
 sub bizrate_url : DataField { return 'http://www.bizrate.com'; }

will allow access to this data as:

 $stream = Data::Gandolfini::MyClass->stream_hash( @args );
 $hash = $stream->next();
 print $hash->{ 'bizrate_url' };

=back

=cut
sub DataField : ATTR(CODE) {
	my ($package, $symbol, $referent, $attr, $data, $phase)	= @_;
	our (%_handles);
	no strict 'refs';
	push( @{ $package . '::__cols' }, *{ $symbol }{'NAME'} );
	warn "New column defined: " . *{ $symbol }{'NAME'} if (DEBUG & DEBUG_SUBCLASS);
	return 1;
}


######################################################################

1;

__END__

=head1 PROCS FILE

The conf/procs.yaml file is a L<YAML|YAML> data file containing the database
account information (dsn, username, password) and proc descriptions.

=head2 SYNTAX

As a L<YAML|YAML> file, the procs file depends on whitespace indentation to
determine the proper structure of the data. It is important to remember that
tabs are not a good way to maintain cross-platform indentation; Use spaces
instead. If a stray tab is used in the procs file where there should be spaces,
you're likely to get the following YAML error:

 code: YAML_LOAD_ERR_BAD_MAP_ELEMENT
 msg: Invalid element in map
 line: 14

To fix this, go to line 14 of the procs file and replace the tab with spaces.

=head2 STRUCTURE

The procs file has five main sections:

	db_aliases - database aliases
	dbh - database handle lists
	dsn_rewrite - optional dsn rewriting expressions
	dbi_defaults - database default settings
	procs - proc definitions

All except the last are typically loaded from conf/colo/*/dbh*.yaml files.
The last is loaded from conf/procs*.yaml files.

=head3 db_aliases

	db_aliases:
	  pr_bizrate:
		- &PRLOG01
		dsn: dbi:Sybase:server=pr_log01;database=logging;hostname=$hostname
		username:
		password:
		- &PRLOG02
		dsn: dbi:Sybase:server=pr_log02;database=logging;hostname=$hostname
		...etc...

	  pr_barbie:
		- &PRBARBIE01
		dsn: dbi:Sybase:server=pr_barbie01;database=prodep;hostname=$hostname
		...etc...

The database aliases section assigns names (aliases), like PRLOG01 above, to
a particular dsn + username + password combination.

=head3 dbh

  dbh:
	prod_odd_001-009:
	  logging:
		- *PRLOG01
		- *PRLOG03
	  barbie:
		- *PRBARBIE01
		- *PRBARBIE03
	  dss:
		- *PRRW01SILO1
	prod_odd_011-019:
	  logging:
		...etc...

Database handles are defined in sets ('prod_odd_001-009' and 'prod_odd_011-019'
in the example above).  In each set, a 'stack' of one or more database handles
are associated with each type of database (logging, barbie, etc.) by specifying
the alias name defined by the db_aliases section.

When DBIx::HA is being used it will connect to the first in the stack and
fail-over to the following ones if there's an error. When DBIx::HA is being used
there's no value in having more than one in each stack, but it's harmless.

The name of the set to use is controlled by conf/colo/*/hackman_rdbms.conf.
If the selected name is not defined in the dbh section then it'll try using
"DEFAULT" as a fallback. If there's no set called DEFAULT then startup will
fail with an error.

=head3 dsn_rewrite

  dsn_rewrite:
	DEFAULT:
	  logging: s{^(.*?);hostname=.*}{dbi:Gofer:transport=http;url=http://gofer001.$domain:19101/pr_logdb;dsn=$1}
	  barbie:  s{^(.*?);hostname=.*}{dbi:Gofer:transport=http;url=http://gofer001.$domain:19001/pr_barbiedb;dsn=$1}
	  dss:

The optional dsn_rewrite section provides a mechanism to edit the 'dsn' values
in the stacks of databases defined by the L</dbh> section (above).
A different rewrite expression can be specified for each type of database.

A different set of rewrite expressions can be specified for each set
('prod_odd_001-009' and 'prod_odd_011-019' in the dbh section example above)
but that's rarely useful. If there's no dsn_rewrite for a particular set then
the DEFAULT dsn_rewrite will be used, if defined.

The dsn_rewrite expressions are perl statements that alter the value of $_, which holds the dsn.
As a convienience the $domain variable holds the current domain.
Syntax errors are caught at startup.

=head3 dbi_defaults

  dbi_defaults:
	DBIxHA:
	  max_retries: 2
	  connectoninit: 1
	  pingtimeout: -1
	  connecttimeout: 1
	  executetimeout: 8
	  failoverlevel: application
	DBI:
	  AutoCommit: 1
	  ChopBlanks: 1
	  PrintError: 0
	  RaiseError: 0
	  RootClass: 'DBIx::HA'
	DBI_non_persistent: 
	  AutoCommit: 1
	  ChopBlanks: 1
	  PrintError: 0
	  RaiseError: 0
	  RootClass: 'DBI'

The dbi_defaults section defines defaults for various kinds of connections.

=head3 procs

The proc definitions are given by proc name, and contain a perl class name,
a description, a named database handle, arguments and columns:

 procs:
   bizrate..P_S_OLD_CID:
     class: OldCategory
     description: Mapping table from old CIDs to new CIDs
     dbh: qa_barbie
     args:
       - cid: int
     cols:
       - new_cid

This defines a proc 'bizrate..P_S_OLD_CID' that will be represented by the
class Gandolfini::Data::OldCategory (If Gandolfini::Data was subclassed, by
Hackman::Data, for instance, this would instead be Hackman::Data::OldCategory).
The proc takes one integer argument, and returns one column 'new_cid'.

For proper quoting, the type of each argument is specified after the argument
name. The type may be one of the following:

=over 4

=item string - A string

=item number - A number (int or float)

=item int - An integer

=item float - A floating point number

=back

=head1 KNOWN BUGS

None

=head1 TO DO

=over 4

=item * Write tests for run()

=item * Write tests for multiple database handle sets

=back

=head1 AUTHOR

 Gregory Williams <gwilliams@cpan.org>

=cut

vim: ts=4:sw=4
