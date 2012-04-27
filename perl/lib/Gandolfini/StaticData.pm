# Gandolfini::StaticData
# -------------
# $Revision: 1850 $
# $Date: 2007-11-13 14:34:07 -0800 (Tue, 13 Nov 2007) $
# -----------------------------------------------------------------------------

=head1 NAME

Gandolfini::StaticData - Thin Database Abstraction Class for Static Data

=cut

package Gandolfini::StaticData;

=head1 SYNOPSIS

 use Gandolfini::StaticData;
 Gandolfini::StaticData->init( '/path/to/static/data/info.yaml' );
 my $value	= Gandolfini::StaticData::Category->get_data( @args );
 my $data	= Gandolfini::StaticData::Category->get_data(  );

=head1 DESCRIPTION

Gandolfini::StaticData is a thin database abstraction class for Static Data. 
Using information about database procs from a YAML metadata file, subclasses of 
Gandolfini::Data are generated for each proc. Objects representing the rows 
returned by these procs may be accessed using the C<get_data> methods.

=head1 REQUIRES

L<Gandolfini::Data|Gandolfini::Data>

L<YAML|YAML>

=cut

use strict;
use warnings;
use Carp qw(croak);
use Scalar::Util qw/reftype/;
use YAML qw(LoadFile);
use Storable qw(lock_nstore lock_retrieve freeze);

=head1 EXPORTS

Nothing

=cut

######################################################################

our (@ISA, $debug, $verbose, %static);
use constant DEBUG_NONE		=> 0b00000000;
use constant DEBUG_INIT		=> 0b00000001;
use constant DEBUG_WARN		=> 0b00000010;
use constant DEBUG_DUMPER	=> 0b00000100;
use constant DEBUG_SUBCLASS	=> 0b00001000;

BEGIN {
	@ISA		= qw();
	$debug		= DEBUG_NONE;# | DEBUG_WARN;# | DEBUG_DUMPER;# | DEBUG_INIT;# | DEBUG_SUBCLASS;
	$verbose	= 0;
}

# Default path to store StaticData cache file.
# Overridden by $cache argument to init().
# If false then caching is disabled.
# Could be set by httpd conf file to be relative to server root.
our $STATICDATA_CACHE_FILE = undef; # "/tmp/staticdata_cache.storable";

# Time-to-live in seconds for cache file validity.
# Keep it short (say <= ~120) to reduce risk of consistency problems
# (such as code changes during a restart). If you want a longer ttl then add
# more info into the cache digest sanity check.
our $STATICDATA_CACHE_TTL ||= 90;


=head1 METHODS

=cut

######################################################################

=head2 INITIALIZATION METHODS

=over 4

=item C<init ( $filename )>

Takes a list of Classes to initialize the Static Data in a global.

=cut

sub init {
	my $proto	= shift;
	my $class	= ref($proto) || $proto;
	my $file	= shift || 'static_data.yaml';
	our $staticdesc	= shift || LoadFile( $file ) or do { warn "$file: $!" if $debug & DEBUG_INIT; return undef };
	my $cache	= shift;

	my $start_time = time();
	warn sprintf "%s: loading %d classes...\n", $proto, scalar keys %{ $staticdesc->{static_data} };

	local $STATICDATA_CACHE_FILE = $cache if $cache;
	my $loaded_cache = $class->load_static_data_cache_file($STATICDATA_CACHE_FILE, $STATICDATA_CACHE_TTL, $staticdesc)
	    if $STATICDATA_CACHE_FILE && -f $STATICDATA_CACHE_FILE;
	
	while (my($sname, $sdata) = each(%{ $staticdesc->{'static_data'} })) {
		warn __PACKAGE__ . "->init: [${sname}]\n" if ($debug & DEBUG_INIT);
		$class->_subclass_init( $sname, $sdata );
	}

	$class->save_static_data_cache_file($STATICDATA_CACHE_FILE, $staticdesc)
	    if $STATICDATA_CACHE_FILE && !$loaded_cache;

	warn sprintf "%s: loaded %d classes in %d seconds\n",
	    $proto, scalar keys %{ $staticdesc->{'static_data'} }, time()-$start_time;
	if ( $debug & DEBUG_INIT and Hackman::Apache::CleanupAndTerminateChild->can( 'get_memory_size' ) ) {
	    warn "Memory in use: ".join(", ", Hackman::Apache::CleanupAndTerminateChild::get_memory_size());
	}

	return 1;
} # END sub init

=back

=cut



sub save_static_data_cache_file {
	my ($class, $cache_file, $digest_data) = @_;

	eval {
		if ($debug & DEBUG_INIT and open my $dump_fh, ">$cache_file.dump") {
			print $dump_fh Data::Dumper::Dumper(\%static);
		}
		# add frozen $digest_data so load_static_data_cache_file() can check
		# the cache file being loaded relates to the same data
		local $static{"-digest_data_key"} = freeze($digest_data);

		lock_nstore(\%static, $cache_file) || die "lock_nstore failed: $!\n";
	};
	if ($@) {
		warn "StaticData cache file '$cache_file' not written: $@\n";
		unlink $cache_file; # potentially corrupt, so delete
		return 0;
	}
	warn "$class: written data cache to $cache_file\n" if $debug & DEBUG_INIT;
	return 1;
}


sub load_static_data_cache_file {
	my ($class, $cache_file, $ttl, $digest_data) = @_;

	my $mtime = (stat($cache_file))[9]
		or return 0;    # no file or can't access it

	# if ttl given then check if file is too old to use
	return 0 if $ttl && $mtime < time() - $ttl;

	eval {
		my $cached_data = lock_retrieve($cache_file);
		# sanity check the loaded data relates to what we expect
		my $digest_data_key = delete $cached_data->{"-digest_data_key"}
			or die "No digest_data_key found\n";
		$digest_data_key eq freeze($digest_data)
			or die "cache outdated (digest_data_key mismatch)\n";
		# all seems well so publish the loaded data
		%static = %$cached_data;
	};
	if ($@) {
		warn "Unable to load StaticData cache file '$cache_file': $@\n";
		return 0;
	}
	warn "$class: loaded cached data from $cache_file\n"; # if $debug & DEBUG_INIT;
	return 1;
}


######################################################################

=head2 ITERATOR AND LIST CONSTRUCTORS

=over 4

=item C<get_data ( $class [, @args ] )>

Pass in the class and the data will be retrieved for you.

If called in array context, count of rows will also be returned.

=cut

sub get_data {
	my $proto	= shift;
	my $class	= ref($proto) || $proto;
	my $name	= (split(/::/, $class))[-1];
	my ($data, $count, $coderef, $coderef_set);
	our %static;
	
	if (ref($static{$name}) && ref($static{$name}->[0])) {
		warn __PACKAGE__ . "->get_data: [${name}] We already have the data!\n" if ($debug & DEBUG_WARN);
		($data, $count, $coderef, $coderef_set) = @{ $static{$name} };
	} else {
		warn __PACKAGE__ . "->get_data: [${name}] We don't have the data yet!\n" if ($debug & DEBUG_WARN);
		($data, $count, $coderef, $coderef_set) = $proto->_data();
		if (ref $coderef) {
			#warn "get_data($coderef, $default_meth, $extract_meth)\n";
		    my $has_overridden_extract = (       $proto->can("_extract_from_data_with_args")
						 != __PACKAGE__->can("_extract_from_data_with_args") );
		    if ($coderef == $proto->_coderef || $has_overridden_extract) {
				# convert code refs to be flags so we don't try to serialize the code refs
				$coderef     &&= 1;
				$coderef_set &&= 1;
		    }
		    elsif ($STATICDATA_CACHE_FILE) {
				warn "$class needs to be updated to use _extract_from_data_with_args()\n";
		    }
		}
		$static{$name} = [ $data, $count, $coderef, $coderef_set ];
	}
	
	if ($coderef && @_) {
		warn __PACKAGE__ . "->get_data: [@_] We have params!\n" if ($debug & DEBUG_WARN);
		return $class->_extract_from_data_with_args( $data, @_ )
			if not ref $coderef;
		return $coderef->( $data, @_ );
	} else {
		warn __PACKAGE__ . "->get_data: [${count}] We don't have params!\n" if ($debug & DEBUG_WARN);
		warn __PACKAGE__ . '->get_data: ' . Data::Dumper::Dumper( $data ) if ($debug & DEBUG_DUMPER);
		return wantarray ? ($data, $count) : $data;
	}
} # END sub get_data


=item C<set_data ( $id, $data )>

Pass in the class and the data will be retrieved for you.

If called in array context, count of rows will also be returned.

=cut

sub set_data {
	my $proto	= shift;
	my $class	= ref($proto) || $proto;
	my $name	= (split(/::/, $class))[-1];
	my $id		= shift || return undef;
	my $object	= shift || return undef;
	our %static;
	warn __PACKAGE__ . "->set_data: id[${id}]!\n" if ($debug & DEBUG_WARN);
	my ($data, $count, $coderef, $coderef_set) = @{ $static{$name} };
	return $proto->_store_into_data_with_args( $data, $id, $object )
		if not ref $coderef_set;
	$coderef_set->( $data, $id, $object );
} # END sub set_data



=item C<data_class (  )>

Returns the data class for the associated static class.

=cut

sub data_class {
	my $proto		= shift;
	my $class		= ref($proto) || $proto;
	my $data_class	= $class;
	$data_class		=~ s/StaticData/Data/;
	return $data_class;
} # END sub data_class

=item C<verbose ( mode )>

Sets the verbose output mode.

=cut

sub verbose {
	my $proto = shift;
	my $mode = shift;
	$verbose = $mode;
} # END sub verbose

######################################################################
## PRIVATE INITIALIZATION METHODS

=head2 PROTECTED METHODS

These methods should only be used by Gandolfini::StaticData subclasses.

=over 4

=item C<_subclass_init (  )>

Builds the data structure for the given Static Data Class.  This class 
is generic and builds a standard HASH, key => $data or ARRAY, list of 
$data.

=cut

sub _subclass_init {
	my $proto		= shift;
	my $class		= ref($proto) || $proto;
	my $staticname	= shift;
	my $staticdata	= shift;
	
	my $type		= $staticdata->{ 'type' };
	my $key			= $staticdata->{ 'keys' };
	my $required	= exists($staticdata->{ 'required' }) ? $staticdata->{ 'required' } : 0; 
	my $subclass	= join('::', $class, $staticname);
	
	no strict 'refs';
	
	warn __PACKAGE__ . "->_subclass_init: ${staticname}\n" if ($debug & DEBUG_INIT);
	@{ "${subclass}::ISA" }		= ($class)	unless (@{ "${subclass}::ISA" });
	${ "${subclass}::VERSION" }	||= 1.00	unless (${ "${subclass}::VERSION" });
	warn __PACKAGE__ . "->_subclass_init: type: ${type}\n" if ($debug & DEBUG_INIT);
	warn __PACKAGE__ . "->_subclass_init: key: ${key}\n" if ($debug & DEBUG_INIT);
	
	no warnings 'redefine';
	*{ "${subclass}::_type" }	= sub { return $type };
	*{ "${subclass}::_key" }	= sub { return $key };
	if (exists($staticdata->{'dataclass'})) {
		my $data_class	= join('::', $class, $staticdata->{'dataclass'});
		$data_class		=~ s/StaticData/Data/;
		*{ "${subclass}::data_class" }	= sub { return $data_class; };
	}

	(my $pm = $subclass) =~ s/::/\//g;
	$pm .= ".pm";
	eval { require $pm };
	warn __PACKAGE__ . "->_subclass_init: require ${subclass}... " . (($@) ? "failed.\n" : "ok.\n") if ($debug & DEBUG_SUBCLASS);
	warn $@ if ($@ && $@ !~ /Can't locate \Q$pm/);
	$@	= '';	# We don't care about not finding $subclass.pm
	
	my($data, $count) = $subclass->get_data();
	if ($required && $count == 0) {
		die ' *** ERROR: '.${subclass}." is required but the proc returned ZERO records, possible data migration happening while app server was starting.\n";
	}

	warn "StaticData loaded $subclass ($count)\n" if ($verbose);

	return 1;
} # END sub _subclass_init

=item C<_data (  )>

Builds the data structure for the given Static Data Class.  This class 
is generic and builds a standard HASH, key => $data or ARRAY, list of 
$data.

=cut

sub _data {
	my $proto		= shift;
	my $stream		= $proto->data_class->stream_hash();
	my $count		= 0;
	my $data;
	warn __PACKAGE__ . '->_data:_type: ' . $proto->_type . "\n" if ($debug & DEBUG_WARN);
	warn __PACKAGE__ . '->_data:_key: ' . $proto->_key . "\n" if ($debug & DEBUG_WARN);
	
	while (my $row = $stream->next()) {
		if ($proto->_type eq 'hash') {
			$data = { } unless (keys %$data);
			$data->{ $row->{ $proto->_key } } = $row;
		} elsif ($proto->_type eq 'array') {
			$data = [ ] unless ($data->[0]);
			push @$data, $row;
		}
		$count++;
	}
	$stream->close;
	
	return $data, $count, $proto->_coderef, $proto->_coderef_set;
} # END of _data



=item C<_extract_from_data_with_args ( )>

Extract data from the data structure. Currently uses the deprecated _coderef method.
Once client classes have been changed to define their own _extract_from_data_with_args()
methods then _coderef() can be deleted and the guts of it moved here (without the coderef).

=cut

sub _extract_from_data_with_args {
	my ($class, $data, @args) = @_;
	my $key = shift @args;
	my $coderef = $class->_coderef;
	return $coderef->( $data, $key );
}


=item C<_coderef (  )>

Generic definition of the way data is retrieved from the data structure.
Deprecated. See _extract_from_data_with_args().

=cut

sub _coderef {
	return sub {
				my $data	= shift;
				my $key		= shift;
				if (ref $data and reftype($data) eq 'HASH' ) {
					return $data->{ $key } if ($key && exists($data->{ $key }));
				} elsif (ref $data and reftype($data) eq 'ARRAY') {
					return $data->[ $key ];
				}
			};
} # END sub _coderef


=item C<_store_info_data_with_args ( )>

Store data into the data structure. Currently uses the deprecated _coderef_set method.
Once client classes have been changed to define their own _store_info_data_with_args()
methods, if needed, then _coderef_set() can be deleted and the guts of it moved
here (without the coderef).

=cut

sub _store_info_data_with_args {
	my ($class, $data, $id, $newvalue ) = @_;
	my $coderef_set = $class->_coderef_set;
	return $coderef_set->( $data, $id, $newvalue );
}


=item C<_coderef_set (  )>

Generic definition of the way data is retrieved from the data structure.
Deprecated. See _store_info_data_with_args().

=cut

sub _coderef_set {
	return sub {
				my $data	= shift;
				my $key		= shift;
				my $replace	= shift;
				if (ref $data and reftype($data) eq 'HASH') {
					$data->{ $key } = $replace if ($key && exists($data->{ $key }));
				} elsif (ref $data and reftype($data) eq 'ARRAY') {
					$data->[ $key ] = $replace;
				}
			};
} # END sub _coderef_set

=item C<_has_data (  )>

Generic definition of the way data is retrieved from the data structure.

=cut

sub _has_data {
	my $proto	= shift;
	my $data	= shift;
	if (ref $data and reftype($data) eq 'HASH') {
		return keys(%$data) ? 1 : 0;
	} elsif (ref $data and reftype($data) eq 'ARRAY') {
		return ref($data->[0]) ? 1 : 0;
	}
} # END sub _has_data




######################################################################

1;

__END__

=back

=head1 KNOWN BUGS

None

=head1 AUTHOR

 Thai Nguyen <thai@bizrate.com>

=cut
