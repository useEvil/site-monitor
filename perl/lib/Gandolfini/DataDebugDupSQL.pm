package Gandolfini::DataDebugDupSQL;

# -------------
# $Revision: 1812 $
# $Date: 2007-08-14 06:31:54 -0700 (Tue, 14 Aug 2007) $
# -----------------------------------------------------------------------------

=head1 NAME

Gandolfini::DataDebugDupSQL - Detect and report duplicate SQL being executed

=head1 SYNOPSIS

To enable detection of duplicate SQL:

    use Gandolfini::DataDebugDupSQL;

    sql_execute_count_tracking(1);

To be more verbose about sql that matches a regex (i.e. a stored proc name),
including printing a stack trace whenever it's executed:

    sql_execute_count_tracking(1, qr/regex/);

To write the stack trace to an external file instead of the log, add a capture to the regex:

    sql_execute_count_tracking(1, qr/reg(ex)/);

To note the execution of an SQL statement (Gandolfini::Data already does this):

    sql_execute_count_use($sql);

To report a summary of duplicate execution, if anys:

    sql_execute_count_report($message);

To discard the data (i.e. at the end of a request):

    sql_execute_count_discard();

=head1 DESCRIPTION

See L</METHODOLOGY> below for how to use this module to identify the sources of duplicate sql requests.

=cut

use strict;
use warnings;
use Carp qw(croak carp);

use base qw(Exporter);

our @EXPORT_OK = qw(
    sql_execute_count_tracking
    sql_execute_count_use
    sql_execute_count_report
    sql_execute_count_discard
    $sql_execute_count_use
);

use constant DEBUG => 0;

(my $lib_root = __FILE__) =~ s{lib/Gandolfini/DataDebugDupSQL.pm}{};

our $sql_execute_verbose;   # regex to trigger verbosity, if enabled
our $sql_execute_count_use; # count of times sql_execute_count_use called
our $sql_execute_count;     # ref to hash of sql, if enabled


=head2 sql_execute_count_tracking

    sql_execute_count_tracking( $enable );
    sql_execute_count_tracking( $enable, $verbose_regex );

If $enable is true then calls to sql_execute_count_use() will be counted instead of being ignored.

If $verbose_regex is true then calls to sql_execute_count_use() with SQL which
matches the regex will produce a stack trace. See L</sql_execute_count_use> for
more information.

=cut

sub sql_execute_count_tracking {
    my ($enable, $verbose_regex) = @_;
    warn "sql_execute_count_tracking($enable, $verbose_regex)\n" if DEBUG;
    if ($enable) {
	sql_execute_count_discard();
	$sql_execute_verbose = $verbose_regex;
    }
    else {
	$sql_execute_count = undef
    }
}


=head2 sql_execute_count_use

    sql_execute_count_use( $sql );

Record an SQL statement being executed. Does nothing unless counting has been enabled using L<sql_execute_count_tracking>.

If a $verbose_regex argument was given to sql_execute_count_tracking() then a
stack trace is written to the log wevenever $sql matches the regex.

If the $verbose_regex contains capturing parens then instead of writing the
stack trace to the log, it's edited slightly and appended to a file:

    /tmp/sql_execute_count_use.$1.$ppid.log

The $1 is whatever string was captured by the parens (with all sequences of
non-word chars replaced with an underscore). Typically the name of a stored procedure.
And $ppid is the parent process id.

The stack trace written to the file has all hex values, like 0x16F53ae, replaced by 0x
in order to simplify later analysis.

=cut

sub sql_execute_count_use {
    ++$sql_execute_count_use;
    return unless $sql_execute_count;

    my ($sql) = @_;
    warn "sql_execute_count_use($sql)\n" if DEBUG;

    my $count = ++$sql_execute_count->{$sql};

    return unless $sql_execute_verbose && $sql =~ /$sql_execute_verbose/;
    my $capture = $1;

    # get stack trace and edit it slightly
    local $Carp::CarpLevel = $Carp::CarpLevel + 4; # skip dull stuff
    my $msg = Carp::longmess("SQL executed $count times by $$: $sql");
    my @msg = grep { !m{called at /dev/null line 0} } split /\n/, $msg;
    s/$lib_root//og for @msg;

    if ($capture) {
        shift @msg; # discard the "SQL executed $count times" message
        push @msg, $msg if !@msg; # stack was only /dev/null's
        # mark the two closest subs (often good candidates for caching)
        $msg[0] .= " [LAST]";
        $msg[1] .= " [PREV]" if @msg > 1;

	s/([A-Z])\(0x[0-9a-f]+\)/$1/g for @msg; # normalize for diff'ing
	$capture =~ s/\W+/_/g; # sanitize for use as filename
	# shell tools:
	# sort /tmp/sql_execute_count_verbose_use.p_s_mid_display_info.log|uniq -c|sort -nr|less
	# grep -C 1 '' /tmp/sql_execute_count_verbose_use.p_s_mid_display_info.log | sort -u
	my $ppid = getppid();	# group by apache instance
	open my $fh, ">>", "/tmp/sql_execute_count_use.$capture.$ppid.log";
	print $fh "$_\n" for @msg;

        # create another file with a more aggressively summarized version
        # so sort|uniq -c will merge lines irrespective of the arguments to subs
        # this is the file to study first
        s/\(.*\) called at/(...) called at/ for @msg;
	open $fh, ">>", "/tmp/sql_execute_count_use.$capture.$ppid.min.log";
	print $fh "$_\n" for @msg;
    }
    else {
	warn join "\n", @msg, '';
    }
}


=head2 sql_execute_count_report

    sql_execute_count_report( $message );

Does nothing if counting is not enabled, or no distinct SQL statements have
been executed more than once.

If there any duplicate SQL statements executed then $message is printed,
followed by each duplicate statement (along with a count of the number of times
it was executed) followed by a summary line.

Finally sql_execute_count_discard() is called.

=cut

sub sql_execute_count_report {
    my ($message) = @_;
    warn "sql_execute_count_report($message)\n" if DEBUG;
    return unless $sql_execute_count;

    my ($total, $redundant) = (0,0);
    for my $sql (sort keys %$sql_execute_count) {
	my $count = $sql_execute_count->{$sql};
	$total     += $count;
	$redundant += $count-1 if $count > 1;
	next unless $count >= 2;
	warn "$message\n" if $message;
	$message = undef;
	warn sprintf "SQL executed %d times: %s\n", $count, $sql;
    }

    if ($redundant) {
	warn "$message\n" if $message;
	warn sprintf "Out of %d database requests %d (%.1f%%) were redundant duplicates\n",
	    $total, $redundant, $redundant/$total*100
    }
    sql_execute_count_discard();
}


=head2 sql_execute_count_discard

    sql_execute_count_discard()

Discards count data. Usually called automatically by L</sql_execute_count_report>.

=cut

sub sql_execute_count_discard {
    warn "sql_execute_count_discard\n" if DEBUG;
    $sql_execute_count = {}
}


1;

__END__

=head1 METHODOLOGY

=head2 Default Monitoring

By default sql_execute_count_tracking is enabled for non-production environments

    sql_execute_count_tracking(1)
        unless isDeployMode( SZ_DEPLOY_PR );

so duplicate sql requests within a single http page request will be detected
and reported to the error_log like this:

    Duplicate SQL for GET /9L--Cisco_Catalyst_Hub_-_cat_id--494__prod_id--5168017
    SQL executed 2 times:exec bizrate..p_s_prof_reviews 5168017

=head2 Data Collection

Start by enabling verbose reporting of stack traces for just the particular sql being duplicated:

    sql_execute_count_tracking(1, qr/(p_s_prof_reviews)/)
        unless isDeployMode( SZ_DEPLOY_PR );

Note the use of capturing parens within the regex. That forces the stack traces
to be written to files. See L</sql_execute_count_report>.

Then restart the httpd and replay the problem requests. It's best to replay
I<many> queries so you can see alternative queries that cause the same problem
through different code paths.

You'll end up with two files in /tmp like this:

    /tmp/sql_execute_count_use.p_s_prof_reviews.12128.min.log
    /tmp/sql_execute_count_use.p_s_prof_reviews.12128.log

=head2 Data Analysis

To get a high-level view run a "sort|uniq|sort" on the '.min.log file:

  sort /tmp/sql_execute_count_use.p_s_prof_reviews.12128.min.log | uniq -c | sort -rn

which will produce something like this:

  23  eval {...} called at /home/tbunce/local/lib/perl5/site_perl/5.8.6/Error.pm line 419
  23  Hackman::Utils::HandlerSpec::spec::__ANON__(...) called at lib/Hackman/Dispatch/Apache.pm line 280
  23  Hackman::Display::HTML::Handler::handler(...) called at lib/Hackman/Utils/HandlerSpec.pm line 224
  23  Hackman::Display::HTML::Handler::__ANON__(...) called at /home/tbunce/local/lib/perl5/site_perl/5.8.6/Error.pm line 427
  23  Hackman::Display::HTML::Handler::Product::run(...) called at lib/Hackman/Display/HTML/Handler.pm line 90
  23  Hackman::Display::HTML::Handler::Product::_determine_tokenized_page(...) called at lib/Hackman/Display/HTML/Handler/Product.pm line 93
  23  Error::subs::try(...) called at lib/Hackman/Display/HTML/Handler.pm line 136
  12  Hackman::Display::PodCollector::build_template_data(...) called at lib/Hackman/Display/HTML/Handler/Product.pm line 128
  12  Hackman::Display::Business::CompactedProduct::_get_detailed_data(...) called at lib/Hackman/Display/Business/CompactedProduct.pm line 267 [PREV]
  12  Gandolfini::Data::list_obj(...) called at lib/Hackman/Display/Business/CompactedProduct.pm line 315 [LAST]
  11  Hackman::Display::POD::ProductReview::new(...) called at lib/Hackman/Display/PodCollector.pm line 106
  11  Hackman::Display::POD::ProductReview::build_template_data(...) called at lib/Hackman/Display/PodCollector.pm line 159
  11  Hackman::Display::Business::CompactedProduct::build_template_data(...) called at lib/Hackman/Display/POD/ProductReview.pm line 115
  11  Gandolfini::Data::list_hash(...) called at lib/Hackman/Display/POD/ProductReview.pm line 431 [LAST]
   8  Hackman::Display::PodCollector::add_pod(...) called at lib/Hackman/Display/HTML/Handler/Product.pm line 172
   8  Hackman::Display::POD::ProductReview::_get_reviews_summary(...) called at lib/Hackman/Display/POD/ProductReview.pm line 742
   8  Hackman::Display::POD::ProductReview::_get_review_professional_data(...) called at lib/Hackman/Display/POD/ProductReview.pm line 755 [PREV]
   8  Hackman::Display::POD::ProductReview::_get_review_list(...) called at lib/Hackman/Display/POD/ProductReview.pm line 201
   8  Hackman::Display::HTML::Handler::Product::_12(...) called at lib/Hackman/Display/HTML/Handler/Product.pm line 120
   3  Hackman::Display::PodCollector::add_pod(...) called at lib/Hackman/Display/HTML/Handler/Product.pm line 239
   3  Hackman::Display::POD::ProductReview::_get_review_professional_data(...) called at lib/Hackman/Display/POD/ProductReview.pm line 225 [PREV]
   3  Hackman::Display::HTML::Handler::Product::_9L(...) called at lib/Hackman/Display/HTML/Handler/Product.pm line 120
   1  Hackman::Display::POD::Product::build_template_data(...) called at lib/Hackman/Display/PodCollector.pm line 159
   1  Hackman::Display::Business::CompactedProduct::build_template_data(...) called at lib/Hackman/Display/POD/Product.pm line 50

That's a rich source of information. Here's how to read it:

The top few lines with counts of 23 show that we found 23 instances of this sql
being executed and that those subroutines were executed at those places for all
of them. This is the common code path. Usually it only contains 'high-level' calls
such as Hackman::Display::HTML::Handler::handler.

Note the two lines marked [LAST] and the three marked [PREV]. These show the
last two interesting calls in the stack before the sql was executed.
They should be the initial focus of investigation.

Performing the same command on the '.log' file instead of the '.min.log'
produces a similar but longer report. About twice the size in this case.
The longer report includes the arguments to the subroutine calls which can be useful.

=cut

vim: ts=8:sw=4:et
