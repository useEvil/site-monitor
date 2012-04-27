=head1 NAME

Gandolfini::Utility::UniqueID

=head1 DESCRIPTION

=cut

package Gandolfini::Utility::UniqueID;

use strict;
use warnings;
use Data::Dumper;

use base 'Exporter';
our @EXPORT_OK = qw( global_unique_id session_unique_id is_valid_global_unique_id is_valid_session_unique_id);
our @EXPORT_ALL = @EXPORT_OK;

use Sys::Hostname;
use Time::HiRes qw( gettimeofday );
use Time::Local qw( timelocal );
use Gandolfini::Utility::ConfInit qw(getColoMode getColoNum getSiloNum);

=item C<global_unique_id> ( )

The 35-digit unique ID consists of (number of digits in parens):

 unix time (10) + microseconds (6) + per-process counter (5)
    + dante # (4) + colo id (2) + silo id (2) + process # (6)

Even if the same dante, in the same silo/colo responded to a redirect in the
same microsecond using the same process, it would still have a different rd counter #.

EXAMPLE:
11570478186046500000100080101024152

1157047818      604650      00001       0008     01     01      024152
time            microsecs   counter     dante    colo   silo    processid

=cut

# this is the "per-process counter" mentioned in the =pod
our $GLOBAL_UNIQUE_ID_COUNTER;

sub global_unique_id {
    my $format = '%010d%06d%05d%04d%02d%02d%06d';

    # this is very aggressive, could just replace gettimeofday and pid
    # instead and then require a httpd restart to get a repeatable series
    # but this'll do for now.
    return sprintf($format, $main::STABLE_FOR_TESTING, (1)x6)
        if $main::STABLE_FOR_TESTING;

    # 4 digits
    my $dante_num = ((Sys::Hostname->hostname =~ /^[^\d]+(\d+)\./) ? $1 : 0) % 10000;

    # increment the RD counter, roll over at 100000 (5 digits)
    my $counter  = ++$GLOBAL_UNIQUE_ID_COUNTER % 100000;

    # from Gandolfini::Utility::ConfInit (2 digits each)
    my $colo_id = (getColoNum(getColoMode) || 0) % 100;
    my $silo_id = (getSiloNum() || 0) % 100;
    
    # make sure the pid is no more than 6 digits
    my $pid = $$ % 1000000;

    # build the complete unique ID
    my $id = sprintf($format,
        gettimeofday, # seconds (10 digits) microseconds (6 digits)
        $counter,     # per-process RD counter (5 digits)
        $dante_num,   # Dante number (4 digits)
        $colo_id,     # Colo ID (2 digits)
        $silo_id,     # Silo ID (2 digits)
        $pid);        # process ID (6 digits)

    return $id;
}

=item C<is_valid_global_unique_id> ( ID )

Check that ID is a valid global_unique_id

=cut

sub is_valid_global_unique_id {
    my $value = shift;
    return ($value && $value =~ /^\d{35}$/);
}


=item C<session_unique_id> ( )

The 18-digit session ID consists of (number of digits in parens):

 per-process counter (1) + dante # (3) + colo id (1) + silo id (1) +
    process # (5) + seconds since start of month (7 digits)

The requirements for this value are:

 - 18 digits (upstream limitations)
 - 30 days uniqueness (we can only approximate this)
 - high variablility in the last two digits (which are used to pick tests)

 EXAMPLE:
 200811241522632218

 2          008     1       1       24152       2632218
 counter    dante   colo    silo    processid   seconds since start of month

=cut

our $SESSION_UNIQUE_ID_COUNTER;
our $curr_second = 0;
our $ids_this_second = 0;

sub session_unique_id {
	# 3 digits
    my $dante_num = ((Sys::Hostname->hostname =~ /^[^\d]+(\d+)\./) ? $1 : 0) % 1000;

    # calculate the number of seconds since the beginning of the month
    my $seconds_since_month = time - timelocal(0,0,0,1, (localtime)[4,5]);
    
    # make sure we don't try to allocate more than 9 ids in the same second,
    # since the counter will wrap around and we'll get duplicate ids...
    if($seconds_since_month == $curr_second) {
    	$ids_this_second++;
    	if($ids_this_second > 9) {
    		# this should be pretty rare, log for now....
    		warn __PACKAGE__ . "sleeping 1 second, to avoid duplicating id";
    		sleep 1;
    		
    		# recur
    		return session_unique_id();
    	}
    }
    else {
    	$curr_second = $seconds_since_month;
    	$ids_this_second = 1;
    }

    # increment the counter (range 1 .. 9, NO ZEROES)
    my $counter  = ++$SESSION_UNIQUE_ID_COUNTER % 9 + 1;
    
    # make sure the pid is no more than 5 digits
    my $pid = $$ % 100000;

    # from Gandolfini::Utility::ConfInit (1 digit each)
    my $colo_id = (getColoNum(getColoMode) || 0) % 10;
    my $silo_id = (getSiloNum() || 0) % 10;
    
    # build the complete unique ID
    my $id = sprintf('%1d%03d%1d%1d%05d%07d',
        $counter,               # per-process counter (1 digit)
        $dante_num,             # Dante number (3 digits)
        $colo_id,               # Colo ID (1 digit)
        $silo_id,               # Silo ID (1 digit)
        $pid,                   # process ID (5 digits)
        $seconds_since_month);  # 7 digits
        
    return $id;
}

=item C<is_valid_session_unique_id> ( ID )

Check that ID is a valid session_unique_id

=cut

sub is_valid_session_unique_id {
    my $value = shift;
    return ($value && $value =~ /^\d{18}$/);
}



1;
__END__

=head1 AUTHOR

  Zack Hobson <zhobson@shopzilla.com>

=cut

