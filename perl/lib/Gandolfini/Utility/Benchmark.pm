=head1 NAME

Gandolfini::Utility::Benchmark

=cut

package Gandolfini::Utility::Benchmark;

=head1 SYNOPSIS


=head1 DESCRIPTION

Benchmark CPU cycles from begin to end markers.

=cut

=head1 REQUIRES

 use strict;
 use Benchmark

=cut

use strict;
use warnings;
use Benchmark;
use base 'Exporter';
use vars '@EXPORT';
our (@ISA);
@ISA = qw(Exporter);
@EXPORT = qw(cpubegin cpuend cpudiff);

use constant DEBUG_NONE		=> 0b00000000;
use constant DEBUG_WARN		=> 0b00000001;
use constant DEBUG_DUMPER	=> 0b00000010;



######################################################################

our ($VERSION, $debug);
BEGIN {
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 981 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
	$debug		= DEBUG_NONE;# | DEBUG_WARN;# | DEBUG_DUMPER;
}
our ($begin, $end);
######################################################################


=item C<cpubegin> ()

Marks the beginning of cpu timer

=cut

sub cpubegin
{
	$begin = '';
	$begin = Benchmark->new;
	return 1;

} #END OF SUB

=item C<cpuend> ()

Marks the end of the cpu timer

=cut

sub cpuend
{
	$end = '';
	$end  = Benchmark->new;
	return 1;

} #END OF SUB


=item C<cpudiff> ([action => 'print', action => 'return'])

Calculates the cpu difference and either prints to stderr or return to caller.

=cut

sub cpudiff
{
	my (%args) = @_;
	my $action = $args{'action'} || '';

	return undef if (! $begin && ! $end);

	my $timediff     = timestr(timediff($end,$begin));

	if ($action eq 'print')
	{
		print STDERR "CPU: $timediff \n";
	}
	elsif ($action eq 'return')
	{
		return $timediff;
	}
	else
	{
		#default is print to stderr
		print STDERR "CPU: $timediff \n";
		return 1;
	}

} #END OF SUB



1;

__END__

=back

=head1 REVISION HISTORY

=head1 AUTHOR

 Sagi Zelnick <szelnick@shopzilla.com>

=cut
