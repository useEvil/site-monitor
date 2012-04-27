# Gandolfini::Logging::ProcessLogger
# -------------
# $Revision: 255 $
# $Date: 2005-04-06 07:27:36 -0700 (Wed, 06 Apr 2005) $
# -----------------------------------------------------------------------------

=head1 NAME

Gandolfini::Logging::ProcessLogger

=cut

package Gandolfini::Logging::ProcessLogger;

=head1 DESCRIPTION

Process logging class.

=cut

=head1 REQUIRES

 L<Apache::Constants>

=cut


use strict;
use warnings;
use Gandolfini::Logging;
use base 'Gandolfini::Logging';
use POSIX qw(strftime);
use Apache::Constants qw(:common :response);

######################################################################

our ($VERSION, $debug);
use constant DEBUG_NONE		=> 0b00000000;
use constant DEBUG_WARN		=> 0b00000001;
use constant DEBUG_DUMPER	=> 0b00000010;

BEGIN {
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 255 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
	$debug		= DEBUG_NONE;# | DEBUG_WARN;# | DEBUG_DUMPER;
}

######################################################################

=head1 METHODS

=over 4

=item C<handler> ( $apache_req )

Generic mod_perl Response handler

=cut

sub handler : method {
	my $class	= shift;
	my $r		= shift;
	my $self	= $class->new( $r );
	$self->run();
} # END of handler


=item C<new> ( $request_obj )

Base constructor

=cut

sub new {
	my $class	= shift;
	my $r		= shift;
	my $self	= $class->SUPER::new( @_ );
	$self->{'_r'}	= $r;
	$r->register_cleanup( sub { $self->process_queue(); } );
	$self;
} # END of new


sub r { $_[0]->{'_r'} }

=item C<run> ( )

=cut

sub run {
	my $self		= shift;
	return undef unless (ref $self);
	my $r			= $self->r;
	my $mem			= $self->get_mem_size;
	my $timestamp	= strftime( '[%d/%b/%Y:%H:%M:%S %z]', localtime($r->request_time()) );
	my $request		= $r->the_request;
	## PID Memmory Logging ##
	no warnings 'uninitialized';
	$self->pid_tracking_log( join('|', scalar(localtime), $$, $request, $mem) );
	OK;
} # END of run


=item C<get_mem_size> (  )

Returns the memory size for a pid.

  size       total program size
  resident   resident set size
  share      shared pages
  trs        text (code)
  drs        data/stack
  lrs        library
  dt         dirty pages

=cut

sub get_mem_size {
	my $class = shift;
	open PROC, "/proc/$$/statm";
		local $/ = undef;
		my $mem = <PROC>;
		chomp $mem;
	close PROC;
	my @sizes = split(/\s/, $mem);
	warn __PACKAGE__ . "->get_mem_size: memory[@sizes]\n" if ($debug & DEBUG_WARN);
	$mem = join('|', map { $_ * 4096 } @sizes);
	warn __PACKAGE__ . "->get_mem_size: memory[${mem}]\n" if ($debug & DEBUG_WARN);
	return $mem;
} # END of get_mem_size


=item C<pid_tracking_log> ( $log_entry )

Log PID, URI and memory values.

=cut

sub pid_tracking_log {
	my $self		= shift;
	my $log_entry	= shift || return undef;
	warn __PACKAGE__ . "->pid_tracking_log: log_entry[${log_entry}]\n" if ($debug & DEBUG_WARN);
	my $log_file	= $self->r->dir_config('PIDLogFile');
	return OK unless ($log_file);
	warn __PACKAGE__ . "->pid_tracking_log: log_entry[${log_file}]\n" if ($debug & DEBUG_WARN);
	$self->add_entry( LOG_TYPE_LOCAL, $self->r->server_root_relative( $log_file ), $log_entry );
} # END of pid_tracking_log


1;


__END__


=back

=head1 REVISION HISTORY

$Log$
Revision 1.3  2005/04/06 14:27:36  dpisoni
run() - suppressed extraneous warnings

Revision 1.2  2005/02/01 16:29:46  dpisoni
Turned off debugging

Revision 1.1  2005/02/01 01:26:32  thai
 - new module for handling pid memory size logging


=head1 AUTHOR

Thai Nguyen <thai@shopzilla.com>

=cut
