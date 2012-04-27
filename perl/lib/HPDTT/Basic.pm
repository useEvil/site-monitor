=head1 NAME

HPDTT::Basic

Basic overloading methods for HPDTT 

=cut

package HPDTT::Basic;

=head1 SYNOPSIS

 use HPDTT;
 use HPDTT::Basic;

 HPDTT::config_method_overload ('execute', 'HPDTT::Basic::profile_dbexecute_inline');

=head1 REQUIRES

use Time::HiRes		# Optional, for timing and profiling

=cut

=head1 EXPORTS

Nothing

=head1 DESCRIPTION

HPDTT is a self-contained profiling module that will automatically overload any method
based on its name from the currently loaded packages.

HPDTT::Basic is a collection of overloading methods that provide basic functionality
such as warns and profiling.

=cut

use strict;
use Time::HiRes qw(time gettimeofday tv_interval);
use vars qw(@ISA $DEBUG);

BEGIN {
	$DEBUG = 1;
}

my $profiling_log = "/tmp/HPDTT_profiling.log";

#############################################################################
#
#               START PRIVATE METHODS TO USE FOR OVERLOADING
#
#############################################################################


sub warn_standard {
	# This is a standard warn sub
	# Warns the overloaded method name and its params to the error log
	my $thepackage	= shift;
	my $themethod	= shift;

	my $codestr 	= <<EOF;

my \$result = \&{'$thepackage'.'_HPDTToverload_'.'$themethod'} (\@_);
warn "$thepackage$themethod params: ".join(",",\@_)."\\n";

return \$result;
EOF

	return $codestr;
} # end warn_standard


sub profile_standard {
	# This is a standard profiling sub
	# Stores inside the $profiling_log the method name, its main param,
	# and the time taken to execute
	my $thepackage	= shift;
	my $themethod	= shift;

	my $codestr 	= <<EOF;

my (\$u1, \$s1, \$cu1, \$cs1) = times;
my \$time = localtime;
my \$ru1 = time;
my(\@result, \$result);
my \$result;
if (wantarray) {
	\$result = [ \&{"$thepackage"."_HPDTToverload_"."$themethod"} (\@_) ];
} else {
	\$result = \&{"$thepackage"."_HPDTToverload_"."$themethod"} (\@_);
}
my \$ru2 = time;
my (\$u2, \$s2, \$cu2, \$cs2) = times;

unless (\$ru2-\$ru1 < .001) {
	open OUTFILE, ">>$profiling_log";
	#print OUTFILE join(",", '$thepackage$themethod', \$_[1],'', \$u2-\$u1, \$s2-\$s1, \$cu2-\$cu1, (\$cs2-\$cs1)."\\n");
	#print OUTFILE join("\\t", \$_[1],sprintf('%.4f',\$ru2-\$ru1),sprintf('%.4f',\$u2-\$u1)."\\n");
	print OUTFILE join("\\t", "[\$time]",\$_[1],sprintf('%.4f',\$ru2-\$ru1),sprintf('%.4f',\$u2-\$u1)."\\n");
	close OUTFILE;
}

return wantarray ? \@\$result : \$result;
EOF

	return $codestr;
} # end profile_standard


sub profile_inline {
	# This is a profiling sub that prints information directly on the screen
	my $thepackage	= shift;
	my $themethod	= shift;

	my $codestr 	= <<EOF;

my (\$u1, \$s1, \$cu1, \$cs1) = times;
my \$ru1 = time;
#my \$result = goto \&{"$thepackage"."_HPDTToverload_"."$themethod"};
my \$result;
if (wantarray) {
	\$result = [ \&{"$thepackage"."_HPDTToverload_"."$themethod"} (\@_) ];
} else {
	\$result = \&{"$thepackage"."_HPDTToverload_"."$themethod"} (\@_);
}
my \$ru2 = time;
my (\$u2, \$s2, \$cu2, \$cs2) = times;

unless (\$ru2-\$ru1 < .001) {
	if ((\$ru2 - \$ru1) >= 0.3) {
		print "<div class=profilingBad>";
	} elsif ((\$ru2 - \$ru1) >= 0.1) {
		print "<div class=profilingAvg>";
	} else {
		print "<div class=profilingGood>";
	}
	print join(" - ", '$thepackage$themethod', \$_[1],sprintf('%.4f',\$ru2-\$ru1),sprintf('%.4f',\$u2-\$u1));
	print "</div>\\n";
}

return wantarray ? \@\$result : \$result;
EOF

	return $codestr;
} # end profile_inline


sub warn_dbexecute {
	# This is a warn sub for database execute call
	# Warns the overloaded execute method name and its custom params to the error log
	my $thepackage	= shift;
	my $themethod	= shift;

	my $codestr 	= <<EOF;

my \$t0 = time;
my \$result;
if (wantarray) {
	\$result = [ \&{"$thepackage"."_HPDTToverload_"."$themethod"} (\@_) ];
} else {
	\$result = \&{"$thepackage"."_HPDTToverload_"."$themethod"} (\@_);
}
#warn "$thepackage$themethod dbname: ".\$DBI::lasth->\{Database}->\{Name}.", params: ".\$DBI::lasth->\{Statement}."time: ".(time-\$t0)."\\n";
warn \$DBI::lasth->\{Statement}.", time: ".(time-\$t0)."\\n";

return wantarray ? \@\$result : \$result;
EOF

	return $codestr;
} # end warn_dbexecute


sub profile_dbexecute {
	# This is a database execute profiling sub
	# Stores inside the $profiling_log the execute database name, the SQL statement,
	# and the time taken to execute
	# we can't use usertime because all the work is being done outside the server, in the database.
	my $thepackage	= shift;
	my $themethod	= shift;

	my $codestr 	= <<EOF;

my \$time = localtime;
my \$ru1 = time;
my \$result;
if (wantarray) {
	\$result = [ \&{"$thepackage"."_HPDTToverload_"."$themethod"} (\@_) ];
} else {
	\$result = \&{"$thepackage"."_HPDTToverload_"."$themethod"} (\@_);
}
my \$ru2 = time;

my \$sp_name = lc(\$DBI::lasth->\{Statement});
\$sp_name =~ s/exec ([^ ]+).*\$/\$1/og;
\$sp_name =~ s/(p_[^ ]+).*\$/\$1/og;
\$sp_name =~ s/^(select .+) where.+\$/\$1/og;
	
#if (\$DBI::lasth->\{Database}->\{Name} =~ /barbie/) {
open OUTFILE, ">>$profiling_log";
#print OUTFILE join(",", '', \$sp_name, '"'.\$DBI::lasth->\{Statement}.'"', sprintf('%.4f',\$ru2-\$ru1)."\\n");
print OUTFILE join("\\t", "[\$time]", '"'.\$DBI::lasth->\{Statement}.'"', sprintf('%.4f',\$ru2-\$ru1)."\\n");
close OUTFILE;
#}

return wantarray ? \@\$result : \$result;
EOF

	return $codestr;
} # end profile_dbexecute


sub profile_dbexecute_inline {
	# This is a database execute profiling sub that displays results directly on the screen.
	# we can't use usertime because all the work is being done outside the server, in the database.
	my $thepackage	= shift;
	my $themethod	= shift;

	my $codestr 	= <<EOF;

my \$ru1 = time;
#my \$result = goto \&{"$thepackage"."_HPDTToverload_"."$themethod"};
my \$result;
if (wantarray) {
	\$result = [ \&{"$thepackage"."_HPDTToverload_"."$themethod"} (\@_) ];
} else {
	\$result = \&{"$thepackage"."_HPDTToverload_"."$themethod"} (\@_);
}
my \$ru2 = time;

my \$sp_name = lc(\$DBI::lasth->\{Statement});
\$sp_name =~ s/exec ([^ ]+).*\$/\$1/og;
\$sp_name =~ s/(p_[^ ]+).*\$/\$1/og;
\$sp_name =~ s/^(select .+) where.+\$/\$1/og;
	
if ((\$ru2 - \$ru1) >= 0.1) {
	print "<div class=profilingBad>";
} elsif ((\$ru2 - \$ru1) >= 0.03) {
	print "<div class=profilingAvg>";
} else {
	print "<div class=profilingGood>";
}
my \$sp = \$DBI::lasth->\{Statement};
\$sp =~ s/'/\\\\'/g;
print "<a href=\\"javascript: openPopup('/qa/sp_detail?sp=\$sp','sp_detail','height=450,width=600,scrollbars=yes,resizable=yes,screenx=1,screeny=1,top=1,left=1')\\">\\n";
print join(" --> ", \$DBI::lasth->\{Statement},sprintf('%.4f',\$ru2-\$ru1));
print "</a></div>\\n";

return wantarray ? \@\$result : \$result;
EOF

	return $codestr;
} # end profile_dbexecute_inline


#############################################################################
#
#               END METHODS TO USE FOR OVERLOADING
#
#############################################################################

1;
