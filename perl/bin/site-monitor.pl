#!/usr/bin/perl
# ---------------------------------------------------------------------------- #
# site-monitor.pl
# ---------------------------------------------------------------------------- #
# Script for retrieving monitoring data from web applications.
#
# ./bin/site-monitor.pl
# ---------------------------------------------------------------------------- #

use Carp;
use strict;
use warnings;
use FindBin qw($Bin);
use Cwd qw(realpath);
use Log::Log4perl qw(:easy :no_extra_logdie_message);
use Sys::Hostname;

use lib "$Bin/../lib";

use SiteMonitor;
use CLI::Environment;
use CLI::Configuration;

# ---------------------------------------------------------------------------- #
# Main
# ---------------------------------------------------------------------------- #
MAIN:
{
	(my $root = $Bin) =~ s![\w-]+/[\w-]+/bin$!!o;
	
	## initialize Environment ##
	my $env	= { r => $root };
	$env	= CLI::Environment->new(
				$env,
			);
	$env->load_classes( qw(CLI::Profiler) );
	
	## initialize the main object ##
	my $main = SiteMonitor->new( $env, { _env => $env } );
	$main->db_file( $root . 'site-monitor/python/development.db' );
	$main->run;
	
	exit(0);
}


1;

__END__

=head1 NAME

publisher.pl


=head1 SYNOPSIS

 ./bin/site-monitor.pl


=head1 DESCRIPTION

This script is used to generate data for monitoring files.

The -e flag defaults to 'dev'.


=head1 REQUIRES

=over 4

=item C<Projects>

Uses 'affiliate', 'manager', 'coreservices' and 'taxii'.

=item C<strict>

Maintains strict declarations of variables.

=item C<Getopt::Long>

Allows params to be set as the script is executed.

=item C<Term::ANSIColor>

Used to present verbose results in color.

=item C<FindBin>

Used to get default location of the script.

=item C<CLI::Environment>

API for the environment variables.

=item C<CLI::Configuration>

API for the configurtation parameters.

=back


=head1 USAGE

./bin/publisher.pl -v=3 -placementID=1 -data=iqe -by=atom -cleanup -ftp

   -h               help
   -l               write to a log file
   -p               turn on profiling
   -d=#             debug level
   -v=#             verbose level
   -t=#             test loop/iteration
   -e=string        prod|qa|dev enviroment
   -c=string        US|GB|DE|FR country code (optional: US)
   -publisherID=#   the Publisher ID (optional: [PUBLISHER_ID])


=head1 OPTIONS

=head2 MAIN OPTIONS

=over 4

=item C<-h>

The help menu

=item C<-l>

Turns on logging to a file saved date.  Format is located in conf/publisher.yaml.

=item C<-p>

Turns on profiling and reporting.

=item C<-v=#>

The verbose level.

=item C<-d=#>

Debug level.

=item C<-t=#>

Test Loops.

=item C<-e=string>

The environment to run under (default is qa).

=item C<-c=string>

The country code to run under (default is US).

=back


=head1 REVISION HISTORY

Thursday, January 10, 2008 - v1.0:
  Initial release of script.


=head1 SEE ALSO

L<perl>


=head1 KNOWN BUGS

None.


=head1 AUTHORS

Thai Nguyen <thai@shopzilla.com>

=cut
