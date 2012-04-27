package Gandolfini::Crawler;

=head1 NAME

Gandolfini::Crawler

=head1 SYNOPSIS

my $brand   = 'shopzilla.com';
my $machine = 'hackmandev.';
my $port    = ':8740' if ($machine eq 'hackmandev');
my $links   = '200';
my $regex   = '';
my $user_agent = 'Internet Explorer/5.5 (mozilla 4.0)';
my $error_log  = 1; #default to tail error logs and view

GetOptions ('user_agent=s' => \$user_agent , 'links=i' => \$links , 'port=s' => \$port , 'brand=s' => 
\$brand,
$'machine=s' => \$machine, error_log => \$error_log);

my $crawler = Crawler->new(
    brand        => $brand,
    machine      => $machine,
    port         => $port,
    user_agent   => $user_agent,
    debug        => 1,
    error_log    => $error_log,
    tail_log     => 1,
    #total_links => ,  #default is unlimited
);

#create a list of links to skip!!! VERY IMPORTANT!!
my $link_skip_list =
{
    '/rd' => 1,
    'javascript' => 1,
    'www\.shop', => 1,
    'www\.bizrate' => 1,
    'www\.shopzilla' => 1,
    'nielsen' => 1,
    'server-au' => 1,

};

$crawler->link_skip_list($link_skip_list); #pass a hash ref of regexs links to skip

$crawler->init(); #need more options?!


#Main auto loop below if you want to automate the fetching...
$crawler->fetch_random_pages;

#OR

#Manual looping of random pages..

NOTE: Please see file: playground/apps/hackman/t/crawler.pl FOR A COMPLETE EXAMPLE...

$crawler->init()
$crawler->start();
$crawler->fetch_one_random_page;

$crawler->tail_log(0); #can turn off tailing logs, or turn on by passing a value other than 0
my $fh = $crawler->log_file_fh;
$fh = $crawler->seek_end_file($fh); 

print "-" x 100 . "\n";
until ($crawler->links_count == $crawler->total_links)
{
    $crawler->fetch_one_random_page;

	print "URL: " . $crawler->current_url  . " Returned: " . $crawler->http_status . " Time: " . $crawler->total_fetch_time . "\n";

	$fh = $crawler->tail_file($fh); #<-- will print out the error log output
    print "-" x 100 . "\n";

} #END OF until

#############################################################################
#---------------------------------------------------------------------------#
#Fetching pages from a list..

NOTE: Please see file: playground/apps/hackman/t/crawler.pl FOR A COMPLETE EXAMPLE...


First create an array of list URLS (either from a file or whatever...)

my $crawler = Crawler->new;
$crawler->url_list($urls);
$crawler->init();

#--- Still Working on. And can get tricky. ---#
#will add a testmeas param to the URL except homepages.
#begin == what range to start...10's, 20's, etc..
#range == x1, x2, x3 (if range set to 3)
#interval == add interval to range

#below is optional... works fine without...
$crawler->add_testmeas(begin => 1, range => 3, interval => 1);

while (my $url = $crawler->next_url)
{
   $crawler->get_this_url($url);
   my $fetch_time = $crawler->total_fetch_time;
   my $size       = $crawler->page_size;
   my $html       = $crawler->html_content; #can use this for other testing...
   print "got $url, it took $fetch_time and was $size bytes \n";
}


=head1 DESCRIPTION
A crawler class that can be used with different types of crawling. It can be used to automaticly
crawl random URLs for a given domain/machine/port/brand. You can also randomly crawl urls from a
script and perform different logic for each url received. Also you can pass in a filelist and have
the crawler run thru each of the urls in the files automaticly, or you can use a script to perform
action for each link fetched from a given list. 

=head1 REQUIRES
WWW::Mechanize
Time::HiRes


=head1 TODO

Move some methods into different classes. Add more error checking. And overall cleanup and other
stuff. Feel free to help...

=cut


use strict;
use base qw(WWW::Mechanize);
use Time::HiRes qw(gettimeofday tv_interval);
use Scalar::Util qw/reftype/;

use constant DEBUG => 0;

=head1 METHODS

######################################################################################################
#PUBLIC SUBS
######################################################################################################


=head2 CONSTRUCTORS

=item C<new> ( params )

Creates a new crawler object.

=cut


sub new
{
    my $proto   = shift;
    my $class   = ref($proto) || $proto;
    my (%args)  = @_;

	my $self;
	if (defined( $args{allow_cookies} ) ) {
		$self = $class->SUPER::new(agent => $args{user_agent}, cookie_jar => {}); 
	} else {
		$self = $class->SUPER::new(agent => $args{user_agent});
	}

    my %new_args = (
        type           => $args{'type'} || 'random', #random is default. can be others... 
        brand          => $args{'brand'} ||  'bizrate.com', #default bizrate
        machine        => $args{'machine'} || 'hackmandev.', #default
        port           => $args{'port'} || undef, #default to my port
        user_agent     => $args{'user_agent'} ||  'mozilla/4.0', #stupid default aint it? :)
        allow_cookies  => $args{'allow_cookies'} || undef, #dont accept cookies by default
        follow_links   => $args{'follow_links'} || undef, #default follow unlimited links
        debug          => $args{'debug'} || 0,
		error_log      => $args{'error_log'} || 0,
		tail_log       => $args{'tail_log'}  || 0,
		url_list       => $args{'url_list'} || undef,
		single_testme  => $args{'single_testme'} || undef,
	);
	map { $self->{$_} = $new_args{$_} } keys %new_args;

	$self->{'user_info'} = 
	{
		user_name => $ENV{'USER'},
		user_home => $ENV{'HOME'},
		log_dir   => "/home/playground/$ENV{'USER'}/logs",
	};
	
	$self->_start_tail_file if ($self->tail_log);
	return $self;

} #END OF SUB


=item C<start>

Start crawling by hitting our first page, find all the links
and set the link info/status

=cut

sub start {
	my $self = shift;
	my (%args) = @_;
	my $start  = $args{'start'} || $self->next_url || $self->homepage; #maybe make it the homepage?

	print "Starting: $start \n" if ($self->debug);

	$self->get($start);
	$self->_set_link_info($start);

	$self->_find_all_links; #also extract them and puts them in our list

} #END OF SUB


=item C<get_links_from_url> ($fully_qualified_url)

A simpler interface to this crawler object to return all the links on a single page

=cut

sub get_links_from_url{
	my $self = shift;
	my %args = @_;
	$self->get_this_url($args{url});
	
	my $links = $self->find_all_links();
	if(defined($args{regex})) {
		my @links = grep { $_ =~ $args{regex} } @$links;
		$links = \@links;
	}

	return $links; 
}

=item C<get_this_url> ($url)

Retreive a specific url and set the link info. See method _set_link_info

=cut

sub get_this_url {
	my $self = shift;
	my $url  = shift || undef;

	if ($url) {
		$self->_fetch_time_begin('set'); #set means nothing. but without it, it will return 
		my $http_obj = $self->get($url);

		#should make below use a private method.
		$self->{'http_obj'} = $http_obj;

		$self->_fetch_time_end('set'); #again, foo means nothing. but without foo, it will returne
		$self->_set_link_info($url);
		$self->_find_all_links;
		return 1;
	}
	return 0;
} #END OF SUB

=item C<fetch_random_pages> ()

Main logic. Fetches random pages based on parameters set in the constructor...
If no start page defined, it will use the homepage. And then randomly follow links found on each
page that is fetches. Follow until N links are retreived

=cut

sub fetch_random_pages {
	my $self = shift || undef;
	return 0 if ($self->type ne 'random'); 


	$self->start if (! $self->current_url);
	$self->total_links(10000000) if (! $self->total_links); #set to unlimited if not set..
	until ($self->links_count == $self->total_links) {
		#print "fetching another random page... " .  $self->links_count . " \n";

		#pick a random url from our current list or use the default homepage
		my $url = $self->_pick_random_url;

		#sometimes i found links that are just #
		$url    = $self->_pick_random_url if (length($url) < 2);

		$self->get_this_url($url); #this method set time info too
	
		$self->print_status if ($self->debug);

	}
} #END OF SUB

=item C<fetch_one_random_page>

Only fetch one random page at a time. This method should be used in scripts where you want to
control the flow and do other things with each page that is retreived.

=cut

sub fetch_one_random_page {
	my $self = shift;
	return 0 if ($self->type ne 'random');

	$self->start if (! $self->current_url);
	$self->total_links(10000000) if (! $self->total_links); #set to unlimited if not set..

	my $url = $self->_pick_random_url;

	#sometimes i found links that are just #
	$url    = $self->_pick_random_url if (length($url) < 2);

	my $count = 0;
	until ($url ne '#')
	{
		$url = $self->homepage() if ($count == 5);
		$count++;
		$url    = $self->_pick_random_url;
	}

	#print "whats this: $url \n";

	 if ($self->{'single_testme'} )
	 {
		#$url = $self->_add_single_testmeas(url => $url, testme =>
		$url = $self->_add_single_testmeas($url, $self->{'single_testme'} );
	}

	#fetch a random url
	
	$self->get_this_url($url);
	
} #END OF SUB

=item C<next_url) ()

Gets the next url from our url_list. This list is set when you want to follow a set of URLs defined
ahead of time. Currently can be used with a file list...

=cut

sub next_url {
	my $self = shift;
	my $url_list = $self->url_list;
	my $next = shift(@$url_list);
	return $next if ($next);
	return 0;
} #END OF SUB

#follow all links in our list
sub follow_list {
	my $self = shift;

	until (not (my $next =  $self->next_url) )
	{
		chomp $next;
		print "next: $next \n" if ($self->debug);
		$self->get_this_url($next);
	}
	
} #END OF SUB

=item C<print_status> ()

Prints the status of the current http status. Eg 200, 301, 302, 404, etc....

=cut

sub print_status {
	my $self = shift;
	#print $self->http_status  . ' (' . $self->links_count . ') ' . " for " . $self->current_url . "\n";
	my $count = $self->links_count;
	print "($count) " . $self->http_status . " for: " . $self->current_url  . " \n";
	print "-" x 85 . "\n";
} #END OF SUB

=item C<links_list> ([$links])

Set or return the current links found on the page we just request...

=cut

sub links_list {
	my $self = shift;
	my $links = shift || undef;
	$self->{'links_list'} = $links if (defined $links);
	return $self->{'links_list'} if (not defined $links);
} #END OF SUB

=item C<links_count> ()

Return total links we already crawled...

=cut

sub links_count {
	my $self = shift;
	return $self->{'visited_links_count'};
} #END OF SUB

=item C<link_skip_list> ([$list])

Set or get the list of links to skip. This is useful so we don't have the crawler leave our site and
start fetching pages outside of space.

=cut

sub link_skip_list {
	my $self = shift;
	my $list = shift || undef;
	$self->{'link_skip_list'} = $list if (defined $list);
	return $self->{'link_skip_list'}  if (not defined $list);
} #END OF SUB


=item C<use_default_skip_list> ()

Uses the default built-in link skip list

=cut


sub use_default_skip_list {
	my $self = shift;
	my $list =
	{
		'/rd'            => 1,
		'javascript'     => 1,
		'www\.bizrate'   => 1,
		'www\.shopzilla' => 1,
		'fr\.bizrate'    => 1,
		'de\.bizrate'    => 1,
		'uk\.bizrate'    => 1,
		'nielsen'        => 1,
		'server-au'      => 1,
		'partners'       => 1,
		'xpml'           => 1,
		'features'       => 1,
		'mailto'         => 1,
	};

	$self->link_skip_list($list);
	return 1;
} #END OF SUB

=item C<current_url> ($url)

Set or return the current link we just crawled

=cut

sub current_url {
	my $self = shift;
	my $url  = shift || undef;
	$self->{'current_url'} = $url if (defined $url);
	return $self->{'current_url'} if (not defined $url);
} #END OF SUB

=item C<http_status> ()

Set or return the status of the current url we requested

=cut

sub http_status {
	my $self = shift;
	my $status = shift || undef;
	$self->{'http_status'} = $status if (defined $status);
	return $self->{'http_status'} if (not defined $status);
} #END OF SUB


=item C<html_content> ([$html_content])

Set or return the html content of the current page we just fetched..

=cut

sub html_content {
	my $self = shift;
	my $content = shift || undef;
	$self->{'html_content'} = $content if (defined $content);
	return $self->{'html_content'} if (not defined $content);

} #END OF SUB


=item C<page_size> ()

Return the size of the page we just fetched...

=cut

sub page_size {
	my $self = shift;
	return $self->{'page_size'};
} #END OF SUB


=item C<homepage> ([$homepage])

Set our homepage or return the homepage. If no homepage passed, it will create one based on the
parameters used in the constructor. We need to have a starting url to crawl...

=cut

sub homepage {
	my $self = shift;
	my $homepage = shift || undef;

	if (defined $homepage) {
		$self->{'homepage'} = $homepage;
		return $self->{'homepage'};
	}

	if (not defined $self->{'homepage'}) {
		my $port = $self->port || '';
		my $page = "http://" . $self->machine . $self->brand . $port . "/";
		$self->{'homepage'} = $page;
	}
	return $self->{'homepage'} if (not defined $homepage);
	

} #END OF SUB

=item C<log> ()

add functionality later to log else where...

=cut

sub log {
	my $self = shift;
	my $log  = shift || undef;
	$self->{'log'} = $log if (defined $log);
	return $self->{'log'} if (not defined $log);
} #END OF SUB

=item C<type> ([$type])

Define the crawler type. random, url list, etc...

=cut


sub type {
	my $self = shift;
	my $type = shift || undef;
	$self->{'type'} = $type if (defined $type);
	return $self->{'type'} if (not defined $type);
} #END OF SUB


=item C<total_links> ([$links])

Set or return how many links to follow

=cut

sub total_links {
	my $self = shift;
	my $links = shift || undef;
	$self->{'follow_links'} = $links if (defined $links);
	return $self->{'follow_links'} if (not defined $links);

} #END OF SUB

=item C<brand> ([$brand])

Return or define a brand to use. shopzilla or bizrate, etc...

=cut

sub brand {
	my $self = shift;
	my $brand = shift || undef;
	$self->{'brand'} = $brand if (defined $brand);
	return $self->{'brand'} if (not defined $brand);

} #END OF SUB

=item C<machine> ([$machine])

Return or define a machine to use. hackmandev, hackmanstage, etc...

=cut

sub machine {
	my $self = shift;
	my $machine = shift || undef;
	$self->{'machine'} = $machine if (defined $machine);
	return $self->{'machine'} if (not defined $machine);
} #END OF SUB

#define a port to use. 8740, etc...
sub port {
	my $self = shift;
	my $port = shift || undef;
	$self->{'port'} = $port if (defined $port);
	return $self->{'port'} if (not defined $port);

} #END OF SUB

=item C<user_agent> ([$user_agent])

Return or define a useragent to use with the crawler. eg. mozilla/4.0, googlebot 2.1, etc...

=cut

sub user_agent {
	my $self = shift;
	my $user_agent = shift || undef;
	$self->{'user_agent'} = $user_agent if (defined $user_agent);
	return $self->{'user_agent'} if (not defined $user_agent);
} #END OF SUB

=item C<allow_cookies> ([$allow])

This method needs more logic to work with www::mechanize's cookie jar

=cut

sub allow_cookies {
	my $self = shift;
	my $allow = shift || undef;
	$self->{'allow_cookies'} = $allow if (defined $allow);
	return $self->{'allow_cookies'} if (not defined $allow);
} #END OF SUB

=item C<debug>

Set or return debug value

=cut

sub debug {
	my $self = shift;
	my $debug = shift || undef;
	$self->{'debug'} = $debug if (defined $debug);
	return $self->{'debug'} if (not defined $debug);
} #END OF SUB

=item C<error_log> ([$error_log])

Set or return error_log flag. not used yet...

=cut

sub error_log {
	my $self = shift;
	my $error_log = shift || undef;
	$self->{'error_log'} = $error_log if (defined $error_log);
	return $self->{'error_log'} if (not defined $error_log);
} #END OF SUB

=item C<tail_log> ([$tail])

Set or return tail log flag

=cut

sub tail_log {
	my $self = shift;
	my $tail = shift;
	$self->{'tail_log'} = $tail if (defined $tail);
	return $self->{'tail_log'} if (not defined $tail);

} #END OF SUB

=item C<url_list> ([$list])

Set or return the current url list

=cut

sub url_list {
	my $self = shift;
	my $list = shift || undef;
	$self->{'url_list'} = $list if (defined $list);
	return $self->{'url_list'} if (not defined);
} #END OF SUB

=item C<url_list_count> ()

Return total links our url_list

=cut

sub url_list_count
{
	my $self = shift;
	return 0 if (! $self->url_list );
	return scalar( @{$self->url_list} );
} #END OF SUB



=item C<add_testmeas> ([begin => n, range => n, interval => n])

Add testmeas=n to each of the URLs in our list. 
begin == where to begin. 10's, 50's, etc...
range == from begin to range. eg, 50 -- 90
interval == how many per each range.
Default is only 1: http://bizrate.com/buy/browse__cat_id--24,testmeas--11.html
*NOTE -- Will not add testmeas to homepages (at least for now)

=cut

sub add_testmeas {
	my $self     = shift;
	my (%args)   = @_;
	my $begin    = $args{'begin'} || 0;
	my $range    = $args{'range'} || 0;
	my $interval = $args{'interval'} || 1;
	my $only     = $args{'only'}  || undef;


	#add a single testmeas only in ramdom mode
	if (defined $only && $self->type eq 'random')
	{
		return undef if ($self->current_url =~ m|/$|);

		#$self->_add_single_testmeas($only);
	}
	
	return 0 if ($begin > 9);
	return 0 if (! $self->url_list || $range > 9);
	my $url_list = $self->url_list;
	my $new_list = ();
	for my $url (@$url_list)
	{
		chomp $url;
		$url =~ s|\s+||g; #remove trailing spaces anywhere...
		next if ($url =~ m#/$#); #would break if it was just bizrate.com
		#cuz burzin made the vip (shopzilla) even though it points to bizrate
		if ($url =~ m#(bizrate|rlviptest01)#)  
		{
			#bizrate
			#skip home page

			for ($begin..$range)
			{
				my $here = $_;
				for (1..$interval)
				{
					my $tempint = $_;
					my $number = $here.$tempint;
					#print "number: $number \n";
					my $tempurl = "";
					$tempurl    = $url;
					$tempurl =~ s#\.html$#,testmeas--$number\.html#;
					push (@$new_list, $tempurl);
				}
			}
		}
		elsif ($url =~ m|shopzilla|)
		{
			#shopzilla
			#skip home page
			for ($begin..$range)
			{
				my $here = $_;
				for (1..$interval)
				{
					my $tempint = $_;
					my $number = $here.$tempint;
					my $tempurl = "";
					$tempurl    = $url;
					$tempurl = $url . "__testmeas--$number";
					push (@$new_list, $tempurl);
				}
			}
			
		}
	} ###################################################
	$self->url_list($new_list);

	
} #END OF SUB

=item C<add_show_to_uri> ()

Adds show=N to the URI passed in

=cut

sub add_show_to_uri
{
	my $self   = shift;
	my (%args) = @_;
	my $uri    = $args{'uri'}  || undef;
	my $show   = $args{'show'} ||  undef;

	if (defined $uri && defined $show)
	{
		if ($uri =~ m|bizrate|)
		{
			#bizrate
			$uri =~ s|\.html|,show--$show\.html|;
		}
		elsif ($uri =~ m|shopzilla|)
		{
			#shopzilla
			$uri = $uri . "__show--$show";
		}
	}

	return $uri;
} #END OF SUB


=item C<full_url> ()

Returns the current url in a fully qualified stype

=cut
sub full_url
{
	my $self = shift;

	my $machine = $self->machine;
	my $brand   = $self->brand;
	my $port    = $self->port || '';
	my $full    = "http://$machine$brand$port";

	return $full;
} #END OF SUB


=item C<user_info> ()

Return user info like username, home dir, log dir

=cut

sub user_info
{
	my $self = shift;

	return $self->{'user_info'};

} #END OF SUB

=item C<log_file_fh> ([$log_fh])

Sets or return the current log filehandle to used when printing errors from the log to the screen

=cut

sub log_file_fh
{
	my $self = shift;
	my $log_fh = shift || undef;
	$self->{'LOG_FH'} = $log_fh if (defined $log_fh);
	return $self->{'LOG_FH'} if (not defined $log_fh and $self->tail_log);

} #END OF SUB

=item C<seek_end_file> ($fh)

Seek to end of the file of FH passed and return success value (1) or return 0 if failed

=cut

sub seek_end_file
{
	my $self = shift;
	my $fh   = shift || undef;
	
	if (defined $fh)
	{
		seek($fh, -1, 2) || return 0;
		#return $fh;
		$self->log_file_fh($fh);
	}
	return 0;
	
	
	
} #END OF SUB

=item C<tail_file> ($fh)

Tail the end of the FH passed in and then reset the seek position

=cut

sub tail_file
{
	my $self = shift;
	my $fh   = shift || undef;

	my $curpos;
	my @tail ;
	if (defined $fh)
	{
		for ($curpos = tell($fh); $_ = <$fh>; $curpos = tell($fh))
		{
			chomp;
			#print "$_ \n" if ($_);
			push (@tail, "$_\n") if ($_);
	    }
		seek($fh, $curpos, 0);
		#return $fh;
		$self->log_file_fh($fh);
	}
		
	return \@tail;
} #END OF SUB

=item C<total_fetch_time> ()

Returns the total time it took to fetch a url...

=cut

sub total_fetch_time
{
	my $self = shift;
	return $self->{'fetch_time'};

} #END OF SUB

=item C<testme> ()

Just a bogus method...

=cut

sub testme
{
	my $self = shift;
	print "we are ok! " . $self . " \n";
} #END OF SUb
#-----------------------------------------------------------------------#
####################### PRIVATE SUBS ####################################
#-----------------------------------------------------------------------#


=item C<_add_single_testmeas> ($session_test_id)

Adds a single testmeas=N to the current random url we're about to fetch...

=cut


sub _add_single_testmeas
{
	my $self = shift;
	#--------------------------------------------------
	# my (%args) = @_;
	# my $only   = $args{'testme'};
	# my $url    = $args{'url'};
	#-------------------------------------------------- 
	my $url = shift || undef;
	my $only = shift || undef;
	return undef if (! defined $only && ! defined $url);
	return $url if ($url =~ m#/$#);

	my $brand = $self->brand;
	my $full  = $self->full_url;
	my $full_with_uri = $url;
	$full_with_uri    = $full . $url if ($full_with_uri !~ m|http|);

	if ($self->brand =~ m#bizrate#i || $full_with_uri =~ m#rlviptest01#)
	{
		$full_with_uri =~ s|\.html|,testmeas--$only\.html|;
		$url = $full_with_uri;
	}	
	elsif ($self->brand =~ m|shopzilla|i)
	{
		$full_with_uri .= "__testmeas--$only";
		$url = $full_with_uri;
	}

	return $url;
} #END OF SUB


=item C<_allow_this_link> ($link)

Verify if a current link is allowed to be crawled..

=cut

sub _allow_this_link
{
    my $self = shift;
    my $link = shift || undef;
    my $list = $self->link_skip_list;

	my $rv = '1';
    for my $not_allowed (keys %$list)
    {
        $rv = 0 if ($link =~ m|$not_allowed|i);
		if ($link =~ m|http|)
		{
			my $machine = $self->machine;
			$rv = 0 if ($link !~ m|$machine|);
		}
    }
    return $rv;

} #END OF SUB


=item C<_extract_links_from_object> ([$links])

Extracts all the links in the current minus those in our regex list

=cut

sub _extract_links_from_object
{
    my $self = shift;
    my $links = shift || undef;

    my $_links = ();
	my $_raw_links = ();
    if (defined $links)
    {
        if (ref $links and reftype($links) eq 'ARRAY') )
        {
            for (@$links)
            {
                 my $link = $_->[0];
				 push (@$_raw_links, $link);
                 push (@$_links, $link) if ($self->_allow_this_link($link));
            }
        }
    }

	$links = undef;

	$self->{'_raw_links'} = $_raw_links;

    return $_links;
} #END OF SUB


sub raw_links {
	my $self = shift;
	my $list = shift || undef;
	return $self->{'_raw_links'};
} #END OF SUB
=item C<_find_all_links> ()

Finds all the links in the current exluding those in our dont follow regex list

=cut

sub _find_all_links
{
    my $self = shift;
    my $links = $self->find_all_links(); #www::mechanize specific                                            

    my $extracted_links = $self->_extract_links_from_object($links);

    $self->links_list($extracted_links);


} #END OF SUB


=item C<_increase_link_count> ()

Increase the amount of links we visited...

=cut


sub _increase_link_count
{
    my $self = shift;

    if ($self->{'visited_links_count'})
    {
        #print "were at: " . $self->{'visited_links_count'} . "\n";
        $self->{'visited_links_count'}++;
    }
    else
    {
        #print "FIRST TIME! \n";
        $self->{'visited_links_count'} = 1;
    }
    #$self->{'visited_links_count'} = $self->{'visited_links_count'} ? ($self->{'visisted_links_count'}++ ) : 1
$;

} #END OF SUB


=item C<_set_link_info> ($link)

Set the status for this link. Includes http status, html content and increase the link count...

=cut

sub _set_link_info
{
    my $self = shift;
    my $link = shift;
    $self->current_url($link);
    $self->http_status($self->status() ); #www mech specific
    $self->html_content($self->res->content);
	$self->_set_page_size;
    $self->_increase_link_count;

} #END OF SUB

=item C<_set_page_size> ()

Set the size of the current html page we just fetched...

=cut

sub _set_page_size
{
	my $self = shift;
	my @html = $self->html_content;
	$self->{'page_size'} = length("@html");
	
} #END OF SUB

=item C<_pick_random_url> 

Randomly pick a url from the links we saw...

=cut

sub _pick_random_url
{
    my $self = shift;
    my $list = $self->links_list;
    my $rand = $list->[rand @$list];
    return $rand if ($rand);
    return $self->homepage; #just incase??


} #END OF SUB

=item C<_start_tail_file> ()

Opens a filehandle to the user's error log file and returns the FH

=cut

sub _start_tail_file
{
    my $self = shift;
    my $userinfo = $self->user_info;
    my $logdir   = $userinfo->{'log_dir'};
    open (LOGFILE, "$logdir/error_log" ) or die "can't open  $logdir/error_log  : $!";
    $self->{'LOG_FH'} = *LOGFILE;

} #END OF SUB


=item C<_fetch_time_begin> ([$time])

Sets the begin time of fetching a url or returns the begin fetch time.

=cut

sub _fetch_time_begin
{
        my $self = shift;
        my $time = shift || undef;
                
        if (defined $time)
        {
                my $t0 = [gettimeofday];
                $self->{'fetch_time_begin'} = $t0;
        }
        if (not defined $time)
        {
                return $self->{'fetch_time_begin'};
        }
        
} #END OF SUB

=item C<_fetch_time_end> ([$time])

Sets the end time of fetching a url or returns the end fetch time.

=cut

sub _fetch_time_end
{
        my $self = shift;
        my $time = shift || undef;

        if (defined $time)
        {
                my $t1 = [gettimeofday];
                my $t0 = $self->{'fetch_time_begin'}; #could use private method instead?
                $self->{'fetch_time_end'} = $t1;
                my $t0_t1 = tv_interval $t0, $t1;
                $t0_t1 = sprintf("%0.3f", $t0_t1);
                $self->{'fetch_time'} = $t0_t1;
        }
} #END OF SUB


######################################################################################################
#END OF PRIVATE
######################################################################################################



1;

__END__

