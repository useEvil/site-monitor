# ---------------------------------------------------------------------- #
# package Gandolfini::Date
# Date.pm
# -----------------
# $Revision: 1874 $
# $Date: 2008-01-22 08:06:06 -0800 (Tue, 22 Jan 2008) $
# ---------------------------------------------------------------------- #
# DESCRIPTION OF FILE
#	Date.pm.  Base Class to get the date in a format you can use.
# ---------------------------------------------------------------------- #
package Gandolfini::Date;

=head1 NAME

Gandolfini::Date - contains methods to get date/time fields.


=head1 SYNOPSIS

 use Gandolfini::Date;

OVERLOADED OPERATORS:

    '""'    => 'str_time',      # returns time as a string
    '0+'    => 'time_local',    # returns seconds
    '>'     => 'greater_than',
    '<'     => 'less_than',
    '>='    => 'greater_than_or_equal',
    '=='    => 'equal_equal',
    '!='    => 'bang_equal',
    'eq'    => 'equal',
    'ne'    => 'not_equal',
    '<='    => 'less_than_or_equal',
    '*'     => 'multiply',
    '/'     => 'divide',
    '-'     => 'subtract',
    '+'     => 'add'
    '-='     => 'subtract_seconds',
    '+='     => 'add_seconds'
    '<=>'    => 'numeric_compare',


CONSTRUCTORS:

  $date = Gandolfini::Date->new(  )

OBJECT METHODS:

  $date->time_local;
  $date->str_time;
  $date->language;

  $date->str2time( "4 Jun|6 1998 21:09:55" );
  $date->str2time( 4 'Jun'|6,1998,'21:09:55' );
  $date->time2str( "%a %b %e %T %Y", $time );

  $date->last_year;
  $date->last_month;
  $date->last_month_lday;
  $date->last_month_year;

  $date->next_year;
  $date->next_month;
  $date->next_month_lday;
  $date->next_month_year;

  $date->qtr_1;
  $date->qtr_2;
  $date->qtr_3;
  $date->qtr_1_lday;
  $date->qtr_2_lday;
  $date->qtr_3_lday;

  $date->yesterday;
  $date->yesterday_month;
  $date->yesterday_month_lday;
  $date->yesterday_year;

  $date->tomorrow;
  $date->tomorrow_month;
  $date->tomorrow_month_lday;
  $date->tomorrow_year;

  $date->week_begin;
  $date->week_begin_month;
  $date->week_begin_month_lday;
  $date->week_begin_year;

  $date->week_end;
  $date->week_end_month;
  $date->week_end_month_lday;
  $date->week_end_year;

  $date->last_week_begin;
  $date->last_week_begin_month;
  $date->last_week_begin_month_lday;
  $date->last_week_begin_year;

  $date->last_week_end;
  $date->last_week_end_month;
  $date->last_week_end_month_lday;
  $date->last_week_end_year;

  $date->next_week_begin;
  $date->next_week_begin_month;
  $date->next_week_begin_month_lday;
  $date->next_week_begin_year;

  $date->next_week_end;
  $date->next_week_end_month;
  $date->next_week_end_month_lday;
  $date->next_week_end_year;

  $date->days_by_week;
  $date->days_by_month;

  $date->month_full;
  $date->month_full2abrv;

  $date->is_leap_year;

  $date->last_day;
  $date->last_days;

  $date->week_days_list;
  $date->week_days_sh_list;
  $date->week_days_full_list;

  $date->week_days;
  $date->week_days_sh;
  $date->week_days_full;

  $date->months_list;
  $date->months_full_list;

  $date->months;
  $date->months_pad;
  $date->months_full;
  $date->months_full_pad;
  $date->months_abrv;

  $date->int_months;
  $date->int_months_full;

  $date->hours24;
  $date->hours;
  $date->minutes;


=head1 REQUIRES

 POSIX
 Time::Local

=head1 EXPORTS

Nothing


=head1 DESCRIPTION

OO Date Module for dealing with dates.  Its major advantage is that 
it treats dates as an object, for which you can call methods against.  
(ie. 'month', 'day', 'year').

If called in string context:

print "The date is:  " . $date . "\n";

$date will return a date string defined by the format that the object 
was created with, ie.  '%B %e %Y %I:%M%p'.

If called in a calculation:

$seconds = $date + 1;

$date will return the date in seconds.


=head1 METHODS

=over 4

=cut

use overload (	fallback	=> 1,
				'""'		=> 'str_time',		# returns date as a string
				'0+'		=> 'time_local',	# returns date in seconds
				'>'			=> 'greater_than',
				'<'			=> 'less_than',
				'>='		=> 'greater_than_or_equal',
				'=='		=> 'equal_equal',
				'!='		=> 'bang_equal',
				'eq'		=> 'equal',
				'ne'		=> 'not_equal',
				'<='		=> 'less_than_or_equal',
				'*'			=> 'multiply',
				'/'			=> 'divide',
				'-'			=> 'subtract',
				'+'			=> 'add',
				'-='		=> 'subtract_seconds',
				'+='		=> 'add_seconds',
#				'--'		=> 'subtract_subtract',
#				'++'		=> 'add_add',
				'<=>'		=> 'numeric_compare'
			 );
use vars qw(%ampm);
use Carp;
use strict;
use Data::Dumper;
use Time::Local;
use POSIX qw(strftime);


BEGIN {
	%ampm	= (
				am => '00',
				pm => '12'
			);
}


=item C<new> ( $time [, $type ] )

=item C<new> ( [, $time ] [, $type ] )

=item C<new> ( [, $time ] [, $type ] )

 Calling new() without params will default to:
    time in systime, secs
    language is in English

A constructor that will return a Gandolfini::Date 
object for which you can call these methods:

    sec         => seconds
    min         => minutes
    hour        => hour
    mday        => day of the month
    mon         => month # (0 .. 11)
    dd          => day (2-digit)
    mm          => month (2-digit)
    yy          => year (2-digit)
    wday        => day of the week # (0 .. 6)
    yday        => day of the year
    isdst       => daylight savings time
    wkday       => week day abrv
    day         => day of the month padded zeros
    hhmmss      => time (00:00:00) 24 hr
    hhmm        => time (00:00) 24 hr
    year        => year (4-digit)
    month       => month string (abrv)
    month_full  => month string (full name)
    mon_number  => month # (1 .. 12)
    mon_padd    => month # (01 .. 12) padded zeros
    wkday_full  => day of the week (full name)
    wkday_short => day of the week (2 char)
    am_pm       => AM or PM
    am          => true if AM
    pm          => true if PM

You can pass the Languages:  English, German, 
Norwegian, Italian, or Austrian.

You must pass it $time in systime or seconds.  $type is optional, 
and can be any of the following.  This will determine how $date->str_time 
is returned.

 Types can be defined as:
    '%B %e %Y %I:%M%p' => 'May  4 1998 12:00AM'
    '%D'               => '05/31/98'
    '%Y.%m.%e'         => '1998.05.31'
    '%e/%m/%Y'         => '31/05/1998'
    '%e.%m.%Y'         => '31.05.1998'
    '%e-%m-%Y'         => '31-05-1998'
    '%e %B %Y'         => '31 May 1998'
    '%B %e, %Y'        => 'May 31, 1998'
    '%I:%M:%S'         => '00:00:00'
    '%B %e %Y %T'      => 'May 31 1998 12:00:00'
    '%m-%e-%Y'         => '05-31-1998'
    '%Y/%m/%e'         => '1998/05/31'
    '%Y%m%e'           => '19980531'

 Types of formats:
    %%    PERCENT
    %a    day of the week abbr
    %A    day of the week
    %b    month abbr
    %B    month
    %c    ctime format: Sat Nov 19 21:05:57 1994
    %d    numeric day of the month
    %e    DD
    %D    MM/DD/YY
    %h    month abbr
    %H    hour, 24 hour clock, leading 0's)
    %I    hour, 12 hour clock, leading 0's)
    %j    day of the year
    %k    hour
    %l    hour, 12 hour clock
    %m    month number, starting with 1
    %M    minute, leading 0's
    %n    NEWLINE
    %o    ornate day of month -- "1st", "2nd", "25th", etc.
    %p    AM or PM
    %r    time format: 09:05:57 PM
    %R    time format: 21:05
    %s    seconds since the Epoch, UCT
    %S    seconds, leading 0's
    %t    TAB
    %T    time format: 21:05:57
    %U    week number, Sunday as first day of week
    %w    day of the week, numerically, Sunday == 0
    %W    week number, Monday as first day of week
    %x    date format: 11/19/94
    %X    time format: 21:05:57
    %y    year (2 digits)
    %Y    year (4 digits)
    %Z    timezone in ascii. eg: PST
    %z    timezone in format -/+0000

=cut

sub new {
	my $self	= shift;
	my $class	= ref($self)	|| $self;
	my $time	= shift			|| time;
	my $type	= shift			|| '%d %b %Y %T';
	
	$self = {
				_time_local	=> $time,
				_format		=> $type
			};
	
	bless $self, $class;
} # END of new


=item C<new_by_string> ( $date_string [, $format ] )

Will return date_format.

=cut

sub new_by_string {
	my $self		= shift;
	my $class		= ref($self) || $self;
	my $time		= shift;
	my $type		= shift || '%d %b %Y %T';
	my $localtime	= $class->str2time( $time ) || time;
	return $self->new( $localtime, $type );
} # END of new_by_string


=item C<date_format> (  )

Will return date_format. 

=cut

sub date_format {
	my $self	= shift;
	my $format	= shift;
	$self->{'_format'} = $format if ($format);
	return $self->{'_format'};
} # END of date_format


=item C<time_local> (  )

Will return time_local, in system time, or seconds.  If you pass the time 
in seconds, then it will update with the new value.

=cut

sub time_local {
	my $self	= shift;
	my $time	= shift;
	$self->{'_time_local'} = $time if ($time);
	return $self->{'_time_local'};
} # END of time_local


=item C<str_time> ( [ $format ] )

=item C<as_string> ( [ $format ] )

Will return the date as a string, according to the date format.

=cut

sub str_time	{ $_[0]->time2str( ($_[1] || $_[0]->date_format), $_[0]->time_local ) }
sub as_string	{ $_[0]->str_time( $_[1] ) }


=item C<str2time> ( "06/30/1998" )

=item C<str2time> ( "Jun|06 30, 1998" )

=item C<str2time> ( "Jun|06 30 1998 11:09:55PM" )

=item C<str2time> ( "30 Jun|6 1998 21:09:55" )

=item C<str2time> ( 30,Jun|6,1998,21:09:55 )

A constructor that will return timelocal, or seconds according 
to the type and time string passed.  $zone, if given, specifies 
the timezone to assume when parsing if the date string does not 
specify a timezome. 

=cut

sub str2time {
	my $self	= shift;
	my @vals	= @_;
	return undef unless ($vals[0]);
	unless ($vals[1]) {
		## iso8601: 2006-07-28T08:06:17 ##
		if ($vals[0] =~ /(\d{4})-(\d{1,2})-(\d{1,2})T([\d:]+)([AM|PM]*)/) {
			@vals = ($3, $2, $1, $4, $5);
		## 30 Jun|06 1998 11:09:55PM ##
		} elsif ($vals[0] =~ /(\d{1,2})\s+(\d{1,2}|\w+)\s+(\d{4})\s+([\d:]+)([AM|PM]*)/) {
			@vals = ($1, $2, $3, $4, $5);
		## 30 Jun|06 1998 ##
		} elsif ($vals[0] =~ /(\d{1,2})\s+(\d{1,2}|\w+)\s+(\d{4})(.*)/) {
			@vals = ($1, $2, $3, $4);
		## 06/30/1998 06-30-1998 06.30.1998 ##
		} elsif ($vals[0] =~ m!(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})(.*)!) {
			@vals = ($2, $1, $3, $4);
		## 1998-06-30 1998/06/30 1998.06.30 ##
		} elsif ($vals[0] =~ m!(\d{4})[-/.](\d{1,2})[-/.](\d{2})(.*)!) {
			@vals = ($3, $2, $1, $4);
		## Jun|06 30, 1998 11:09:55PM ##
		## Jun|06 30 1998 11:09:55PM ##
		} elsif ($vals[0] =~ /(\w+|\d{1,2})\s+(\d{1,2})[,]?\s+(\d{4})\s+([\d:]+)([AM|PM]*)/) {
			@vals = ($2, $1, $3, $4, $5);
		## Jun|06 30, 1998 ##
		## Jun|06 30 1998 ##
		} elsif ($vals[0] =~ /(\w+|\d{1,2})\s+(\d{1,2})[,]?\s+(\d{4})(.*)/) {
			@vals = ($2, $1, $3, $4);
		} else {
			return time;
		}
	}
	## take care of months here ##
	my (%months, $mon);
	if ($vals[1] =~ /\D/) {
		if (length $vals[1] > 3) {
			%months	= reverse %{ $self->months_full };
			$mon	= $months{ $vals[1] } - 1;
		} else {
			%months	= reverse %{ $self->months };
			$mon	= $months{ $vals[1] } - 1;
		}
	} else {
		$mon	= $vals[1] - 1;
	}
	## take care of time here ##
	unless ($vals[4]) {
		$vals[3] =~ /([\d:]+)([AM|PM]*)/;
		$vals[3] = $1;
		$vals[4] = $2;
	}
	my ($hour, $min, $sec)	= ( '00', '00', '00' );
		($hour, $min, $sec)	= split(/:/, $vals[3]);
	if ($vals[4] eq 'PM') {
		$hour	+= 12 unless ($hour == 12);
		$hour	= '00' if ($hour == 24);
		$sec	= '00';
	} elsif ($vals[4] eq 'AM') {
		$hour	= '00' if ($hour == 12);
		$sec	= '00';
	}
	## timelocal( $sec, $min, $hour, $mday, $mon, $year ) ##
	return timelocal( $sec, $min, $hour, $vals[0], $mon, $vals[2] );
} # END of str2time


=item C<time2str> ( "%a %b %e %T %Y", $time )

A constructor that will return a string according to the type and 
system time, or seconds passed.

=cut

sub time2str  {
	my $self	= shift;
	my $type	= shift;
	my $time	= shift || (ref($self) ? $self->time_local : time);
	# strftime(fmt, sec, min, hour, mday, mon, year, wday = -1, yday = -1, isdst = -1)
	#                0    1    2     3     4    5     6     7     8
	#               sec, min, hour, mday, mon, year, wday, yday, isdst
	return strftime( $type, localtime( $time ) );
} # END of time2str


sub sec			{ $_[0]->time2str( '%S' ) }

sub min			{ $_[0]->time2str( '%M' ) }

sub hour		{ $_[0]->time2str( '%H' ) }

sub mday		{ return (localtime( $_[0]->time_local ))[3] }

sub mon			{ return (localtime( $_[0]->time_local ))[4] }

sub dd			{ $_[0]->mday }

sub mm			{ $_[0]->mon_padd }

sub yy			{ $_[0]->time2str( '%y' ) }

sub wday		{ $_[0]->time2str( '%w' ) }

sub yday		{ return (localtime( $_[0]->time_local ))[7] }

sub isdst		{ return (localtime( $_[0]->time_local ))[8] }

sub wkday		{ $_[0]->time2str( '%a' ) }

sub day			{ $_[0]->time2str( '%d' ) }

sub hhmmss		{ $_[0]->time2str( '%T' ) }

sub hhmm		{ $_[0]->time2str( '%R' ) }

sub year		{ $_[0]->time2str( '%Y' ) }

sub month		{ $_[0]->time2str( '%b' ) }

sub month_full	{ $_[0]->time2str( '%B' ) }

sub mon_number	{ $_[0]->mon + 1 }

sub mon_padd	{ $_[0]->time2str( '%m' ) }

sub wkday_full	{ $_[0]->time2str( '%A' ) }

sub wkday_short	{ substr($_[0]->wkday,0,2) }

sub am_pm		{ $_[0]->time2str( '%p' ) }

sub am			{ ($_[0]->am_pm eq 'AM' ? 1 : undef) }

sub pm			{ ($_[0]->am_pm eq 'PM' ? 1 : undef) }

#### depricate, please ####
sub mon_num		{ $_[0]->mon_number }


=item C<today> (  )

Returns true if the date object is the same as the current date.

=cut

sub today {
	my $self	= shift;
	my $today	= $self->new;
	return (
				(($today->mday == $self->mday) &&
				($today->month eq $self->month) &&
				($today->year == $self->year))
			?	1
			:	0
	);
} # END of today


=item C<last_year> (  )

Returns the 4-digit year of last year.

=item C<last_month> (  )

Returns the integer month (0 .. 11) for last month.

=item C<last_month_lday> (  )

Returns the last day for last month.

=item C<last_month_year> (  )

Returns the 4-digit year that last month falls in.

=cut

sub last_year		{ $_[0]->year - 1 }
sub last_month		{ $_[0]->mon == 0 ? 11 : $_[0]->mon - 1 }
sub last_month_lday	{ $_[0]->last_day( $_[0]->last_month, $_[0]->last_month_year ) }
sub last_month_year	{ $_[0]->last_month > $_[0]->mon ? $_[0]->last_year : $_[0]->year }


=item C<next_year> (  )

Returns the 4-digit year of next year.

=item C<next_month> (  )

Returns the integer month (0 .. 11) for next month.

=item C<next_month_lday> (  )

Returns the last day for next month.

=item C<next_month_year> (  )

Returns the 4-digit year that next month falls in.

=cut

sub next_year		{ $_[0]->year + 1 }
sub next_month		{ $_[0]->mon == 11 ? 0 : $_[0]->mon + 1 }
sub next_month_lday { $_[0]->last_day( $_[0]->next_month, $_[0]->next_month_year ) }
sub next_month_year { $_[0]->next_month == 0 ? $_[0]->year + 1 : $_[0]->year }


=item C<qtr_1> (  )

=item C<qtr_2> (  )

=item C<qtr_3> (  )

Returns the integer month (0 .. 11) for next month.  Not finished.  
Might not work correctly.

=item C<qtr_1_lday> (  )

=item C<qtr_2_lday> (  )

=item C<qtr_3_lday> (  )

Returns the last day for that quarter month.  Might not work correctly.

=cut

sub qtr_1		{ $_[0]->mon }
sub qtr_2		{ $_[0]->next_month }
sub qtr_3		{ $_[0]->next_month == 11 ? 0 : ($_[0]->next_month == 0 ? 1 : $_[0]->next_month + 1) }
sub qtr_1_lday	{ $_[0]->last_day( $_[0]->qtr_1 ) }
sub qtr_2_lday	{ $_[0]->last_day( $_[0]->qtr_2 ) }
sub qtr_3_lday	{ $_[0]->last_day( $_[0]->qtr_3 ) }


=item C<yesterday> (  )

Returns the day value for yesterday.

=item C<yesterday_month> (  )

Returns the integer month (0 .. 11) for the month that yesterday falls in.

=item C<yesterday_month_lday> (  )

Returns the last day for the month that yesterday falls in.

=item C<yesterday_year> (  )

Returns the 4-digit year that yesterday falls in.

=cut

sub yesterday				{ $_[0]->mday == 1 ? $_[0]->last_day( $_[0]->mon ) : $_[0]->mday - 1 }
sub yesterday_month			{ $_[0]->yesterday == $_[0]->last_day( $_[0]->mon ) ? $_[0]->last_month : $_[0]->mon }
sub yesterday_month_lday	{ $_[0]->last_day( $_[0]->yesterday_month, $_[0]->yesterday_year ) }
sub yesterday_year			{ ($_[0]->yesterday_month == 11) && ($_[0]->mon != 11) ? $_[0]->last_year : $_[0]->year }

=item C<tomorrow> (  )

Returns the day value for tomorrow.

=item C<tomorrow_month> (  )

Returns the integer month (0 .. 11) for the month that tomorrow falls in.

=item C<tomorrow_month_lday> (  )

Returns the last day for the month that tomorrow falls in.

=item C<week_begin_year> (  )

Returns the 4-digit year that tomorrow falls in.

=cut

sub tomorrow			{ $_[0]->mday == $_[0]->last_day ? 1 : $_[0]->mday + 1 }
sub tomorrow_month		{ $_[0]->tomorrow == 1 ? $_[0]->next_month : $_[0]->mon }
sub tomorrow_month_lday	{ $_[0]->last_day( $_[0]->tomorrow_month, $_[0]->tomorrow_year ) }
sub tomorrow_year		{ ($_[0]->tomorrow_month == 0) && ($_[0]->mon != 0) ? $_[0]->next_year : $_[0]->year }


=item C<week_begin> (  )

Returns the day value of the first day of the week, based on a Sun thru Sat week.

=item C<week_begin_month> (  )

Returns the integer month (0 .. 11) for the month that the week began.

=item C<week_begin_month_lday> (  )

Returns the last day for the month that the week began.

=item C<week_begin_year> (  )

Returns the 4-digit year that the week began.

=cut

sub week_begin				{ $_[0]->_beg <= 0 ? $_[0]->last_month_lday + $_[0]->_beg : $_[0]->_beg }
sub week_begin_month		{ $_[0]->week_begin > $_[0]->mday ? $_[0]->last_month : $_[0]->mon }
sub week_begin_month_lday	{ $_[0]->last_day( $_[0]->week_begin_month, $_[0]->week_begin_year ) }
sub week_begin_year			{ $_[0]->week_begin_month > $_[0]->mon ? $_[0]->last_year : $_[0]->year }


=item C<week_end> (  )

Returns the day value of the last day of the week, based on a Sun thru Sat week.

=cut

sub week_end {
	if ($_[0]->week_end_month == $_[0]->mon) {
		if ($_[0]->_end > $_[0]->last_month_lday) {
			return $_[0]->_end - $_[0]->last_month_lday;
		}
	} elsif ($_[0]->week_end_month == $_[0]->next_month) {
		if ($_[0]->_end > $_[0]->last_day) {
			return $_[0]->_end - $_[0]->last_day;
		}
	}
	return $_[0]->_end;
} # END of week_end


=item C<week_end_month> (  )

Returns the integer month (0 .. 11) for the month that the week ended.

=cut

sub week_end_month {
	if ($_[0]->week_begin > $_[0]->mday) {
		if ($_[0]->week_begin_month == $_[0]->last_month) {
			return $_[0]->mon;
		} elsif ($_[0]->week_begin_month == $_[0]->mon) {
			return $_[0]->next_month;
		}
	} elsif ($_[0]->_end > $_[0]->last_day) {
		return $_[0]->next_month;
	} else {
		return $_[0]->mon;
	}
} # END of week_end_month


=item C<week_end_month_lday> (  )

Returns the last day for the month that the week ended.

=item C<week_end_year> (  )

Returns the 4-digit year that the week ended.

=cut

sub week_end_month_lday	{ $_[0]->last_day( $_[0]->week_end_month, $_[0]->week_end_year ) }
sub week_end_year		{ $_[0]->week_end_month < $_[0]->mon ? $_[0]->next_year : $_[0]->year }


=item C<last_week_begin> (  )

Returns the day value of the first day of last week, based on a Sun thru Sat week.

=item C<last_week_begin_month> (  )

Returns the integer month (0 .. 11) for the month that last week began.

=item C<last_week_begin_month_lday> (  )

Returns the last day for the month that last week began.

=item C<last_week_begin_year> (  )

Returns the 4-digit year that last week began.

=cut

sub last_week_begin				{ $_[0]->week_begin - 7 <= 0 ? $_[0]->last_month_lday + $_[0]->week_begin - 7 : $_[0]->week_begin - 7 }
sub last_week_begin_month		{ $_[0]->last_week_begin > $_[0]->mday ? $_[0]->last_month : $_[0]->mon }
sub last_week_begin_month_lday	{ $_[0]->last_day( $_[0]->last_week_begin_month, $_[0]->last_week_begin_year ) }
sub last_week_begin_year		{ $_[0]->last_week_begin_month > $_[0]->mon ? $_[0]->last_year : $_[0]->year }


=item C<last_week_end> (  )

Returns the day value of the last day of last week, based on a Sun thru Sat week.

=item C<last_week_end_month> (  )

Returns the integer month (0 .. 11) for the month that last week ended.

=item C<last_week_end_month_lday> (  )

Returns the last day for the month that last week ended.

=item C<last_week_end_year> (  )

Returns the 4-digit year that last week ended.

=cut

sub last_week_end				{ $_[0]->week_begin - 1 <= 0 ? $_[0]->last_month_lday + $_[0]->week_begin - 1 : $_[0]->week_begin - 1 }
sub last_week_end_month			{ $_[0]->last_week_end > $_[0]->mday ? $_[0]->last_month : $_[0]->mon }
sub last_week_end_month_lday	{ $_[0]->last_day( $_[0]->last_week_end_month, $_[0]->last_week_end_year ) }
sub last_week_end_year			{ $_[0]->last_week_end_month > $_[0]->mon ? $_[0]->last_year : $_[0]->year }


=item C<next_week_begin> (  )

Returns the day value of the first day of next week, based on a Sun thru Sat week.

=item C<next_week_begin_month> (  )

Returns the integer month (0 .. 11) for the month that next week begins.

=item C<next_week_begin_month_lday> (  )

Returns the last day for the month that next week begins.

=item C<next_week_begin_year> (  )

Returns the 4-digit year that next week begins.

=cut

sub next_week_begin				{ $_[0]->week_end + 1 }
sub next_week_begin_month		{ $_[0]->next_week_begin < $_[0]->mday ? $_[0]->next_month : $_[0]->mon }
sub next_week_begin_month_lday	{ $_[0]->last_day( $_[0]->next_week_begin_month, $_[0]->next_week_begin_year ) }
sub next_week_begin_year		{ $_[0]->next_week_begin_month < $_[0]->mon ? $_[0]->last_year : $_[0]->year }


=item C<next_week_end> (  )

Returns the day value of the last day of next week, based on a Sun thru Sat week.

=item C<next_week_end_month> (  )

Returns the integer month (0 .. 11) for the month that next week ended.

=item C<next_week_end_month_lday> (  )

Returns the last day for the month that next week ended.

=item C<next_week_end_year> (  )

Returns the 4-digit year that next week ended.

=cut

sub next_week_end				{ $_[0]->next_week_begin + 6 > $_[0]->last_day ? $_[0]->next_week_begin + 6 - $_[0]->next_month_lday : $_[0]->next_week_begin + 6 }
sub next_week_end_month			{ $_[0]->next_week_end < $_[0]->next_week_begin ? $_[0]->next_month : $_[0]->mon }
sub next_week_end_month_lday	{ $_[0]->last_day( $_[0]->next_week_end_month, $_[0]->next_week_end_year ) }
sub next_week_end_year			{ $_[0]->week_end_month < $_[0]->mon ? $_[0]->next_year : $_[0]->year }


=item C<is_leap_year> ( [ $year ] )

Returns true if the year is a leap year.  If called statically, then you 
must pass the $year.  $year is a 4 digit year.

=cut

sub is_leap_year {
	my $self = shift;
	my $year = shift;
	if (ref $self) {
		$year = $self->year unless (defined $year);
	}
	return undef unless (defined $year);
	return 0 if $year % 4;
	return 1 if $year % 100;
	return 0 if $year % 400;
	return 1;
} # END of is_leap_year


=item C<days_by_week> ( $show )

Returns an array ref of the week with date objects as the elements.  
It will put undef place holders for days of last or next month.  
If you pass $show, then it will show the days for the end of last month 
and the beginning of next month.

=cut

sub days_by_week {
	my $self	= shift;
	my $class	= ref($self) || return undef;
	my $show	= shift;
	my $start	= $self->week_begin;
	my $end		= $self->week_end;
	my $wdays	= [ ];

	if (($start > $end) && ($self->week_begin_month != $self->mon)) {
		foreach ($start .. $self->last_month_lday) {
			if ($show) {
				my $date = $self->new($self->str2time($_ . ' ' . $self->int_months->{ $self->last_month } . ' ' . $self->last_month_year . ' 00:00:00') );
				push(@$wdays, $date);	# push the date
			} else {
				push(@$wdays, undef);	# push undef into the first empty slots
			}
		}
		foreach (1 .. $end) {
			my $date = $self->new($self->str2time($_ . ' ' . $self->month . ' ' . $self->year . ' 00:00:00') );
			push(@$wdays, $date);		# push the date
		}
	} elsif ($start > $end) {
		foreach ($start .. $self->last_day) {
			my $date = $self->new($self->str2time($_ . ' ' . $self->month . ' ' . $self->year . ' 00:00:00') );
			push(@$wdays, $date);		# push the date
		}
		foreach (1 .. $end) {
			if ($show) {
				my $date = $self->new($self->str2time($_ . ' ' . $self->int_months->{ $self->next_month } . ' ' . $self->next_month_year . ' 00:00:00') );
				push(@$wdays, $date);	# push the date
			} else {
				push(@$wdays, undef);	# push undef into the first empty slots
			}
		}
	} else {
		foreach ($start .. $end) {
			my $date = $self->new($self->str2time($_ . ' ' . $self->month . ' ' . $self->year . ' 00:00:00') );
			push(@$wdays, $date);		# push the date
		}
	}

	return $wdays;
} # END of days_by_week


=item C<days_by_month> (  )

Returns an array ref of weekday array refs with date objects as the elements.  
It will put undef place holders for days of last or next month.  
If you pass $show, then it will show the days for the end of last month 
and the beginning of next month.

=cut

sub days_by_month {
	my $self	= shift;
	my $class	= ref($self) || return undef;
	my $show	= shift;

	my $days	= [ ];
	my $wdays	= [ ];
	my $count	= -1;

	if ($self->week_begin > 1) {
		foreach ($self->week_begin .. $self->last_day($self->week_begin_month, $self->week_begin_year)) {
			if ($show) {
				my $date = $self->new($self->str2time($_ . ' ' . $self->int_months->{ $self->last_month } . ' ' . $self->last_month_year . ' 00:00:00') );
				push(@$wdays, $date);	# push the date
			} else {
				push(@$wdays, undef);	# push undef into the first empty slots
			}
			$count++;
		}
	}

	foreach (1 .. $self->last_day) {
		my $date = $self->new($self->str2time($_ . ' ' . $self->month . ' ' . $self->year . ' 00:00:00') );
		if ($count == 6) {
			push(@$days, $wdays);		# push the weekdays for each week
			$wdays = [ ];				# re-initialize week array
			$count = 0;					# re-initialize weekdays count
			push(@$wdays, $date);		# push the date because it starts again
		} else {
			push(@$wdays, $date);		# push the date
			$count++;
		}
	}
	if (@$wdays < 7) {
		my $end = 7 - @$wdays;
		foreach (1 .. $end) {
			if ($show) {
				my $date = $self->new($self->str2time($_ . ' ' . $self->int_months->{ $self->next_month } . ' ' . $self->next_month_year . ' 00:00:00') );
				push(@$wdays, $date);	# push the date
			} else {
				push(@$wdays, undef);	# push undef into the first empty slots
			}
		}
	}
	push(@$days, $wdays);

	return $days;
} # END of days_by_month


=item C<last_day> ( [ $mon ] [, $year ] )

Returns the last day of the of the month and year passed.  If nothing is passed 
then it uses the objects month and year.  Month is the integer month 0 .. 11, and 
year is the 4 digit year.  If called statically, you must pass $mon and $year.

=cut

sub last_day {
	my $self	= shift;
	my $mon		= shift;
	my $year	= shift;

	if (ref $self) {
		$mon	= $self->mon unless (defined $mon);
		$year	= $self->year unless (defined $year);
	}

	return undef unless (defined($mon) && defined($year));
	return $self->last_days->{ $mon } unless ($mon == 1);
	return 28 unless $self->is_leap_year( $year );
	return 29;
} # END of last_day


=item C<last_days> (  )

Returns a hash ref of the last day for each month.  The keys are 
the integer months (0 .. 11). *This method might be misleading, as it's not leap year aware*

=cut

sub last_days { return { 0 => '31', 1 => '28', 2 => '31', 3 => '30', 4 => '31', 5 => '30', 6 => '31', 7 => '31', 8 => '30', 9 => '31', 10 => '30', 11 => '31' } }


=item C<week_days_list> (  )

Returns an array ref of abbreviated weekdays.

=cut

sub week_days_list { return [ map { substr($_,0,3) } @{ $_[0]->week_days_full_list } ] }


=item C<week_days_sh_list> (  )

Returns an array ref of abbreviated (2 char) weekdays.

=cut

sub week_days_sh_list { return [ map { substr($_,0,2) } @{ $_[0]->week_days_full_list } ] }


=item C<week_days_full_list> (  )

Returns an array ref of weekdays.

=cut

sub week_days_full_list {
	return [ qw(Sunday Monday Tuesday Wednesday Thursday Friday Saturday) ];
} # END of week_days_full_list


=item C<week_days> (  )

Returns a hash ref of abbreviated weekdays.  With the keys being the wday (0 .. 6).

=item C<week_days_sh> (  )

Returns a hash ref of abbreviated (2 char) weekdays.  With the keys being the wday (0 .. 6).

=item C<week_days_full> (  )

Returns a hash ref of weekdays.  With the keys being the wday (0 .. 6).

=cut

sub week_days			{ return { map { $_ => $_[0]->week_days_list->[$_] }		(0 .. $#{ $_[0]->week_days_list } ) } }
sub week_days_sh		{ return { map { $_ => $_[0]->week_days_sh_list->[$_] }		(0 .. $#{ $_[0]->week_days_sh_list } ) } }
sub week_days_full		{ return { map { $_ => $_[0]->week_days_full_list->[$_] }	(0 .. $#{ $_[0]->week_days_full_list } ) } }


=item C<months_list> (  )

Returns an array ref of abbreviated months.

=cut

sub months_list { return [ map { substr($_,0,3) } @{ $_[0]->months_full_list } ] }


=item C<months_full_list> (  )

Returns an array ref of months.

=cut

sub months_full_list {
	return [ qw(January February March April May June July August September October November December) ];
} # END of months_full_list


=item C<months> (  )

Returns a hash ref of abbreviated months.  With the keys being the true month 
value (1 .. 12).

=item C<months_pad> (  )

Returns a hash ref of abbreviated months.  With the keys being the true month 
value (01 .. 12).

=item C<months_full> (  )

Returns a hash ref of full month names.  With the keys being the true month 
value (1 .. 12).

=item C<months_full_pad> (  )

Returns a hash ref of full month names.  With the keys being the true month 
value (01 .. 12).

=item C<months_abrv> (  )

Returns a hash ref of abbreviated months.  With the keys being the full month name.

=cut

sub months				{ return { map { $_ => $_[0]->months_list->[$_ - 1] }							(1 .. @{ $_[0]->months_list }) } }
sub months_pad			{ return { map { sprintf("%02d", $_) => $_[0]->months_list->[$_ - 1] }			(1 .. @{ $_[0]->months_list }) } }
sub months_full			{ return { map { $_ => $_[0]->months_full_list->[$_ - 1] }						(1 .. @{ $_[0]->months_full_list }) } }
sub months_full_pad		{ return { map { sprintf("%02d", $_) => $_[0]->months_full_list->[$_ - 1] }		(1 .. @{ $_[0]->months_full_list }) } }
sub months_abrv			{ return { map { $_[0]->months_full_list->[$_] => $_[0]->months_list->[$_] }	(0 .. 11) } }


=item C<int_months> (  )

Returns a hash ref of abbreviated months.  With the keys being the integer month 
value (0 .. 12).

=item C<int_months_full> (  )

Returns a hash ref of full month names.  With the keys being the integer month 
value (0 .. 12).

=cut

sub int_months		{ return { map { $_ => $_[0]->months_list->[$_] }			(0 .. $#{ $_[0]->months_list } ) } }
sub int_months_full	{ return { map { $_ => $_[0]->months_full_list->[$_] }		(0 .. $#{ $_[0]->months_full_list } ) } }


=begin comment

_start_qtr()
 Not done yet.

_int_mon()
 Returns a hash ref of integer months to true months (prepended with zeros)

_beg()
 Returns the value of mday minus wday.

_end()
 Returns the value of week_begin() plus 6.

=end comment

=cut

sub _start_qtr		{ return { 0 => 0, 1 => 0, 2 => 0, 3 => 3, 4 => 3, 5 => 3, 6 => 6, 7 => 6, 8 => 6, 9 => 9, 10 => 9, 11 => 9 } }
sub _int_mon		{ return { 0 => '01', 1 => '02', 2 => '03', 3 => '04', 4 => '05', 5 => '06', 6 => '07', 7 => '08', 8 => '09', 9 => '10', 10 => '11', 11 => '12' } }
sub _beg			{ return $_[0]->mday - $_[0]->wday }
sub _end			{ return $_[0]->week_begin + 6 }


=item C<hours24> (  )

Returns an array ref of hours in 24hr time.

=item C<hours> (  )

Returns an array ref of hours in 12hr time.  Padded with zeros.

=item C<minutes> (  )

Returns an array ref of minutes (0 .. 60).  Padded with zeros.

=cut

sub hours24	{ return [ '00','01','02','03','04','05','06','07','08','09', (10 .. 23) ] }
sub hours	{ return [ '01','02','03','04','05','06','07','08','09','10','11','12' ] }
sub minutes	{ return [ '00','01','02','03','04','05','06','07','08','09', (10 .. 59) ] }


=item C<day2sec> ( $day )

Returns the number of seconds for the amount of days.

=item C<hour2sec> ( $hour )

Returns the number of seconds for the amount of hours.

=item C<min2sec> ( $min )

Returns the number of seconds for the amount of minutes.

=item C<sec2day> ( $sec )

Returns the number of days for the amount of seconds.

=item C<sec2hour> ( $sec )

Returns the number of hours for the amount of seconds.

=item C<sec2min> ( $sec )

Returns the number of minutes for the amount of seconds.

=cut

sub day2sec {
	my $self	= shift;
	my $day		= shift;
	return $day * 86400;
} # END of day2sec


sub hour2sec {
	my $self	= shift;
	my $hour	= shift;
	return $hour * 3600;
} # END of hour2sec


sub min2sec {
	my $self	= shift;
	my $min		= shift;
	return $min * 60;
} # END of min2sec


sub sec2day {
	my $self	= shift;
	my $sec		= shift;
	return $sec / 86400;
} # END of sec2day


sub sec2hour {
	my $self	= shift;
	my $sec	= shift;
	return $sec / 3600;
} # END of sec2hour


sub sec2min {
	my $self	= shift;
	my $sec		= shift;
	return $sec / 60;
} # END of sec2min


########################
### OVERLOAD METHODS ###
########################


sub add {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= shift;
	my $value	= $self->time_local;
	my $sum		= $value + $arg;
	return $sum;
} # END of add


sub subtract {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= 0+(shift());
	my $rev		= shift;
	my $value	= $self->time_local;
	my $diff	= ($rev) ? $arg - $value : $value - $arg;
	return $diff;
} # END of subtract


sub add_seconds {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= shift;
	my $value	= $self->time_local;
	my $sum		= $value + $arg;
	return $self->new( $sum, $self->date_format );
} # END of add_seconds


sub subtract_seconds {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= 0+(shift());
	my $rev		= shift;
	my $value	= $self->time_local;
	my $diff	= ($rev) ? $arg - $value : $value - $arg;
	return $self->new( $diff, $self->date_format );
} # END of subtract_seconds


sub add_add {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= $self->day2sec(1);
	my $new		= $self->add_seconds( $arg );
	return $self->time_local( $new->time_local );
} # END of add_add


sub subtract_subtract {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= $self->day2sec(1);
	my $new		= $self->subtract_seconds( $arg, @_ );
	return $self->time_local( $new->time_local );
} # END of subtract_subtract


sub multiply {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= 0+(shift());
	my $value	= $self->time_local;
	my $mul		= $value * $arg;
	return $mul;
} # END of multiply


sub divide {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= 0+(shift());
	my $rev		= shift;
	my $value	= $self->time_local;
	my $div		= $rev ? $arg / $value : $value / $arg;
	return $div;
} # END of divide


sub greater_than {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= 0+(shift());
	my $rev		= shift;
	my $value	= $self->time_local;
	return $rev ? $arg > $value : $value > $arg;
} # END of greater_than


sub less_than {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= 0+(shift());
	my $rev		= shift;
	my $value	= $self->time_local;
	return $rev ? $arg < $value : $value < $arg;
} # END of less_than


sub greater_than_or_equal {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= 0+(shift());
	my $rev		= shift;
	my $value	= $self->time_local;
	return $rev ? $arg >= $value : $value >= $arg;
} # END of greater_than_or_equal


sub equal_equal {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= 0+(shift());
	my $rev		= shift;
	my $value	= $self->time_local;
	return $rev ? $arg == $value : $value == $arg;
} # END of equal_equal


sub bang_equal {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= 0+(shift());
	my $rev		= shift;
	my $value	= $self->time_local;
	return $rev ? $arg != $value : $value != $arg;
} # END of equal_equal


sub equal {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= shift;
	my $rev		= shift;
	my $value	= $self->str_time;
	return $rev ? $arg eq $value : $value eq $arg;
} # END of equal


sub not_equal {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= shift;
	my $rev		= shift;
	my $value	= $self->str_time;
	return $rev ? $arg ne $value : $value ne $arg;
} # END of equal


sub less_than_or_equal {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= 0+(shift());
	my $rev		= shift;
	my $value	= $self->time_local;
	return $rev ? $arg <= $value : $value <= $arg;
} # END of less_than_or_equal

sub numeric_compare {
	my $self	= shift;
	return undef unless ref($self);
	my $arg		= 0+(shift());
	my $value	= $self->time_local;
	return $value <=> $arg;
} # END of numeric_compare

1;

__END__

=back

=head1 REVISION HISTORY

 $Log$
 Revision 1.14  2005/03/04 01:27:14  jjordan
 Repaired bugs in last_week_end_month, last_week_end_year, days_by_week, and days_by_month.

 Revision 1.13  2005/03/02 00:41:21  jjordan
 I modified the yesterday_year and tomorrow_year methods, so that they return the proper year.

 Revision 1.12  2005/03/02 00:36:41  jjordan
 Removing this change so that I can add it in as it's own update.

 Revision 1.10  2005/01/11 22:18:25  apisoni
 str2time() - $hour	+= 12 unless ($hour == 12);  It used to always add 12, but if it was 12pm, then + 12 would be 24, which would reset to 00 (which would not be 12pm).  Now it doesn't change the $hour if its 12pm.

 Revision 1.9  2004/10/23 01:20:30  thai
  - commented out '--' and '++' for further testing

 Revision 1.8  2004/10/23 00:49:45  thai
  - added '--' and '++'

 Revision 1.7  2004/10/11 23:27:19  thai
  - added add_seconds() and subtract_seconds()
    ie.
    $sdate += $sdate->day2sec(5)  # will return a new date object 5 days later

 Revision 1.6  2004/10/09 01:01:10  thai
  - added numeric_compare()
  - added another regexp for str2time()

 Revision 1.5  2004/09/23 01:28:16  thai
  - changed as_string() and str_time() to take a format as an argument

 Revision 1.4  2004/09/15 17:43:29  thai
  - added new_by_string()

 Revision 1.3  2004/05/25 01:14:24  thai
  - added forwarder for as_string()

 Revision 1.2  2004/04/29 18:44:39  thai
  - fixed bug in date parsing of the time

 Revision 1.1  2004/03/17 21:48:17  thai
  - added this module to handle Date and Time objects



=head1 SEE ALSO

POSIX, Time::Local, L<perl>.

=head1 KNOWN BUGS

No bugs are known.

=head1 TODO

Nothing

=head1 COPYRIGHT

 Copyright (c) 2000, Cnation Inc. All Rights Reserved. This module is free
 software. It may be used, redistributed and/or modified under the terms
 of the GNU Lesser General Public License as published by the Free Software
 Foundation.

 You should have received a copy of the GNU Lesser General Public License
 along with this library; if not, write to the Free Software Foundation, Inc.,
 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


=head1 AUTHORS

 Thai Nguyen <thai@bizrate.com>

=cut
