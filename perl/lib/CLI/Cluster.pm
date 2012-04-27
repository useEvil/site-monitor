# ----------------------------------------------------------------------------------------------- #
# CLI::Cluster
# Cluster.pm
# ----------------------------
# $Revision: 1.4 $
# $Date: 2003/01/22 00:56:51 $
# ----------------------------------------------------------------------------------------------- #
# DESCRIPTION OF FILE
#   Cluster.pm,  Cluster Class.
# ----------------------------------------------------------------------------------------------- #
package CLI::Cluster;

=head1 NAME

CLI::Cluster

=head1 SYNOPSIS

 use CLI::Cluster;
 my $conf = CLI::Cluster->new(  );

=head1 DESCRIPTION

The class handles the confirguration of the script.

=head1 REQUIRES

 use Carp;
 use strict;
 use YAML;
 use Class::Accessor::Fast;

 use base qw(Class::Accessor::Fast);

=head1 EXPORTS

Nothing

=cut

use Carp;
use strict;
use YAML;
use Net::SSH qw(ssh_cmd);
use Class::Accessor::Fast;
use Sys::Hostname qw(hostname);
use Framework::Email;

use base qw(Class::Accessor::Fast);

# ----------------------------------------------------------------------------------------------- #

our ($VERSION, @ISA, $TIMER);
use constant DEBUG_NONE     => 0b00000000;
use constant DEBUG_WARN     => 0b00000001;
use constant DEBUG_DUMPER   => 0b00000010;
use constant DEBUG_TRACE    => 0b00000100;
use constant DEBUG_INIT     => 0b00001000;
use constant DEBUG_SUBCLASS => 0b00010000;
use constant DEBUG_TEST     => 0b00100000;
use constant DEBUG_ALL      => 0b00111111;
use constant DEBUG_CLASS    => DEBUG_NONE; # | DEBUG_TEST | DEBUG_WARN | DEBUG_DUMPER | DEBUG_TRACE | DEBUG_INIT | DEBUG_SUBCLASS | DEBUG_ALL;

use constant FIELDS => [
    qw(sleep_time forks first_param param runs params last_param env host per_server error
      top_atoms servers pids child_status first_run last_run script country_code to_email from_email
      directory config_files config_dirs order_by servers_to_use user atom_sorted sorted_param logger ssh)
];

# ----------------------------------------------------------------------------------------------- #

BEGIN {
	$VERSION = do { my @REV = split(/\./, (qw$Revision: 1.8 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1] / 1000)) };
	__PACKAGE__->mk_accessors(@{ FIELDS() });
}

# ----------------------------------------------------------------------------------------------- #


sub CONSTANTS { }

=head1 CONSTANTS

=over 4

=cut


# ----------------------------------------------------------------------------------------------- #

sub CONSTRUCTORS { }

=back

=head1 METHODS

=head2 CONSTRUCTORS

=over 4

=item C<new> ( \%data )

Process all payment plans of the type given by $type.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = $class->SUPER::new( @_ );
	$self->logger->debug("[Running Cluster]");

	## set hostname ##
	$self->host( Sys::Hostname::hostname );

        $self->ssh('ssh') if !$self->ssh;

	## set per server and forks by country code ##
	$self->forks( $self->forks->{ $self->top_atoms           ? 'top' : $self->country_code } );
	$self->check_servers( $self->servers->{ $self->top_atoms ? 'top' : $self->country_code } );
	$self->per_server( $self->per_server->{ $self->top_atoms ? 'top' : $self->country_code } );
	$self->order_by( $self->order_by->{ $self->country_code } ) if ($self->order_by);
	$self->atom_sorted( $self->atom_sorted->{ $self->country_code } ) if ($self->atom_sorted);
	my $options = 
	      ($self->top_atoms ? ' -top'                     : '')
	    . ($self->directory ? ' -dir=' . $self->directory : '')
	    . ($self->config_files ? join('',map {" -conf=$_"}    @{$self->config_files}) : '')
	    . ($self->config_dirs  ? join('',map {" -confDir=$_"} @{$self->config_dirs }) : '')
	;
	$self->logger->info( "country_code[" . $self->country_code . "] forks[" . $self->forks . "] per_server[" . $self->per_server . "]" );
	$self->logger->info( "options[" . $options . " ]" );

	## define hash with runs to assign sequential order to hash; forks+1 should be last ##
	$self->pids( { } );
	$self->child_status( { } );
	$self->runs( [ ] );
	$self->first_run( 'run' . sprintf("%03d", 0) );
	$self->last_run( 'run' . sprintf("%03d", $self->forks + 1) );
	$self->params(
		{
			$self->first_run => sprintf($self->first_param, $self->country_code, $self->env) . $options,
		}
	);

	## setup each run based on how many forks we want ##
	my $order_by = { };
	foreach my $fork (1 .. $self->forks) {
		my $key = 'run' . sprintf("%03d", $fork);
		$self->params->{ $key } = sprintf($self->param, $self->forks, $fork, $self->country_code, $self->env) . $options;
		if ($self->order_by && grep { $fork == $_ } @{ $self->order_by }) {
			$order_by->{ $fork } = $key;
		} else {
			unshift @{ $self->runs }, $key;
		}
	}

	## order the runs by which process runs the longest ##
	if ($self->order_by) {
		foreach my $fork (@{ $self->order_by }) {
			unshift @{ $self->runs }, $order_by->{ $fork };
		}
	}

	## order the runs by which atoms are the largest ##
	if ($self->atom_sorted) {
		my $run = $self->forks + 1;
		foreach my $atom_id (reverse @{ $self->atom_sorted }) {
			my $key = 'run' . sprintf("%03d", ++$run);
			$self->params->{ $key } = sprintf($self->sorted_param, $atom_id, $atom_id, $self->country_code, $self->env) . $options;
			unshift @{ $self->runs }, $key;
		}
		$self->last_run( 'run' . sprintf("%03d", $run + 1) );
	}
	$self->params->{ $self->last_run } = sprintf($self->last_param,  $self->country_code, $self->env) . $options;

	## debug testing set count to sleep time ##
	$TIMER = $self->sleep_time if (DEBUG_CLASS & DEBUG_TEST);

	return $self;
} # END of new


# ----------------------------------------------------------------------------------------------- #

sub INITIALIZATION_METHODS { }

=back

=head2 INITIALIZATION METHODS

=over 4

=cut


# ----------------------------------------------------------------------------------------------- #

sub OBJECT_METHODS { }

=back

=head2 OBJECT METHODS

=over 4

=item C<fork_processes> (  )

Returns the dbh file path, use the root path if given.

=cut

sub fork_processes {
	my $self = shift;
	return unless (ref $self);

	## setup the SIGCHLD handler ##
	local $SIG{CHLD} = $self->sigchld_handler;

	## first run ##
	$self->logger->info( "starting first run: cleanup" );
	$self->fork_process( $self->first_run, $self->servers->[0] );
	$self->check_forked_processes({fork => 0}); # wait for child; don't start more children
	$self->logger->info( "finished first run: cleanup" );

	## run on all servers at once, run $n forks per server  ##
	$self->logger->info( "starting worker runs" );
	foreach my $n (1 .. $self->per_server) {
		foreach my $server (@{ $self->servers }) {
			$self->fork_process( $self->get_run, $server );
		}
	}
	$self->check_forked_processes; # wait for children to finish
	$self->logger->info( "finished all worker runs" );

	## last run ##
	$self->logger->info( "starting last run: ftp & verify" );
	$self->fork_process( $self->last_run, $self->servers->[0] );
	$self->check_forked_processes; # wait for child
	$self->logger->info( "finished last run: ftp & verify" );

	## clear the SIGCHLD handler ##
	local $SIG{CHLD} = undef;

	return;
}    # END of fork_process


=item C<fork_process> ( $run, $server )

Forks off a process on the given server.

=cut

sub fork_process {
	my $self    = shift;
	return unless (ref $self);
	my $run     = shift                 or $self->logger->logdie( "NO run given" );
	my $server  = shift                 or $self->logger->logdie( "NO server given" );
	my $params  = $self->params->{$run} or $self->logger->logdie( "NO params given" );
	my @command = ($self->ssh, $server, '"' . $self->script . ' ' . $params . '"');
	@command    = ($self->script, $params) if ($self->host eq $server); # skip ssh if local server
	my $command = join(' ',@command);
	$self->logger->info( "run[${run}] command[${command}]" );

	## fork the processes and exit once it's done ##
	my $child = fork();
	if ( !defined($child) ) {
	    $self->logger->logdie( "fork failed: $!");
        } elsif ( $child == 0 ) {
                # child sub-process starts here

		## debug testing code, sleep() not exec() ##
		if (DEBUG_CLASS & DEBUG_TEST) {
			$TIMER += $self->sleep_time;
			sleep($TIMER);
			exit(0);
		}

		## execute command and do not wait for it ##
#		system( $command ) == 0 or $self->logger->logdie("Can't perform: $command");
		exec $command;
		$self->logger->logdie("exec: $!");
	} else {
	        # parent resumes
	        my $key = join('-', $run, $server);
	        $self->pids->{ $key } = $child;
	}

	return $child;
}    # END of fork_process


=item C<check_forked_processes> (  )

Iterates over list of child processes, checking to see if each is still running, then returns
if none are running, otherwise sleeps for $self->sleep_time and repeats.

Optional arguments:
fork => 1 [default]  Fork additional children on a server after the previous process has ended on that server

=cut

sub check_forked_processes {
	my $self = shift;
	my $args = shift || {};

        my $fork = exists $args->{fork} ? $args->{fork} : 1;

	while (1) {
		# $self->pids is hash of running processes
		foreach my $key (sort keys %{ $self->pids }) {
			my ($run, $server) = split('-', $key);
			my $pid = $self->pids->{$key}
			    or next; # $pid == 0 for entries holding statistics

			# Sending a kill 0 actually just checks that a
			# job is still running.
			if (kill(0,$pid)) {
				$self->logger->debug( "run[$run] server[$server] pid[$pid] [Still Executing]" );
			} else {
				$self->logger->debug( "run[$run] server[$server] pid[$pid] [Finished Executing]" );
				delete $self->pids->{ $key };

				# are there more runs in the queue?
				if ($fork && @{ $self->runs }) {
				        # yes, so start the next on on this freed up server
					$self->fork_process( $self->get_run, $server );
				} else {
				        # no. log some statistics
					$self->pids->{ join('-', ++$TIMER, $server) } = 0;
				}
			}
		}

		## check to see if all servers have finished ##
		my $count;
		map { $count += $_ } values %{ $self->pids };
		$self->logger->debug( "count[${count}] [Forks Still Executing]" );
		return unless ($count);

		## exit on error ##
		exit($self->error) if ($self->error);

		## if the scripts are not finished yet, check again in XXX seconds ##
		sleep($self->sleep_time) if ($self->sleep_time);
	}
	$self->logger->debug( "Finished" );
}    # END of check_forked_processes


=item C<check_servers> ( $servers )

Forks off a process on the given server.

=cut

sub check_servers {
	my $self    = shift;
	return unless (ref $self);

	my $servers = shift or $self->logger->logdie( 'NO servers given' );
	my $to_use  = $self->servers_to_use->{ $self->country_code }
	    || scalar @{$servers}; # use all

        my @consider = @{$servers};
	my @use;
	# find servers that are working and have low load
	foreach my $server (@consider) {
		if ($self->check_server( $server )) {
		        push @use, $server;
		        $server = undef; # remove from consideration
		}
		last if (scalar(@use) >= $to_use);
	}

        # if we don't have enough servers yet, take another pass, ignoring load
        if (scalar(@use) < $to_use) {
	        foreach my $server (@consider) {
	                next if !$server;
		        push @use, $server if ($self->check_server( $server, 1 ));
		        last if (scalar(@use) >= $to_use);
	        }
        }

	return $self->servers( \@use );
}    # END of check_servers


=item C<check_server> ( $servers )

Forks off a process on the given server.

=cut

sub check_server {
	my $self    = shift;
	return unless (ref $self);
	my $server = shift or return;
	my $check  = shift || 0;
	my $has_load;
	eval {
		my $data = ssh_cmd(
			{
				user    => $self->user,
				host    => $server,
				command => '/usr/bin/uptime',
			}
		);
		$data =~ /load average: (\d+[.]\d+),/;
		$has_load++ if ($1 > 3.1);
	};
	if ($@) {
	    $self->logger->info( "$server: failed to connect: $@" );
	    return;
	}
	return 1 if $check;
	return 1 if !$has_load;
	return;
}    # END of check_server


=item C<get_run> (  )

Returns the first run from the top of the array and re-caches.

=cut

sub get_run {
	my $self = shift;
	return unless (ref $self);
	return shift @{ $self->runs };
}


=item C<set_sigchld> (  )

Sets up the SIGCHLD handler to send an email when the script fails.

=cut

sub sigchld_handler {
    my $self = shift;

    # this block of code based on: http://perldoc.perl.org/perlipc.html#Signals
    use POSIX ":sys_wait_h";
    return sub {
        local *__ANON__ = "sigchld_handler"; # name the anon sub
        my $child;
        # If a second child dies while in the signal handler caused by the
        # first death, we won't get another signal. So must loop here else
        # we will leave the unreaped child as a zombie. And the next time
        # two children die we get another zombie. And so on.
        local($?, $!);
        while (($child = waitpid(-1,POSIX::WNOHANG)) > 0) {
            $self->child_status->{$child} = $?; # store the status
            #warn "sigchld_handler: $child: exit code: $?\n", ;

            my %pids = reverse %{ $self->pids };
            my ($run, $server) = split('-', $pids{$child});
            next if !$run; # not a child we're tracking

            my $params = $self->params->{ $run };
            $self->logger->debug( "pid[${child}] run[${run}] params[${params}]" );

            if (POSIX::WEXITSTATUS($self->child_status->{$child}) != 0) {
                # failure exit code

                ## restart forked process ##
                #$self->fork_process($run, $server);

                #$self->failure_email($run, $server, $params);

                #$self->error( "Process ${run}\@${server} Failed" );
                $self->logger->logdie( "Process($child) ${run}\@${server} Failed with exit code " . POSIX::WEXITSTATUS($self->child_status->{$child}) );
            }
        }
        $SIG{CHLD} = $self->sigchld_handler; # reinstal handler
    };
}


## send email to list ##
sub failure_email {
    my $self = shift;
    my $run = shift;
    my $server = shift;
    my $params = shift;

    my $mail = Framework::Email->new();
    my $body = qq!
Process Failed
-------------------------------------------------------
Run:    $run
Server: $server
Params: $params
-------------------------------------------------------
!;

    $mail->to( $self->to_email );
    $mail->from( $self->from_email );
    $mail->subject( 'Publisher: Process Failed' );
    $mail->body( $body );
    $mail->send_email
        or $self->logger->warn( "Failed to send Process Failed Email" );
}


# ----------------------------------------------------------------------------------------------- #

sub STATIC_METHODS { }

=back

=head2 STATIC METHODS

=over 4

=cut


# ----------------------------------------------------------------------------------------------- #

sub PROTECTED_METHODS { }

=back

=head2 PROTECTED METHODS

These methods should only be used by CLI::Cluster.

=over 4

=cut


# ----------------------------------------------------------------------------------------------- #

sub REVISION_HISTORY { }

1;

__END__

=back

=head1 REVISION HISTORY

 $Log: Cluster.pm,v $

=head1 SEE ALSO

L<perl>

=head1 KNOWN BUGS

None

=head1 AUTHOR

Thai Nguyen <thai@shozilla.com>

=cut
