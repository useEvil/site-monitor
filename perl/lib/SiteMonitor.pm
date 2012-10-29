# ----------------------------------------------------------------------------------------------- #
# Copyright (c) 2006 All rights reserved.
# ----------------------------------------------------------------------------------------------- #

=head1 NAME

SiteMonitor - Base class for any retrieving data from various site monitoring applications.

=head1 SYNOPSIS

 use SiteMonitor;

=head1 DESCRIPTION

Provides a standard interface for in memory objects. Currently implemented over
Class::Accessor.

=head1 REQUIRES

 use utf8;
 use strict;
 use Cwd qw(realpath);

 use CLI;

 use base qw(CLI);

=head1 EXPORTS

Nothing

=cut

package SiteMonitor;

use utf8;
use strict;
use DBD::SQLite;
use XML::Simple;
use WWW::Mechanize;
use Net::Netid;
use MIME::Base64;
use Cwd qw(realpath);

use CLI;

use base qw(CLI);

our (@ISA, $VERSION);
use constant DEBUG_NONE     => $ISA[0]->DEBUG;
use constant DEBUG_WARN     => 0b00000001;
use constant DEBUG_DUMPER   => 0b00000010;
use constant DEBUG_TRACE    => 0b00000100;
use constant DEBUG_INIT     => 0b00001000;
use constant DEBUG_DBI      => 0b00010000;
use constant DEBUG_SUBCLASS => 0b00100000;
use constant DEBUG_TEST     => 0b01000000;
use constant DEBUG_ALL      => 0b01111111;
use constant DEBUG          => DEBUG_NONE;    # | DEBUG_WARN | DEBUG_DUMPER | DEBUG_TRACE | DEBUG_INIT | DEBUG_DBI | DEBUG_SUBCLASS | DEBUG_TEST | DEBUG_ALL;

use constant FIELDS => [
	qw(browser db_file dbh session_id data)
];

# ----------------------------------------------------------------------------------------------- #

BEGIN {
	$VERSION = do { my @REV = split(/\./, (qw$Revision: 1.5 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1] / 1000)) };
	__PACKAGE__->mk_accessors( @{ FIELDS() } );
}

# ----------------------------------------------------------------------------------------------- #


# ----------------------------------------------------------------------------------------------- #
# Constants.
# ----------------------------------------------------------------------------------------------- #

sub CONSTANTS { }

=head1 CONSTANTS

=over 4

=item C<LOCALE_INFO>

Default Locale Info for different country codes.

=cut

use constant LOCALE_INFO => {
	US => {
		thousands_sep   => [',', '.'],
		currency_symbol => '$',
		currency_first  => 1,
	},
	GB => {
		thousands_sep   => [',', '.'],
		currency_symbol => '£',
		currency_first  => 1,
	},
	DE => {
		thousands_sep   => ['.', ','],
		currency_symbol => 'Û ',
		currency_first  => 1,
	},
	FR => {
		thousands_sep   => ['.', ','],
		currency_symbol => ' Û',
		currency_first  => 0,
	},
};


# ----------------------------------------------------------------------------------------------- #
# Constructors.
# ----------------------------------------------------------------------------------------------- #

sub CONSTRUCTORS { }

=back

=head1 METHODS

=head2 CONSTRUCTORS

=over 4

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = $proto->SUPER::new( @_ );

	return $self;
}


# ----------------------------------------------------------------------------------------------- #
# Internal methods.
# ----------------------------------------------------------------------------------------------- #

sub INTERNAL_METHODS { }

=back

=head2 INTERNAL METHODS

=over 4

=item C<init> ( $filename )

Takes a list of Constants and creates a virtual method.

=cut

sub init {
	my $self = shift;
	return unless (ref $self);
	$self->profile->start('SiteMonitor::init') if ($self->environment->profile);
	my $file = shift || 'site-monitor/perl/conf/site-monitor.yaml';

	## Initialize Date and Configuration Object ##
	$self->date;

	## Initialize Configuration ##
	$self->conf->init( $self->environment->server_root_relative( $file ) );

	## Initialize Browser ##
	$self->browser( WWW::Mechanize->new( cookie_jar => { }, autocheck => 1, agent => $self->conf->user_agent ) );

	## Initialize Database Handle ##
	$self->dbh( DBI->connect( 'dbi:SQLite:dbname=' . $self->db_file, '', '', { RaiseError => 1 } ) ) if ($self->db_file);

	$self->profile->stop('SiteMonitor::init') if ($self->environment->profile);
}


=item C<run> (  )

Process the script.

=cut

sub run {
	my $self = shift;
	return unless (ref $self);
	$self->profile->start('run') if ($self->environment->profile);

	## print usage information ##
	$self->usage if ($self->environment->help);

	## set the date and GO! ##
	my $begin = $self->date;
	$self->print_stdout("\n##Script started [" . $begin->as_string . "]##\n\n");

	## init and print the configuration and environment ##
	$self->init( $self->environment->args('file') );

	$self->print_stdout("Configuration:\n");

#	$self->print_stdout( "\tServer:                 " . $self->data->dbh_set( 'iqe_main' )->[0] . "\n" );
	$self->print_stdout("\tServer:                 " . (Sys::Hostname::hostname                 || '') . "\n");
	$self->print_stdout("\tEnvironment:            " . ($self->environment->env                 || '') . "\n");
	$self->print_stdout("\tConfiguration File:     " . ($self->environment->args('file')        || '') . "\n");
	$self->print_stdout("\tCountry Code:           " . ($self->environment->code                || '') . "\n");
	$self->print_stdout("\tVerbose Level:          " . ($self->environment->verbose             || '') . "\n");
	$self->print_stdout("\tDebug Level:            " . ($self->environment->debug               || '') . "\n");
	$self->print_stdout("\tTest Loop:              " . ($self->environment->test                || '') . "\n");
	$self->print_stdout("\tProfile:                " . ($self->environment->args('p')                ? 'Yes' : 'No') . "\n");
	$self->print_stdout("\tLogging:                " . ($self->environment->args('l')                ? 'Yes' : 'No') . "\n");
	$self->print_stdout("\tCleanup:                " . ($self->environment->args('cleanup')          ? 'Yes' : 'No') . "\n");

	## execute the main function ##
	$self->main;

	my $end = $self->date( time, '%b %e %Y %T' );
	$self->print_stdout("\tTotal Time:             " . $self->_profile_time( $begin, $end ) . "\n");
	$self->print_stdout("\n##Script ended [" . $end->as_string . "]##\n\n");

	## print profiling information ##
	$self->profile->stop('run') if ($self->environment->profile);
	$self->print_stdout( $self->profile->report . "\n\n" ) if ($self->environment->profile);

	## print to a log file ##
	$self->print_log( $self->path_to_log, $self->conf->log_cleanup ) if ($self->environment->logged);
	$self->print_updates( $self->path_to_log, sprintf('xGrid: [' . $self->xgrid . '] End Time: [' . $end->as_string . '] [' . $self->_profile_time( $begin, $end ) . '] [' . ($end - $begin) . ']') ) if ($self->environment->logged);
}


=item C<main> (  )

Runs the script.

=cut

sub main {
	my $self = shift;
	return unless (ref $self);
	$self->profile->start('main') if ($self->environment->profile);

	## execute splunk function ##
	$self->splunk;

	## execute A10 function ##
	$self->a10_hosts;

	$self->profile->stop('main') if ($self->environment->profile);
}


=item C<usage> (  )

Returns the usage of the script.

=cut

sub usage {
	print qq!
        -h              help
        -l              write to a log file
        -p              turn on profiling
        -cleanup        cleanup files first
        -d=#            debug level
        -v=#            verbose level
        -t=#            test loop/iteration
        -e=string       prod|qa|dev enviroment
        -c=string       US|GB|DE|FR country code (optional: US)
        -conf=string    this parameter will override the default config file

!;
	exit(0);
}


# ----------------------------------------------------------------------------------------------- #
# Object methods.
# ----------------------------------------------------------------------------------------------- #

sub OBJECT_METHODS { }

=back

=head2 OBJECT METHODS

=over 4

=item C<splunk> (  )

Crawls the Splunk site

=cut

sub splunk {
	my $self   = shift;
	return unless (ref $self);
	my $params = $self->conf->monitor->{'splunk'};
	foreach my $page (@$params) {
		my $method = $page->{'method'};
		my $value  = $page->{'value'};
		if (UNIVERSAL::isa( $value, 'HASH' )) {
			$value->{'fields'}->{'password'} = decode_base64( $value->{'fields'}->{'password'} )
				if (exists $value->{'fields'}->{'password'});
			$self->print_stdout("\tMethod:                $method\n");
			$self->browser->$method( %$value );
#warn "self->browser->content[",$self->browser->content,"]\n";
		} else {
			$self->print_stdout("\tMethod:                $method\n");
			$self->print_stdout("\tValue:                 $value\n");
			$self->browser->$method( $value );
#warn "self->browser->forms\n" . Data::Dumper::Dumper( $self->browser->forms );
		}
	}
}


=item C<a10_hosts> (  )

Crawls the A10 load balancer to get the hosts from the VIPs.

=cut

sub a10_hosts {
	my $self = shift;
	return unless (ref $self);
	my $data = $self->get_a10_hosts;
	my @fields = qw(HOST_ID HOST_IP HOST_NAME HOST_PORT VIP_NAME STATUS);
#	$self->dbh->begin_work;
	foreach my $vip (keys %$data) {
		next if ($vip =~ /(DNS|NTP|DNS|LDAP|SMTP)/);
		my $members = $data->{ $vip }->{'members'}->[0]->{'member'};
		foreach my $row (@$members) {
			my $address = Net::Netid->netid( $row->{'address'} );
			next unless ($address->{'host'});
			my $sth     = $self->dbh->prepare('SELECT '. join(', ', @fields) . ' FROM host WHERE host_name = ? and host_port = ?;');
			$sth->bind_param( 1, $address->{'host'} );
			$sth->bind_param( 2, $row->{'port'} );
			$sth->execute();
	#		print '[' . join(']==[', $row->{'address'}, $row->{'port'}, $row->{'status'}, $address->{'host'}) . "]\n";
			if (my $hash = $sth->fetchrow_hashref) {
				print 'updating[' . join(']==[', $row->{'address'}, $row->{'port'}, $row->{'status'}, $address->{'host'}, $vip) . "]\n";
				$hash->{'VIP_NAME'}  = $vip;
				$hash->{'HOST_NAME'} = $address->{'host'};
				$hash->{'HOST_PORT'} = $row->{'port'};
				$hash->{'HOST_IP'}   = $row->{'address'};
				$hash->{'STATUS'}    = $row->{'status'};
				$sth = $self->dbh->prepare('UPDATE host SET ' . join(', ', map { $_ . "='" . $hash->{ $_ } . "'" } @fields) .' WHERE host_id = ?;');
				$sth->bind_param( 1, $hash->{'HOST_ID'} );
				$sth->execute();
			} else {
				print 'inserting[' . join(']==[', $row->{'address'}, $row->{'port'}, $row->{'status'}, $address->{'host'}, $vip) . "]\n";
				$sth = $self->dbh->prepare("SELECT max(host_id) AS MAX FROM host;");
				$sth->execute();
				my $res = $sth->fetchrow_hashref;
				my $max = $res->{'MAX'} + 1;
				$sth    = $self->dbh->prepare('INSERT INTO host (' . join(', ', @fields) . ') VALUES (' . $max . ", '" . $row->{'address'} . "', '" . $address->{'host'} . "', " . $row->{'port'} . ", '" . $vip . "', " . $row->{'status'} . ');');
				$sth->execute();
			}
		}
	}
#	my $sth = $self->dbh->prepare("SELECT host_id, host_ip, host_name, host_port, vip_name, status FROM host;");
#	$sth->execute();
#	while (my $row = $sth->fetchrow_hashref) {
#		print '[' . join(']==[', $row->{'HOST_ID'}, $row->{'HOST_IP'}, $row->{'HOST_NAME'}, $row->{'HOST_PORT'}, $row->{'VIP_NAME'}, $row->{'STATUS'}) . "]\n";
#	}
#	$self->dbh->commit;
}


=item C<format_number> ( [number|money|percent] => $value [, country => $country, decimals => $decimals, no_commas => 1/0 ] )

Return a number formatted for monetary value.

=cut

sub format_number {
	my $self     = shift;
	my %args     = @_;
	my $number   = $args{'money'} || $args{'percent'} || $args{'number'} || return 0;
	my $decimals = defined($args{'decimals'}) ? $args{'decimals'} : 2;
	my $comma    = LOCALE_INFO->{$self->environment->code}->{'thousands_sep'}->[0];
	my $decimal  = LOCALE_INFO->{$self->environment->code}->{'thousands_sep'}->[1];
	my ($result, $neg);
	if ($args{'decimals'} || $args{'money'} || $args{'percent'}) {
		if ($decimals == 0) {
			if (index($number, '.') == -1) {
				if (length($number) == 2) {
					$number = $decimal . $number;
				} elsif (length($number) == 1) {
					$number = $decimal . '0' . $number;
				} else {
					substr($number, -2, 0, $decimal);
				}
			}
			$result = $number;
		} else {
			$result = sprintf('%0.*f', $decimals, $number);
		}
	} else {
		$result = $number;
	}
	unless ($args{'no_commas'}) {
		my @chars = split('|', reverse $result);
		if ($chars[$#chars] eq '-') {
			pop @chars;
			$neg++;
		}
		my $num    = 0;
		my $count  = 0;
		my $passed = index($result, '.') < 0;
		my @results;
		foreach (@chars) {
			$num++ if ($passed);
			if ($_ eq '.') {
				$passed = 1;
				push @results, $decimal;
			} else {
				push @results, $_;
			}
			if ($count++ < $#chars && $num && $num % 3 == 0) {
				push @results, $comma;
				$num = 0;
			}
		}
		$result = join('', reverse @results) if (@results);
	}
	$result = "$result%" if ($args{'percent'});
	$result = "-$result" if ($neg);
	return $result;
}


=item C<get_a10_session_id> ( $file_path [, $item ] [, $format ] [, $country_code ] )

Gets the session ID from the load balancers.

=cut

sub get_a10_session_id {
	my $self = shift;
	return unless (ref $self);
	my $url  = 'https://10.82.75.23/services/rest/V1/?method=authenticate&username=readonly&password=readonly';
	my $page = $self->browser->get( $url );
	$page->content =~ m!<session_id>([^<]+)</session_id!;
	$self->session_id( $1 );
	return $self->session_id;
}


=item C<get_a10_hosts> ( $file_path [, $item ] [, $format ] [, $country_code ] )

Gets the session ID from the load balancers.

=cut

sub get_a10_hosts {
	my $self       = shift;
	return unless (ref $self);
	my $session_id = shift || $self->get_a10_session_id;
#	my $url        = 'https://10.82.75.23/services/rest/V1/?session_id=' . $session_id . '&method=slb.service-group.fetchStatisticsByName&name=SG-sessionservvip';
	my $url        = 'https://10.82.75.23/services/rest/V1/?session_id=' . $session_id . '&method=slb.service-group.fetchAllStatistics';
	my $page       = $self->browser->get( $url );
	my $xml        = XML::Simple->new( ForceArray => 1 );
	my $data       = $xml->XMLin( $page->content );
	$self->data( $data->{'service-groups'}->[0]->{'service-group'} );
	return $self->data;
}


=item C<get_file_path> ( $file_path [, $item ] [, $format ] [, $country_code ] )

Sets and Gets the correct file path.

=cut

sub get_file_path {
	my $self   = shift;
	return unless (ref $self);
	my $path   = shift || return;
	my $item   = shift || '';
	my $format = shift || '';
	my $code   = shift || $self->environment->code;
	my @dirs   = split(':', $self->environment->args('dir'));
	my $data   = $dirs[0] || $self->date->as_string('%Y%m%d');
	$path      = sprintf($path, $code, $data, $item, $format);
	if ($self->environment->args('top')) {
		$path =~ s!/pr/data/!/pr/data/top/!;
		$path =~ s!/active!/top!;
	}
	if (@dirs) {
		if ($path =~ /puboffers/) {
			$path =~ s!/(active|top)!/$dirs[0]!;
		} elsif ($path =~ /pubmerchants/) {
			$path =~ s!/(active|top)!/$dirs[1]!;
		}
	}
	$path = $self->check_directory( $path );
	$path = realpath( $path );
	$self->file_path( $path );
	return $path;
}


=item C<check_file> ( $file )

Returns true if a particular feature is set in a feature bitmask, otherwise false
$bitmask is optional, will default to $self->features().

Can be called statically, but $bitmask is then required.

=cut

sub check_file {
	my $self = shift;
	return unless (ref $self);
	$self->profile->start('check_file') if ($self->environment->profile);
	my $file = shift || return;
	if (-e "${file}.gz") {
		$self->print_stdout("\tData File Exists:       " . $file . ".gz\n", 2);
		return 1;
	} elsif (-e "${file}") {
		$self->print_stdout("\tData File Exists:       " . $file . "\n", 2);
		return 1;
	}
	$self->profile->stop('check_file') if ($self->environment->profile);
	return 0;
}


=item C<check_directory> ( $file )

Returns true if a particular feature is set in a feature bitmask, otherwise false
$bitmask is optional, will default to $self->features().

Can be called statically, but $bitmask is then required.

=cut

sub check_directory {
	my $self  = shift;
	return unless (ref $self);
	$self->profile->start('check_directory') if ($self->environment->profile);
	my $path  = shift || return;
	$self->print_stdout("\tGiven Path:             " . $path . "\n", 4);
	my @parts = split('/', $path);
	my $last  = pop @parts;
	$path = join('/', @parts);
	$self->print_stdout("\tPopped Path:            " . $path . "\n", 4);

	unless (-e $path) {
		$self->print_stdout("\tCreating Directory:     " . $path . "\n", 4);
		unless (mkdir($path, 0777)) {
			$self->print_stdout("\tParent Path:            " . $path . "\n", 4);
			$self->check_directory( $path );
			$self->print_stdout("\tRedo Path:              " . $path . "\n", 4);
			mkdir($path, 0777);
		}
	}
	$path = join('/', $path, $last);
	$self->print_stdout("\tFull Path:              " . $path . "\n", 4);
	$self->profile->stop('check_directory') if ($self->environment->profile);
	return $path;
}


=item C<print_log> ( [ $filename ] [, $days_old ] )

Prints the messages to the log.

=cut

sub print_log {
	my $self = shift;
	return unless (ref $self);
	my $file = shift || $self->path_to_log;
	my $days = shift || $self->conf->log_cleanup;
	$file = $self->date->as_string( $file . '%Y%m%d-%H%M%S.log' );
	$self->SUPER::print_log( $file, $days );
}    # END of print_log


=item C<print_updates> ( [ $filename ] [, $text ] )

Prints the processing update to a monitoring file.

=cut

sub print_updates {
	my $self = shift;
	return unless (ref $self);
	my $file = shift || $self->path_to_log;
	my $text = shift || 'No Updates';
	my @dirs = split(':', $self->environment->args('dir'));
	$file    = $self->get_file_path( $self->conf->path_to_log );
	$file    = $self->date->as_string( $file . 'updates_' . $dirs[0] . '_%Y%m%d.log' );
	my $logfile = $self->environment->server_root_relative( $self->date->as_string( $file ) );
	$self->print_stdout("\n\tPrint to Update File:\t[${logfile}]##\n", 4);
	system("echo \"$text\" >> $logfile ");

#	open(LOG, ">>$logfile") || $self->print_stdout( "\t\tFailure: Couldn't open file:  ${logfile}, $!\n\n" );
#		print LOG $text;
#	close(LOG);
}    # END of print_updates


=item C<cleanup_logs> ( [ $filename ] [, $days_old ] )

Remove the logs that are older than conf->log_cleanup.

=cut

sub cleanup_logs {
	my $self = shift;
	return unless (ref $self);
	my $file = shift || $self->path_to_log;
	my $days = shift || $self->conf->log_cleanup;
	$self->SUPER::cleanup_files( $file, $days );
}    # END of cleanup_logs


=item C<cleanup_files> ( [ $filename ] [, $days_to_keep ] )

Remove the logs that are older than conf->log_cleanup.

=cut

sub cleanup_files {
	my $self  = shift;
	return unless (ref $self);
	$self->profile->start('cleanup_files') if ($self->environment->profile);
	my $file  = shift || $self->get_file_path( $self->conf->path_to_feed );
	my $sets  = shift || $self->conf->file_cleanup;
	my $path  = $self->environment->server_root_relative( $file );
	$path     =~ m!(.+)/([^/]+)!;
	my @parts = split('/', $1);
	pop @parts;
	my $ldir  = join('/', @parts);
	my $list  = File::List->new( $ldir );
	$list->show_only_dirs();
	my @dirs  = @{ $list->find("") };
	my @delete;
	if (@dirs) {
		foreach my $dir (sort @dirs) {
			next unless ($dir =~ m!\d+/$!);
			push @delete, $dir;
		}
	}
	my $total = scalar(@delete);
	$self->print_stdout("\n\tPurging Files in:\t[${ldir}]\n", 1);
	$self->print_stdout("\tTotal Sets Here:\t[${total}]\n", 1);
	$self->print_stdout("\tData Sets to Keep:\t[${sets}]\n", 1);
	return unless ($total > $sets);
	$total   -= $sets;
	if (@delete) {
		foreach my $dir (@delete) {
			last unless ($total--);
			if (system('rm', '-Rf', $dir)) {
				$self->print_stdout("\t\tDir:\t\t[${total}][${dir}]:\tRemove Failed\n", 1);
			} else {
				$self->print_stdout("\t\tDir:\t\t[${total}][${dir}]:\tRemove Succeeded\n", 1);
			}
		}
	}
	$self->print_stdout("\tPurging Files Done\n\n", 1);
	$self->profile->stop('cleanup_files') if ($self->environment->profile);
}


=item C<write_build_file> ( $total_files )

Writes out the control file with data for most recent build.

=cut

sub write_build_file {
	my $self  = shift;
	return unless (ref $self);
	return unless ($self->conf->can('path_to_build_file'));
	my $total = shift || 0;
	my $date  = $self->date;
	my $o_ver = $self->version_offer;
	my $m_ver = $self->version_merchant;
	my $body  = qq!## Publisher FTP Feed Data ##
build:
    timestamp:        $date
    offer version:    $o_ver
    merchant version: $m_ver
    total_files:      $total
!;
	my $file   = $self->create_file_handle( $self->get_file_path( $self->conf->path_to_build_file, 'txt' ), 'txt' );
	my $handle = $self->io_handle;
	print $handle $body;
	$self->io_handle->close;
	return $file;
}


1;


=back

=head1 KNOWN BUGS

None

=head1 AUTHOR

Thai Nguyen <thai@shopzilla.com>

=cut
