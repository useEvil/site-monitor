# Gandolfini::Logging
# ----------------------------
# $Revision: 1860 $
# $Date: 2007-12-21 04:31:24 -0800 (Fri, 21 Dec 2007) $
# ----------------------------

package Gandolfini::Logging;

=head1 NAME

 Gandolfini::Logging

=head1 SYNOPSIS

=head1 DESCRIPTION

Manages a queue of Log entries, later processing the queue by writing the appropriate logs.

=head1 REQUIRES

 LWP

=cut

use strict;
use warnings;
use vars qw(@EXPORT);
use Carp qw(carp);
use LWP::UserAgent;
use Scalar::Util qw/reftype/;
use URI::Escape qw(uri_escape);

use Gandolfini::DashProfiler extsys_profiler => [ "Logging" ];

######################################################################

use constant LOG_TYPE_DB                => 0b00000001;
use constant LOG_TYPE_LOCAL             => 0b00000010;
use constant LOG_TYPE_REMOTE            => 0b00000100;
use constant LOG_TYPE_ERRLOG            => 0b00001000;
use constant LOG_TYPE_GNDN              => 0b00010000;
use constant LOG_TYPE_REMOTE_CUMM_POST  => 0b00100000;
use constant LOG_TYPE_ALL               => 0b00111111;

######################################################################

use constant DEBUG_NONE             => 0b00000000;
use constant DEBUG_ADD_ENTRY        => 0b10000000;
use constant DEBUG_DB               => LOG_TYPE_DB;
use constant DEBUG_LOCAL            => LOG_TYPE_LOCAL;
use constant DEBUG_REMOTE           => LOG_TYPE_REMOTE;
use constant DEBUG_GNDN             => LOG_TYPE_GNDN;
use constant DEBUG_REMOTE_CUMM_POST => LOG_TYPE_REMOTE_CUMM_POST;
use constant DEBUG_ALL              => LOG_TYPE_ALL;

use constant DEBUG => DEBUG_NONE;# | DEBUG_ALL;


# Remote logging server needs this
use constant REMOTELOG_URI	=> '/remotelog.html';
use constant REMOTELOG_HDR	=> 'BizRateLogData';

######################################################################

=head1 EXPORTS

=head2 LOG TYPES

=item * LOG_TYPE_DB

Log entry to database. $destination is a DataClass, $data must be an arrayref.

=item * LOG_TYPE_LOCAL

Log entry to file. $destination is a filename.

=item * LOG_TYPE_REMOTE

Log entry to remote log server. $destination is a server hostname, or an arrayref of server hostnames.

=item * LOG_TYPE_GNDN

Log entry to bit bucket. Can be activated with debugging. Merely a useful placeholder.

(GNDN == "Goes Nowhere, Does Nothing")

=cut

BEGIN {
	@EXPORT = qw(LOG_TYPE_GNDN LOG_TYPE_DB LOG_TYPE_LOCAL LOG_TYPE_REMOTE LOG_TYPE_REMOTE_CUMM_POST);
	use base 'Exporter';
}

=head1 METHODS

=over 4

=item C<new> ( )

 Creates new Logging object.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	bless {
			queue	=> [ ],
			ua		=> LWP::UserAgent->new('BizRateRemoteLog/' . (split(' ', '$Revision: 1860 $'))[-2]), 
		}, $class;
}

=item C<cleanup> ( )

 Clean up and reset Logging object.

=cut

sub cleanup {
	my $self = shift;
	return undef unless ref($self);
	carp __PACKAGE__ . ' cleanup() called with pending queue items!'
		if (@{ $self->{queue} });
	$self->{queue} = [ ];	# Reset queue
	1;
}

=item C<add_entry> ( $type, $destination, $data )

 Add an entry to the queue.
 $type is a bitmask which must be one or more of the constants specified above under L<"LOG TYPES">.
 $destination can be a scalar value, or a hash with the constants specified above under L<"LOG TYPES">
as its keys. Each type-specific destination is specified above under L<"LOG TYPES">.
 $data can be an arrayref or a scalar if allowed (LOG_TYPE_DB requires an arrayref, all other types
will flatten the arrayref into a space-delimited string, substituing '-' for undefined values.
 $data can also optionally be a closure (subref) which when called returns the appropriate data type
(scalar or arrayref.)  This is very useful since logging data isn't always ready to be written until
very late in a request.

 In order to have an individual entry use multiple types, a destination must be provided for each type,
otherwise it won't work properly.

=cut

sub add_entry {
	my $self = shift;
	return undef unless (ref $self);
	my $type = shift || return undef;	# DB or REMOTE or LOCAL
	my $dest = shift || return undef;	# class for db, hostname for remote
	my $data = shift;

	if (DEBUG & DEBUG_ADD_ENTRY) {
	    eval { 
		my @dest = (ref $dest eq 'HASH' ) ? %$dest : ($dest);
		my @data = (ref $data eq 'ARRAY') ? @$data : ($data);
		no warnings 'uninitialized';
		printf STDERR "log %08b\t{%s}\t%s\n", $type, "@dest", "@data";
	    } or warn $@;
	}   

	push @{ $self->{queue} }, [ $type, $dest, $data ];
	1;
}

=item C<process_queue> ( )

 Run through entire queue, processing each entry (writing the appropriate log.)
 This should probably not be called until after all client processing is complete.

=cut

sub process_queue {
	my $self = shift;
	return undef unless (ref $self);
	warn __PACKAGE__ . " - processing queue" if (DEBUG & DEBUG_ALL);
	
	my %remote_cumm_post_data;
	
	while (my $entry = $self->_dequeue()) {
		my($types, $dests, $data) = @$entry;
		# Handle data closure
		$data = $data->()
			if (ref $data and reftype($data) eq 'CODE');
		if ($types & LOG_TYPE_DB) {
			my $dest = (ref $dests and reftype($dests) eq 'HASH') ? $dests->{LOG_TYPE_DB()} : $dests;
			$self->_process_DB_entry($dest, $data);
		}
		if ($types ^ LOG_TYPE_DB) {	# Still more work to do
			# All other types need array exploding
			$data = join(' ', map { defined($_) ? $_ : '-' } @$data)
				if (ref $data and reftype($data) eq 'ARRAY');
			if ($types & LOG_TYPE_LOCAL) {
				my $dest = (ref $dests and reftype($dests) eq 'HASH') ? $dests->{LOG_TYPE_LOCAL()} : $dests;
				$self->_process_LOCAL_entry($dest, $data);
			}
			if ($types & LOG_TYPE_REMOTE) {
				my $dest = (ref $dests and reftype($dests) eq 'HASH') ? $dests->{LOG_TYPE_REMOTE()} : $dests;
				$self->_process_REMOTE_entry($dest, $data);
			}
			if ($types & LOG_TYPE_REMOTE_CUMM_POST) {
				my $dest = (ref $dests && reftype($dests) eq 'HASH') ? $dests->{LOG_TYPE_REMOTE_CUMM_POST()} : $dests;
				$self->_pre_process_REMOTE_CUMM_POST_entry($dest, $data, \%remote_cumm_post_data);
			}
			if ($types & LOG_TYPE_ERRLOG) {
				my $dest = (ref $dests and reftype($dests) eq 'HASH') ? $dests->{LOG_TYPE_ERRLOG()} : $dests;
				$self->_process_ERRLOG_entry($dest, $data);
			}
			if ($types & LOG_TYPE_GNDN) {
				my $dest = (ref $dests and reftype($dests) eq 'HASH') ? $dests->{LOG_TYPE_GNDN()} : $dests;
				$self->_process_GNDN_entry($dest, $data);
			}
			if ($types & ~LOG_TYPE_ALL) {	# Check 1's complement of LOG_TYPE_ALL
				warn __PACKAGE__ . " - unrecognized log type " . unpack('b8', pack('c', $types & ~LOG_TYPE_ALL)) . " in queue\n";
			}
		}
	}
	
	# do cummulative entries, as a single log entry event
	if(%remote_cumm_post_data) {
		$self->_process_REMOTE_CUMM_POST_entries(\%remote_cumm_post_data);
	}
	
	1;
}

sub _process_DB_entry {
	my $self = shift;
	my $dclass = shift;
	my $args = shift;
	warn __PACKAGE__ . " - processing DB entry: $dclass\n\t" . join (',', @$args) . "\n" if (DEBUG & DEBUG_DB);
	eval {
		$dclass->run(@$args);
	};
	if ($@) {
		warn __PACKAGE__ . " - error processing DB log entry: $@";
		return undef;
	}
	1;
}

sub _process_LOCAL_entry {
	my $self	= shift;
	my $logfile	= shift || return undef;
	chomp(my $logline	= shift || return undef);
	warn __PACKAGE__ . " - processing LOCAL entry: $logfile\n\t$logline\n" if (DEBUG & DEBUG_LOCAL);

	open(LOG, ">> $logfile") || return (warn(__PACKAGE__ . " - could not open LOCAL logfile $logfile, $!") && undef);
	print LOG $logline . "\n";
	close LOG;
	1;
}

sub _process_REMOTE_entry {
	my $self		= shift;
	my $loghosts	= shift || return undef;
	my $logline		= shift || return undef;

	$loghosts		= [ $loghosts ] unless (ref $loghosts and reftype($loghosts) eq 'ARRAY');
	return undef unless (@$loghosts);
	my $ua 			= $self->ua();
	$ua->timeout(1);	# NEVER put the timeout higher than 1, the servers would burn up
	my $URI			= $self->REMOTELOG_URI();

	warn "[$$] Logging $logline to remote hosts\n" if (DEBUG & DEBUG_REMOTE);
	my $headers = HTTP::Headers->new($self->REMOTELOG_HDR() => $logline);
# 	$headers->referer($r->uri);		# not used
	my $success = 0;
	foreach my $loghost (@$loghosts) {

                my $ps = extsys_profiler($loghost) if extsys_profiler_enabled();

		my $req 	= HTTP::Request->new(GET => 'http://' . $loghost . $URI, $headers);
		my $res 	= $ua->request($req);
		if ($res->is_success) {
			$success++;
			warn "[$$]\tlogged to server $loghost\n" if (DEBUG & DEBUG_REMOTE);
		} else {
			warn "[$$] WARNING: Could not write log entry to log server $loghost\n";
		}
	}

	unless ($success) {
		warn "[$$] CRITICAL: Could not write log entry to any defined log server\n";
		return 0;
	}

	1;
}

sub _pre_process_REMOTE_CUMM_POST_entry {
    my $self        = shift;
	my $loghosts	= shift || return undef;
	my $logdata		= shift || return undef;
    my $cumm_data   = shift || return undef;
    
    foreach my $loghost (@$loghosts) {
        
        my $data_array_ref = $$cumm_data{$loghost};
        if(!defined $data_array_ref) {
            my @new_array;
            $data_array_ref = \@new_array;
            push @$data_array_ref,$logdata;
            $$cumm_data{$loghost} = $data_array_ref;
        }
        else {
            push @$data_array_ref,$logdata;
        }
        
        warn "[$$] pre-processing, adding logdata = '$logdata', for loghost = '$loghost'" if(DEBUG & DEBUG_REMOTE_CUMM_POST);
    }
    
    1;
}

sub _process_REMOTE_CUMM_POST_entries {
	my $self		= shift;
	my $cumm_data	= shift || return undef;
	
	my $ua 			= $self->ua();
	$ua->timeout(1);	# NEVER put the timeout higher than 1, the servers would burn up
	my $success = 0;
	
	my @dests = keys %$cumm_data;
	foreach my $dest (@dests) {
	    
        my %uri_hash;
	
        my $var_count = 0;
        foreach my $datum (@{$$cumm_data{$dest}}) {
            
            # logline has 3 components:
            #   uri
            #   post variable name type
            #   data (everything else)
            my @tokens = split(" ",$datum,3);
            my $uri = $tokens[0];
            my $data_type = $tokens[1];
			my $data = uri_escape($tokens[2]);
			
			# keep track of the count of variables to be posted, and
			# construct post variable names with count appended for uniqueness
			$uri_hash{$uri}->{$data_type . "_$var_count"} = $data;
			$var_count++;
        }

    	foreach my $uri (keys %uri_hash) {
        
            my $uri_hash_ref = $uri_hash{$uri};
        	my $query_string;
        	my @vars = keys %$uri_hash_ref;
        	foreach my $var (@vars) {
            	if(!$query_string) {
                	$query_string = "$var=" . $$uri_hash_ref{$var};
            	}
            	else {
                	$query_string .= "&$var=" . $$uri_hash_ref{$var};
            	}
        	}
        	
            my $req = HTTP::Request->new(POST => 'http://' . $dest . "/" . $uri);
            $req->content_type('application/x-www-form-urlencoded');
            $req->content($query_string);
            my $ps = extsys_profiler($dest) if extsys_profiler_enabled();
            my $res = $ua->request($req);
            if ($res->is_success) {
                $success++;
                warn "[$$]\tlogged to server $dest\n" if (DEBUG & DEBUG_REMOTE_CUMM_POST);
            } else {
                warn "[$$] WARNING: Could not post log entry to log server $dest\n";
            }
        }
    }
	
	unless ($success) {
		#warn "[$$] CRITICAL: Could not post cummulative log entry to any defined log server\n";
		return 0;
	}

	1;
}

sub _process_ERRLOG_entry {
	my $self	= shift;
	my $dest	= shift;
	my $data	= shift;
	print STDERR . "[$$] Logging $dest: \n\t$data\n";
	1;
}

sub _process_GNDN_entry {
}

sub _dequeue { shift @{ $_[0]->{queue} } }

sub ua		{ $_[0]->{ua}	}

1;

__END__

=back

=head1 AUTHOR

 David Pisoni <dpisoni@bizrate.com>

=cut
