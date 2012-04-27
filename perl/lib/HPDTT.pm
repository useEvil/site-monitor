=head1 NAME

HPDTT: Henri's Perl Debugging and Tracing Tools

=cut

package HPDTT;

=head1 SYNOPSIS

 use HPDTT;
 use HPDTT::Simple;

 HPDTT::config_method_overload ('execute', 'HPDTT::Basic::profile_dbexecute_inline');
 HPDTT::recurse_overload('DBD::');

=head1 REQUIRES

use Time::HiRes		# Optional, for timing and profiling

=cut

=head1 EXPORTS

Nothing

=head1 DESCRIPTION

HPDTT is a self-contained profiling module that will automatically overload any method
based on its name from the currently loaded packages.

The overloading only hooks in some trace calls (and later on some timing calls)
and still runs the original method that was overloaded as if nothing happens.

=cut

use strict;
use Time::HiRes qw(time gettimeofday tv_interval);
use vars qw(@ISA $DEBUG %methods_to_overload %packages_already_scanned);

BEGIN {
	$DEBUG = 0;
	%methods_to_overload = ();
	%packages_already_scanned = ();
}

my $profiling_log = "/tmp/HPDTT_profiling.log";
my %overloaded_methods = ();

%methods_to_overload = (
	# these are the methods to overload.
	# the key is the name of the method.
	# the value is the name of the private method in this module to use to overload
	# you can overload any method of a certain name (example: "new")
	# or you can overload a specific method (example: "main::Travolta::Category::new")
	# if you're overloading a specific method, make sure the name of it goes up to the root
	# that you're overloading from. (example: if you start at "Travolta::", then use "Travolta::Category::new")

#			'new'	 	=> '_profile_standard',
#			'main::Travolta::Session::xinclude' 	=> '_profile_standard',
#			'main::Travolta::UCSE::xinclude' 	=> '_profile_standard',
#			'xinclude' 	=> '_profile_inline',
#			'execute' 	=> '_profile_dbexecute_inline',
#			'do' 		=> '_profile_dbexecute_inline',
#			'execute' 	=> '_warn_dbexecute',
#			'prepare' 	=> '_profile_dbexecute',
#			'fetch' 	=> '_profile_dbexecute',
#			'Travolta::Category::new'	=> '_warn_standard',
			  );

%packages_already_scanned = (
			# hash that holds the list of packages already scanned (more efficiency).
			# you can predefine the list to automatically bypass certain packages.
			'main::MD5::'			=> 1,
			'main::FileHandle::'		=> 1,
			'main::Bingo::XPP::Page::'	=> 1,
			'Bingo::XPP::Page::'		=> 1,
			);
my $codesrc;			# source of the overloading code to eval that will create the sub
my $is_warning = $^W;		# are warnings on?  (-w switch)


#############################################################################
#
#               START PUBLIC METHODS TO VIEW AND SET UP THE OVERLOADING
#
#############################################################################

sub config_log {
	# Method to configure the profiling log
	# INPUT: (logfile_path)
	# OUTPUT: undef/1  (undef if no logfile passed in, otherwise 1)

	my $lfile = shift || return undef;
	$profiling_log = $lfile;
	return 1;
}

sub config_package_bypass {
	# Method to disable or reenable overloading of a package
	# i.e. bypassing a package when parsing the package tree for overloading
	# If no toggle is passed in, then the method returns the state of a package's bypass
	#
	# INPUTS: (package [, 0/1 ])
	#	(package) : get state of bypass of package
	#	(package, 1) : enable bypass of package
	#	(package, 0) : disable bypass of package
	#
	# OUTPUT IN 1-INPUT CONFIG: undef/1 showing the state of package's bypass
	# OUTPUT IN 2-INPUT CONFIG: undef/1 (1: ok, undef: package doesn't exist, if bypass removal requested

	my $package = shift or return undef;
	my $toggle = shift;
	my $res;

	if ($toggle eq undef) {		# "get" version
		$res = 1 if ($packages_already_scanned{$package});
	} elsif ($toggle == 1) {	# "set" version, enable
		$packages_already_scanned{$package} = 1;
		$res = 1;
	} elsif ($toggle == 0) {	# "set" version, disable
		$res = 1 if (defined $packages_already_scanned{$package});
		undef $packages_already_scanned{$package};
	}

	return $res;
}

sub check_method_exists {
	# Method that checks for the existence of a method
	#
	# INPUTS: (fully_qualified_method)
	# OUTPUT: undef/1 (1 if method exists, otherwise undef)

	my $method = shift or return undef;

	if (defined &{$method}) {	# method to overload exists
		return 1;
	} else {				# ouch, method to overload doesn't exist!
		warn "$method doesn't exist!\n" if ($DEBUG);
		return undef;
	}

	return undef;
		
}

sub list_overloaded_methods {
	# Method that returns all overloaded methods
	#
	# INPUTS: None
	#
	# OUTPUT: Hash of (method, overloading_method)

	return %overloaded_methods;

}

no strict "refs";

sub overload_method {
	# method that will overload a method with another
	#
	# INPUTS: (fully_qualified_method_to_overload, fully_qualified_overloading_method)
	#	Both methods should be fully qualified with package name.
	#	For example: ('DBD::Sybase::st::execute', 'MyPackage::profile_exec')
	#
	# OUTPUT: undef/1  (undef if a method doesn't exist in the package tree or isn't fully qualified, otherwise 1)

	my $in_method = shift || return undef;
	my $out_method = shift || return undef;

	return undef unless (&check_method_exists($in_method));
	return undef unless (&check_method_exists($out_method));

	return undef unless ($in_method =~ /^(.+::)(.+?)$/o);
	my $method = $2;
	my $package = $1;
	return undef if (defined &{$package."_HPDTToverload_".$method});

	# Make a new alias of it with the prefix "_HPDTToverload_"
	# and then replace it with a new sub that ultimately calls that original method.
	# The trick here is that the alias still points to the original code because it was assigned
	# as a reference (not a real alias where *xxx = *yyy) and thus its value in the symbol table
	# is a pointer to the original code itself.
	# As the subroutine was changed, its glob was assigned a pointer to new code, but the original 
	# code stayed unchanged, as did the pointers to that original code.
	
	*{$package."_HPDTToverload_".$method} = \&{$in_method};
	$codesrc = 'sub '.$in_method.' { '.&{$out_method}($package,$method).' }';
	warn "Overload code for ".$in_method." ==>\n$codesrc\n---\n" if $DEBUG;
	$^W = 0 if $is_warning;	# turn off warnings otherwise it says "subroutine redefined..."
	eval $codesrc;
	$^W = 1 if $is_warning;	# turn warnings back on
	if ($@) {
		warn "OVERLOAD FAILED: $@\n";
		*{$package.$method} = \&{$package."_HPDTToverload_".$method};
		return undef;
	}

	$overloaded_methods{$in_method} = $out_method;
	return 1;
}

sub restore_method {
	# Method that restores a method to its original un-overloaded self
	#
	# INPUTS:
	#	FORM 1: (package, method)
	#	The package should be in the form "XXXX::YYYY::". If "::" is not present at the end, it will be appended.
	#	The method should not have any package information, just its name as if it was called from within the package itself
	#
	#	FORM 2: (fully_qualified_method)
	#	In this form, the method passed is should be fully qualified with its package name. For example: DBD::Sybase::st::execute

	my $package = shift || return undef;
	my $method = shift || undef;

	# Determine which input style was used and get package and method
	if ($method) { 	# form 1, using (package, method)
		$package .= '::' unless ($package =~ /::$/o);
	} else {	# form 2, using fully qualified method name only
		$package =~ /^(.+::)(.+?)$/o;
		$method = $2;
		$package = $1;
	}

	return 0 unless (defined &{$package."_HPDTToverload_".$method});
	*{$package.$method} = \&{$package."_HPDTToverload_".$method};
	undef *{$package."_HPDTToverload_".$method};
	undef $overloaded_methods{$package.$method};
	return 1;
}


sub recurse_overload {
	# Method that will scan through a package recursively, looking for method names to overload
	# Configuration of package bypassing and methods to overload MUST be done prior to calling this method
	# If you are looking to scan through the complete Perl package tree, use 'main::' as the package parameter

	#INPUTS: (package [, flat/recursive ])
	#	The package name MUST end in '::', otherwise we will consider it a method to try to overload
	#	if it exists in the %methods_to_overload hash
	#	The second parameter should be either "flat" or "recursive". Defaults to "recursive".
	#	If "flat", it scans through its package only and doesn't recurse

	# OUTPUT: integer
	#	Number of packages overloaded in total

	my $currpackage = shift;
	my $out_method = shift;
	my $recurse = shift || 1;	# should be 'flat' or 'recursive'. Defaults to 'recursive'
	my $res = 0;

	if ($recurse eq 'flat') {
		$recurse = 0;
	} else {
		$recurse = 1;
	}
	
	foreach (keys %{"$currpackage"}) {
		next if /main::/o;	# 'main::' is everywhere, creating infinite loop if not bypassed.
		next if $packages_already_scanned{$currpackage.$_};	# has package already been scanned?
		next if defined &{$currpackage."_HPDTToverload_".$_}; 	# has method already been overloaded?

		if (/::$/o) {
			# it's a package, not a method (name ends in "::")
			# recurse over it and put it in the list of packages already scanned
			
			warn ($currpackage.$_."\n") if ($DEBUG > 1);
			$packages_already_scanned{$currpackage.$_} = 1;
			if ($recurse) {
				$res += &recurse_overload($currpackage.$_);
			}
			next;
		}

		if (!($methods_to_overload{$_}) && !($methods_to_overload{$currpackage.$_})) {
			# We've got a method that is a candidate for overloading.
			&overload_method($currpackage.$_, $out_method);
		}
	}
	return $res;
}

#SAMPLES:
#&recurse_overload('main::');	# start the overloading on this part of the package tree
#&recurse_overload('Travolta::');	# start the overloading on this part of the package tree
#&recurse_overload('Apache::');	# start the overloading on this part of the package tree
#&recurse_overload('DBD::');	# start the overloading on this part of the package tree
#&recurse_overload('Bingo::');	# start the overloading on this part of the package tree
#&overload_method('Bingo::XPP::xinclude');	# overload a specific method
#&overload_method('Bingo::XPP::', 'xinclude');	# same as above
#&overload_method('Bingo::XPP', 'xinclude');	# same as above


1;
