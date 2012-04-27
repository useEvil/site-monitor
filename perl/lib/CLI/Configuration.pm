# ----------------------------------------------------------------------------------------------- #
# CLI::Configuration
# Configuration.pm
# ----------------------------
# $Revision: 1.4 $
# $Date: 2003/01/22 00:56:51 $
# ----------------------------------------------------------------------------------------------- #
# DESCRIPTION OF FILE
#	Configuration.pm,  Configuration Class.
# ----------------------------------------------------------------------------------------------- #
package CLI::Configuration;

=head1 NAME

CLI::Configuration

=head1 SYNOPSIS

 use CLI::Configuration;
 my $conf = CLI::Configuration->new(  );

=head1 DESCRIPTION

The class handles the confirguration of the script.

=head1 EXPORTS

Nothing

=cut

use Carp;
use strict;
use YAML;
use Class::Accessor::Fast;
use Scalar::Util qw(reftype);
use Gandolfini::Utility::PwdEncoding;
use Gandolfini::Utility::ConfInit;
use File::Spec;
use Hash::Merge::Simple;
use MIME::Base64 ();
use Storable;

# ----------------------------------------------------------------------------------------------- #

our ($VERSION, @ISA);
use constant DEBUG_NONE     => 0b00000000;
use constant DEBUG_WARN     => 0b00000001;
use constant DEBUG_DUMPER   => 0b00000010;
use constant DEBUG_TRACE    => 0b00000100;
use constant DEBUG_INIT     => 0b00001000;
use constant DEBUG_SUBCLASS => 0b00010000;
use constant DEBUG_TEST     => 0b00100000;
use constant DEBUG_ALL      => 0b00111111;
use constant DEBUG =>
  DEBUG_NONE;    # | DEBUG_WARN | DEBUG_DUMPER | DEBUG_TRACE | DEBUG_INIT | DEBUG_SUBCLASS | DEBUG_TEST | DEBUG_ALL;

use constant FIELDS => [qw(env)];

use base qw(Class::Accessor::Fast);

# ----------------------------------------------------------------------------------------------- #

BEGIN {
    $VERSION = do { my @REV = split(/\./, (qw$Revision: 1.8 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1] / 1000)) };
    __PACKAGE__->mk_accessors(@{FIELDS()});
}

# ----------------------------------------------------------------------------------------------- #


sub CONSTANTS { }

=head1 CONSTANTS

=over 4

=item C<DEPLOY>

Maps environment arg to deploy mode.

=cut

use constant DEPLOY => {
    dev  => 'DEPLOY_DEV',
    qa   => 'DEPLOY_QA',
    prod => 'DEPLOY_PR',
};

# ----------------------------------------------------------------------------------------------- #

sub CONSTRUCTORS { }

=back

=head1 METHODS

=head2 CONSTRUCTORS

=over 4

=item C<new> ( \%data )

=cut

sub new {
    my $self = shift;
    my $class = ref($self) || $self;
    my $self  = $class->SUPER::new(@_);
    $self->env('dev') unless ($self->env);
    return $self;
}    # END of new


# ----------------------------------------------------------------------------------------------- #

sub INITIALIZATION_METHODS { }

=back

=head2 INITIALIZATION METHODS

=over 4

=item C<init> ( $filename )

Takes a list of Constants and creates a virtual method.

=cut

sub init {
    my $self = shift;
    my $class = ref($self) || $self;
    my $file  = shift || 'configuration.yaml';

    my $conf  = YAML::LoadFile($file) or do { warn "$!" if (DEBUG & DEBUG_INIT); return; };

    return $self->generate_accessors($conf);
}


# This method supplants init().
# It adds the following additional features:
# -A new argument to specify a list of directories where config files can be found.
# -The passed config file is an array reference of one or more config files.
# -If config files do not have an absolute path, they are looked for in the config dirs.
sub load {
    my $self = shift;
    my %args = @_;

    my $files  = $args{files} || []; # optional; array ref; list of files to load
    my $dirs   = $args{dirs}  || []; # optional; array ref; list of directories to search for config files
    my $config = $args{config};      # optional; hash ref; programmatically set config defaults
    my $env    = $args{env};         # optional; CLI::Environment object; allow command line to override config file
    my $logger = $args{logger};      # optional; logger object

    my $merged_conf = CLI::Getopt::Conf->load(
        files => $files, 
        dirs => $dirs, 
        config => $config, 
        command_line => $env->as_hash, 
        logger => $logger,
    );
    #warn Data::Dumper->Dump([$merged_conf],['final-merged_conf']);

    return $self->generate_accessors($merged_conf);
}


# Given a hash following the structure below, generate accessor methods 
# attached to the current CLI::Configuration object for the 
# top level keys.
sub generate_accessors {
    my $self = shift;
    my $conf = shift;

    #warn Data::Dumper->Dump([$conf],['generate_accessors:conf']);

    # process the config structure, and turn each parameter into a method.
    # The config structure follows this pattern:
    #
    # configure:
    #  <parameter>:
    #    description: <human readable description of parameter>
    #    value:
    #      dev: <dev_value>
    #      qa:  <qa_value>
    #      prod: <prod_value>
    #
    # All configs have a 'configure' root node (now optional). That's followed 
    # by a <parameter> sub-key, each of which may have a 'description' sub-key 
    # describing the parameter, and each must have a 'value' sub-key. If the 
    # contents of 'value' is a hash, and it has a key that is one of 'dev', 
    # 'qa', or 'prod', then only the appropriate value for the current 
    # run-mode will be used. Otherwise the contents of the 'value' key is 
    # returned by $config-><parameter> accessor.
    my $run_mode = $self->env;
    while (my ($cname, $cdata) = each(%{$conf})) {
        #warn Data::Dumper->Dump([$cdata],[$cname]),"\n";
        # We expect $cdata to be a hash ref with a 'value' key, but if not
        # just use whatever $cdata is as the value
        my $value = ref($cdata) eq 'HASH' && exists $cdata->{'value'}
            ? $cdata->{'value'}
            : $cdata;
        # if $value is a hash ref and has a key matching the current run mode...
        if ((reftype($value) eq 'HASH') && exists($value->{$run_mode})) {
            $self->_accessor_method_init($cname, $value->{$run_mode});
        } else {
            $self->_accessor_method_init($cname, $value);
        }
    }

    return 1;
}


# ----------------------------------------------------------------------------------------------- #

sub OBJECT_METHODS { }

=back

=head2 OBJECT METHODS

=over 4

=item C<get_dbh_file> ()

Returns the dbh file path.

=cut

sub get_dbh_file {
    my $self = shift;

    return $self->dbh_file;
}


=item C<get_auth_file> ()

Returns the auth file path.

=cut

sub get_auth_file {
    my $self = shift;

    return $self->auth_file;
}


=item C<load_encoded_file> ( $dbh_file, $auth_file )

Returns the yaml content for the given dbh and auth files.

=cut

sub load_encoded_file {
    my $self = shift;
    my $dbh_files = shift or die __PACKAGE__,"->load_encoded_file: dbh_files: required\n";
    my $auth_file = shift or die __PACKAGE__,"->load_encoded_file: auth_file: required\n";
    my $env       = shift; # optional; CLI::Environment object; allow command line to override config file;
    my $logger    = shift; # optional; logger object

    # promote to array ref, if needed
    $dbh_files = [$dbh_files] if ref($dbh_files) ne 'ARRAY';

    my $dbh = CLI::Getopt::Conf->clean_load(command_line => $env->as_hash, files => $dbh_files, logger => $logger);
    #warn Data::Dumper->Dump([$dbh],['dbh']),"\n";

    my $auth = CLI::Getopt::Conf->clean_load(command_line => $env->as_hash, files => [$auth_file], logger => $logger);
    #warn Data::Dumper->Dump([$auth],['auth']),"\n";

    # code borrowed from Gandolfini::Utility::PwdEncoding
    # walk the db_aliases hash and substitute all usernames and passwords with decoded passwords from $auth.
    my $aliases  = $dbh->{db_aliases};
    foreach my $alias_key (keys %$aliases) {
        my $dbh_alias  = $aliases->{$alias_key};
        my $auth_alias = $auth->{db_aliases}->{$alias_key};

        # skip this alias unless there are credentials for it in the $auth structure
        next if !$auth_alias;

        # iterate over entries within the alias
        foreach my $index (0 .. $#{$auth_alias}) {
            my $dbh_entry  = $dbh_alias->[$index];
            my $auth_entry = $auth_alias->[$index];

            # grab and decode the auth values
            my $username  = $auth_entry->{username};
            my $encoded   = $auth_entry->{password};
            my $plaintext = $self->_decode($encoded);

            # merge the new user/pass into the dbh structure
            $dbh_entry->{username} = $username;
            $dbh_entry->{password} = $plaintext;
        }
    }
    #warn Data::Dumper->Dump([$dbh],['dbh']),"\n";

    return $dbh;
}

# helper for load_encoded_file()
sub _decode {
    my $self = shift;
    my $value = shift or return '';
    return MIME::Base64::decode_base64($value);
}


=item C<is_deploy_mode> ( $mode [, $env ] )

Returns the yaml content for the given dbh and auth files.

=cut

sub is_deploy_mode {
    my $self = shift;
    my $mode = shift || return;
    my $env  = shift || ref($self) ? $self->env : 'dev';
    warn __PACKAGE__ . "->load_encoded_file: mode[${mode}] env[${env}]\n" if (DEBUG & DEBUG_TEST);
    return ($mode eq DEPLOY->{$env});
}    # END of is_deploy_mode


# ----------------------------------------------------------------------------------------------- #

sub STATIC_METHODS { }

=back

=head2 STATIC METHODS

=over 4

=item C<conf_init> ( $env )

Initializes the application using Gandolfini::Utility::ConfInit::init.

=cut

sub conf_init {
    my $self = shift;
    my $env  = shift;
    ## Initialize Configuration for Hackman ##
    Gandolfini::Utility::ConfInit::init(
        sub {
            my $flag = shift;
            return $self->is_deploy_mode($flag, $env);
        }
    );
}    # END of conf_init


# ----------------------------------------------------------------------------------------------- #

sub PROTECTED_METHODS { }

=back

=head2 PROTECTED METHODS

These methods should only be used by CLI::Configuration.

=over 4

=cut

sub _accessor_method_init {
    my $self  = shift;
    my $class  = ref($self) || $self;
    my $method = shift;
    my $value = shift;

    if ($class->can($method)) {
        warn 'Not creating ' . $class . '::' . $method . ", as it already exists.\n" if (DEBUG & DEBUG_SUBCLASS);
        return;
    }

    warn __PACKAGE__ . "->_accessor_method_init: " . Data::Dumper->Dump([$value],[$method]) . "]\n" if (DEBUG & DEBUG_INIT);
    $self->{conf}->{$method} = $value; # add the key/val to the config object

    {    
        no strict 'refs';
        *{"${class}::$method"} = sub {
            my $self = shift;
            return (carp "$method must be called against an object" && undef) unless (ref $self);
            return $self->{conf}->{$method};
        };
    }

    return 1;
}    # END of _accessor_method_init


# Hack to regenerate accessors after object is de-serialized by Class::Remote
sub STORABLE_thaw {
    my $self = shift; # empty object
    my $cloning = shift; # cloning flag
    my $serialized = shift; # the serialized contents of the object

    #warn __PACKAGE__,"->STORABLE_thaw: thawing\n";
    %$self = %{ Storable::thaw($serialized) }; # repopulate object
    $self->generate_accessors($self->{conf}); # regenerate dynamic accessors
}

# Performs default serialization, but needed in order for STORABLE_thaw hook to be used
sub STORABLE_freeze {
    my $self = shift;
    my $cloning = shift;

    #warn __PACKAGE__,"->STORABLE_freeze: _freezeing.\n";
    return Storable::freeze({%$self});
}

# ----------------------------------------------------------------------------------------------- #

# Subclass Search's Getopt::Conf
package CLI::Getopt::Conf;

use base 'Getopt::Conf';

sub command_line { return {} } # override; Publisher CLI doesn't mix command line and config vars
sub default_file_names { }     # override; Publisher CLI doesn't use defaults.yml
sub load {                     # alias new method to old name
    my $class = shift;
    my %args = @_;

    # accomodate logging; using a localized global as there is no place to stash class state
    local $class::LOGGER = delete $args{logger};

    return $class->load2(%args);
}
# override; add logging
sub config_file_names {
    my $class = shift;
    my $files = $class->SUPER::config_file_names(@_);
    $class::LOGGER->info("Configuration file(s): " . join(':',@$files)) if $class::LOGGER;
    return $files;
}
# override; add logging
sub config_dirs {
    my $class = shift;
    my $dirs = $class->SUPER::config_dirs(@_);
    $class::LOGGER->info("Configuration dir(s): " . join(':',@$dirs)) if $class::LOGGER;
    return $dirs;
}
# override; add logging
sub load_file {
    my $class = shift;
    my $file  = shift;
    $class::LOGGER->info("$file: loading...") if $class::LOGGER;
    return $class->SUPER::load_file($file);
}
# override; eliminate the optional and useless 'configure' root node
sub yaml_merge {
    my $class = shift;

    @_ = map {
        # eliminate the optional and useless 'configure' root node
        $_ = exists $_->{'configure'} ? $_->{'configure'} : $_;
    } @_;

    return $class->SUPER::yaml_merge(@_);
}


1;

__END__

=back

=head1 REVISION HISTORY

 $Log: Configuration.pm,v $

=head1 SEE ALSO

L<perl>

=head1 KNOWN BUGS

None

=head1 AUTHOR

Thai Nguyen <thai@shozilla.com>

=cut
