#!/usr/bin/perl
use strict;

SZTest::CLI::Cluster->runtests;

BEGIN {
package SZTest::CLI::Cluster;
use RepRoot;
use base qw(Test::Class);
use Test::More;
#use Test::Exception;
use Test::MockObject;
#use Test::MockObject::Extends;
use Data::Dumper;
use Carp;
use POSIX;
#use Cwd;

# uncomment to get a stack trace leading to failures
#$SIG{__DIE__} = sub {confess @_};
#$SIG{__WARN__} = sub {Carp::longmess(@_)};

sub A000_load_modules : Test(startup => 1) {
    use_ok('CLI::Cluster');
}


sub A010_new : Tests {

    my $logger = Test::MockObject->new;
    $logger->set_true(qw(debug info));
    $logger->mock(logdie => sub {shift; die @_ });
    
    my $args = {
        logger => $logger,
        forks => {US => 1},
        servers => {US => ['localhost']},
        per_server => {US => 1},
        servers_to_use => {},
        country_code => 'US',
    };

    my $c = CLI::Cluster->new($args);
    isa_ok($c, 'CLI::Cluster');
}


# run a simnple child process ("ssh localhost /bin/echo --success--") and verify it ran successfuly
sub A020_fork_process : Tests {

    my $logger = Test::MockObject->new;
    $logger->set_true(qw(debug info));
    $logger->mock(logdie => sub {shift; die @_ });

    my $args = {
        logger => $logger,
        forks => {US => 1},
        servers => {US => ['localhost']},
        per_server => {US => 1},
        servers_to_use => {},
        country_code => 'US',
        script => '/bin/echo',
    };

    my $c = CLI::Cluster->new($args);
    isa_ok($c, 'CLI::Cluster');
    #warn Data::Dumper->Dump([$c],['c']),"\n";

    my $run = 'run000';
    $c->params({$run => '--success--'});
    $SIG{CHLD} = $c->sigchld_handler;

    my ($result, $err, $stdout, $stderr) = capture_output( 
        sub {
            my $pid = $c->fork_process($run, 'localhost');
            #warn "waiting for $pid\n";
            while (kill 0, $pid) { sleep(1); } # wait for child to terminate
            return $c->child_status->{$pid};
        }
    );

    die $err if $err;
    my $status = WEXITSTATUS($result);
    is($status, 0, 'exit status');
    is($stderr, '', 'STDERR');
    is($stdout, "--success--\n", 'STDOUT');
}


# run a child process expected to fail to execute ("/bin/bogus localhost /bin/echo --bogus--")
sub A022_fork_process_bogus : Tests {

    my $logger = Test::MockObject->new;
    $logger->set_true(qw(debug info));
    my $die_log;
    $logger->mock(logdie => sub {shift; $die_log .= join('',@_) });

    my $args = {
        logger => $logger,
        forks => {US => 1},
        servers => {US => ['localhost']},
        per_server => {US => 1},
        servers_to_use => {},
        country_code => 'US',
        script => '/bin/echo',
    };

    my $c = CLI::Cluster->new($args);
    isa_ok($c, 'CLI::Cluster');
    #warn Data::Dumper->Dump([$c],['c']),"\n";

    my $run = 'run000';
    $c->params({$run => '--bogus--'});
    $c->ssh('/bin/bogus');
    $SIG{CHLD} = $c->sigchld_handler;

    my ($result, $err, $stdout, $stderr) = capture_output( 
        sub {
            my $pid = $c->fork_process($run, 'localhost');
            while (kill 0, $pid) { sleep(1); } # wait for child to terminate
            return $c->child_status->{$pid};
        }
    );

    die $err if $err;
    my $status = WEXITSTATUS($result);
    is($status, 127, 'exit status');
    like($die_log, qr/^sigchld_handler: Process\(\d+\) run000\@localhost Failed$/, 'die message');
    $logger->called_ok('logdie');
    is($stderr, "sh: /bin/bogus: No such file or directory\n", 'STDERR');
    is($stdout, '', 'STDOUT');
}


# run a child process expected to return false ("/bin/false localhost /bin/echo --false--")
sub A024_fork_process_false : Tests {

    my $logger = Test::MockObject->new;
    $logger->set_true(qw(debug info));
    my $die_log;
    $logger->mock(logdie => sub {shift; $die_log .= join('',@_) });

    my $args = {
        logger => $logger,
        forks => {US => 1},
        servers => {US => ['localhost']},
        per_server => {US => 1},
        servers_to_use => {},
        country_code => 'US',
        script => '/bin/echo',
    };

    my $c = CLI::Cluster->new($args);
    isa_ok($c, 'CLI::Cluster');
    #warn Data::Dumper->Dump([$c],['c']),"\n";

    my $run = 'run000';
    $c->params({$run => '--false--'});
    $c->ssh('/bin/false');
    $SIG{CHLD} = $c->sigchld_handler;

    my ($result, $err, $stdout, $stderr) = capture_output( 
        sub {
            my $pid = $c->fork_process($run, 'localhost');
            #warn "waiting for $pid\n";
            while (kill 0, $pid) { sleep(1); } # wait for child to terminate
            return $c->child_status->{$pid};
        }
    );

    die $err if $err;
    my $status = WEXITSTATUS($result);
    is($status, 1, 'exit status');
    like($die_log, qr/^sigchld_handler: Process\(\d+\) run000\@localhost Failed$/, 'die message');
    $logger->called_ok('logdie');
    is($stderr, '', 'STDERR');
    is($stdout, '', 'STDOUT');
}


# Run a some code while capturing the STDOUT and STDERR it produces to temporary files
sub capture_output {
    my $code = shift;

    # save current handles
    open my $oldout, ">&STDOUT" or die "Can't dup STDOUT: $!";
    open my $olderr, ">&STDOUT" or die "Can't dup STDERR: $!";

    close STDOUT or die "Can't close STDOUT: $!\n";
    close STDERR or die "Can't close STDERR: $!\n";

    # open file handles
    my $stdout_file = "/tmp/$$.stdout";
    open STDOUT, '>', $stdout_file or die "$stdout_file: Can't redirect STDOUT: $!";
    my $stderr_file = "/tmp/$$.stderr";
    open STDERR, '>', $stderr_file or die "$stderr_file: Can't redirect STDERR: $!";

    # make unbuffered
    select STDERR; local($|) = 1;
    select STDOUT; local($|) = 1;

    # run the code
    my $result = eval { &$code };
    my $err = $@;

    # close
    close STDOUT or die "Can't close redirected STDOUT: $!\n";
    close STDERR or die "Can't close redirected STDERR: $!\n";

    # restore I/O
    open STDOUT, ">&", $oldout or die "Can't restore STDOUT: $!";
    open STDERR, ">&", $olderr or die "Can't restore STDERR: $!";

    sub _slurp {
        my $file = shift;
        local($/) = undef;
        open(my $in, '<', $file) or die "$file: can't open: $!\n";
        my $data = <$in>;
        close $in;
        unlink($file);
        return $data;
    };

    my $stdout = _slurp($stdout_file);
    my $stderr = _slurp($stderr_file);

    return ($result, $err, $stdout, $stderr);
}


} # BEGIN

