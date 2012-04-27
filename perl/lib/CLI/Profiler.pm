# Profiler.pm
#
# Tool for profiling code
#

=head1 NAME

Profiler

=head1 SYNOPSIS

 use Profiler;

 my $p = Profiler->new();

 # First region to be profiled:
 $p->start('First part');
 
 # Do someting...
 $p->stop('First part');
 
 # Second region to be profiled:
 $p->start('Second part');
 
 # Do something else
 $p->stop('Second part');

 # Print report for all regions:
 print $p->report();

 # Print report for region named 'Second part':
 print $p->report('Second part');

=head1 DESCRIPTION

This module provides a way to profile Perl code by adding start()/stop()
calls throughout the code you are interested in.  First, create the
object with the new() method.  Then call the start() method with a name
to name this region (for the report), and call stop() where you want the
clock to stop.	The number of start() calls are recorded, so if you call
start/stop multiple times on the same name the total number of starts and
time will be added up.	The report includes:

 - clock name
 - number of hits (starts)
 - total time
 - total time per hit

It uses Time::HiRes for accuracy.

=head1 SEE ALSO

Time::HiRes

=head1 AUTHOR

Bjorn Solberg <bsolberg@shopzilla.com>

=head1 PREREQUISITES

=over 4

=item *

Perl 5.6.0 or greater

=back

=head1 METHODS

The rest of the documentation details each of the object methods. 
Internal methods are usually preceded with an underscore ('_').

=cut
#---------------------------------------------
package CLI::Profiler;

use strict;
use Time::HiRes;

#---------------------------------------------

=head2 new

 Title:     new
 Usage:     my $profiler = Profiler->new();
 Function:  Create a new instance of this class on which the start(),
            stop(), report() (and other methods) can be called
 Args:      (optional) a name to be used as a default name for the
            region you're profiling.  Otherwise a hard coded default
            will be used if no name is given to the start/stop methods.

=cut
#'
sub new {
	my $proto	= shift;
	my $class	= ref($proto) || $proto;	# called as instance or class method?
	my $name	= shift || 'default name';
	my $self	= { name => $name, profiles => { } };
	return bless $self, $class;
}

#---------------------------------------------

=head2 start

 Title:     start
 Usage:     $profiler->start('A name');
 Function:  Start the clock for the region named 'A name'.
 Args:      (optional) a name for the region you're profiling - if no
        name, then the default given during object instantiation
        is used.

=cut
#'
sub start {
	my $self			= shift;
	my $name			= shift || $self->name;
	my ($sec, $usec)	= Time::HiRes::gettimeofday();
	$self->clear( $name ) unless (exists $self->profiles->{ $name }->{'start'});
	$self->profiles->{ $name }->{'start'} = $sec + $usec / 1000000;
	$self->profiles->{ $name }->{'hits'}++;
}

#---------------------------------------------

=head2 stop

 Title:     stop
 Usage:     $profiler->stop('A name');
 Function:  Stop the clock for the region named 'A name'.
 Args:      (optional) a name for the region you're profiling - if no
            name, then the default given during object instantiation
            is used.

=cut
#'
sub stop {
	my $self = shift;
	my $name = shift || $self->name;
	if ($self->profiles->{ $name }->{'start'} == 0) {
		warn "Profiler: stop() called on name ($name) that has not been started yet - do nothing.";
		return;
	}
	my ($sec, $usec) = Time::HiRes::gettimeofday();
	$self->profiles->{ $name }->{'end'} = $sec + $usec / 1000000;
	my $thistime = $self->total( $name );
	$self->profiles->{ $name }->{'min'} ||= 0;
	$self->profiles->{ $name }->{'max'} ||= 0;
	if ($self->profiles->{ $name }->{'min'} <= 0 || $thistime < $self->profiles->{ $name }->{'min'}) {
		$self->profiles->{ $name }->{'min'} = $thistime || 0;
	}
	if ($self->profiles->{ $name }->{'max'} <= 0 || $thistime > $self->profiles->{ $name }->{'max'}) {
		$self->profiles->{ $name }->{'max'} = $thistime || 0;
	}
	$self->profiles->{ $name }->{'total'} += $thistime;
	$self->profiles->{ $name }->{'start'} = 0;
}

#---------------------------------------------

=head2 total

 Title:     total
 Usage:     $profiler->total( 'A name', '%0.6f' );
 Function:  Return the total time end - start.
 Args:      (optional) a name for the region you're profiling - if no
            name, then the default given during object instantiation
            is used.
            (optional) a format for sprintf.

=cut
#'
sub total {
	my $self	= shift;
	my $name	= shift || $self->name;
	my $format	= shift || "%.6f";
	my $time	= sprintf(
						$format,
						$self->profiles->{ $name }->{'end'} - 
						$self->profiles->{ $name }->{'start'}
					);
	return $time;
}

#---------------------------------------------

=head2 clear

 Title:     clear
 Usage:     $profiler->clear('A name');
 Function:  Clear the profiling info for the region named 'A name'.
 Args:      (optional) a name for the region you're profiling - if no
            name, then the default given during object instantiation
            is used.

=cut
#'
sub clear {
	my $self = shift;
	my $name = shift || $self->name;
	$self->profiles->{ $name }->{'totaltime'}	= 
	$self->profiles->{ $name }->{'perhit'}		= 
	$self->profiles->{ $name }->{'min'}			= 
	$self->profiles->{ $name }->{'max'}			= 
	$self->profiles->{ $name }->{'hits'}		= 
	$self->profiles->{ $name }->{'end'}			= 
	$self->profiles->{ $name }->{'start'}		= 
	$self->profiles->{ $name }->{'total'}		= 0;
}

#---------------------------------------------

=head2 report

 Title:     report
 Usage:     print $profiler->report('A name'); 
            my $report = $profiler->report();
 Function:  Generate a report for this profiler.  
 Args:      (optional) a name for the region you're profiling
 Returns:   a string containing the report

=cut
#'
sub report {
	my $self	= shift;
	my $name	= shift || '';
	my @names	= ( $name );
	if ($name eq '') {
		@names = keys %{ $self->profiles };
	}
	my $result = "\n";
	foreach $name (@names) {
		next if ($self->profiles->{ $name }->{'end'} == 0);
		my $totaltime	= sprintf("%.6f", $self->profiles->{ $name }->{'total'});
		$self->profiles->{ $name }->{'totaltime'} = $totaltime || 0;
		my $totalhits	= $self->profiles->{ $name }->{'hits'};
		$totalhits		= $totalhits ? $totalhits : 1;
		my $perhit		= $totaltime / $totalhits;
		$self->profiles->{ $name }->{'perhit'} = $perhit || 0;
#		my $min			= $self->profiles->{ $name }->{'min'};
#		my $max			= $self->profiles->{ $name }->{'max'};
	}
	foreach my $name (sort { $self->profiles->{ $b }->{'totaltime'} <=> $self->profiles->{ $a }->{'totaltime'} } keys %{ $self->profiles }) {
		$result .= sprintf("    %s: %d hits, %f secs, %f/%f/%f (min/max/avg)\n", $name, $self->profiles->{ $name }->{'hits'}, $self->profiles->{ $name }->{'totaltime'}, $self->profiles->{ $name }->{'min'}, $self->profiles->{ $name }->{'max'}, $self->profiles->{ $name }->{'perhit'});
	}
	return $result;
}


sub by_name {
	my $self	= shift;
	my $name	= shift || $self->name;
	return $self->profiles->{ $name };
}


sub profiles	{ $_[0]->{'profiles'}	}
sub name		{ $_[0]->{'name'}		}


1;

__END__
