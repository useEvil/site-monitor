=head1 NAME

Gandolfini::Utility::ConfInit


=cut

package Gandolfini::Utility::ConfInit;

=head1 SYNOPSIS


Gandolfini::Utility::ConfInit->init();

=head1 DESCRIPTION


Configuration wrapper.  Should be initialized at application start up.  
Exposes configuration parameters for code that needs to know which
deployment and colo mode the current server is running under.

=cut

use strict;
use warnings;
use Sys::Hostname;
use Carp qw/carp/;

######################################################################

use constant SZ_DEPLOY_DEV => 'DEPLOY_DEV';
use constant SZ_DEPLOY_QA => 'DEPLOY_QA';
use constant SZ_DEPLOY_PR => 'DEPLOY_PR';

use constant SZ_COLO_DEV => 'COLO_DEV';
use constant SZ_COLO_DEV_QA => 'COLO_DEV_QA';
use constant SZ_COLO_QA => 'COLO_QA';
use constant SZ_COLO_LAX => 'COLO_LAX';
use constant SZ_COLO_LAX2 => 'COLO_LAX2';
use constant SZ_COLO_HOU => 'COLO_HOU';
use constant SZ_COLO_SEA => 'COLO_SEA';
use constant SZ_COLO_HQ => 'COLO_HQ';

# These should only be 2 digits
use constant SZ_COLO_LAX_NUM => 0;
use constant SZ_COLO_HOU_NUM => 1;
use constant SZ_COLO_LAX2_NUM => 2;
use constant SZ_COLO_HQ_NUM => 90;
use constant SZ_COLO_QA_NUM => 95;
use constant SZ_COLO_DEV_NUM => 99;
use constant SZ_COLO_SEA_NUM => 3;

our $SILENT_INIT = undef();

my $isInitialized = 0;

my $DeployMode;
my $ColoMode;
my $ColoNum;
my $SiloNum;
my $ColoConfDir;
my %ColoConfDirHash;
my %ColoNumHash;

BEGIN {
	use vars qw(@EXPORT);
	@EXPORT = qw(
				SZ_DEPLOY_DEV
				SZ_DEPLOY_QA
				SZ_DEPLOY_PR
				
				SZ_COLO_DEV
				SZ_COLO_DEV_QA
				SZ_COLO_QA
				SZ_COLO_LAX
				SZ_COLO_LAX2
				SZ_COLO_HOU
				SZ_COLO_SEA
				SZ_COLO_HQ
				
				getDeployMode
				getColoMode
				getColoConfDir
				getColoNum
				getSiloNum
				isDeployMode
				isColoMode
				dumpConfig
				);
				
	use base 'Exporter';
}

######################################################################


=head1 METHODS

=over 4

=item C<init> ( \&_testDefined)

Static initialization for application deploy and colo mode.  
It makes a decision using the hostname and the presence of defined flags, 
as returned by a passed-in &_testDefined subroutine.  Typically, this subroutine
will test for command-line startup flags passed to the application, via the -D directive.

For example, within Apache1:

	Gandolfini::Utility::ConfInit::init(
                sub {
                    my $flag = shift;
                    return Apache->define($flag);
                });	

Or, within Apache2

	Gandolfini::Utility::ConfInit::init( 
                sub {
                    my $flag = shift;
                    return Apache2::ServerUtil::exists_config_define($flag);
                });
					
=cut

sub init {
	my $_testDefined = shift;
	
	my $my_hostname;
	
	my @deployment_modes = (SZ_DEPLOY_DEV,
							SZ_DEPLOY_QA,
							SZ_DEPLOY_PR);
	my $dmodect = 0;
	my $dmode;
	
	foreach my $mode (@deployment_modes) {
		if (&$_testDefined($mode)) {
			$dmodect++;
			$dmode = $mode;
		}
	}

	if ($dmodect == 0) {
		die "Cannot start: no deployment mode specified!\n";
	} elsif ($dmodect > 1) {
		die "Cannot start: multiple deployment modes specified!\n";
	}


	# note 'HQCOLO' included in the list for back compatibility, should use COLO_HQ
	my @colo_modes = (SZ_COLO_LAX, 
						SZ_COLO_LAX2,
						SZ_COLO_HOU,
						SZ_COLO_SEA,
						SZ_COLO_HQ, 
						SZ_COLO_QA, 
						SZ_COLO_DEV, 
						'HQCOLO');
	my $coloct = 0;
	my $colo;
	my $colo_conf_dir;
	
	$SiloNum = 0;

	foreach my $mode (@colo_modes) {
		if (&$_testDefined($mode)) {
			$coloct++;
			$colo = $mode;
		}
	}

	if ($coloct == 0) {
		
		# ideally, we'd require one of the defined colo's, but for
		# backward compatibility, need to support that there might
		# not be anything specified.  So, need defaults, based on
		# mode selection.
		#
		if($dmode eq SZ_DEPLOY_DEV) {
			$colo = SZ_COLO_DEV;
		} elsif ($dmode eq SZ_DEPLOY_QA) {
			$colo = SZ_COLO_QA;
		} elsif ($dmode eq SZ_DEPLOY_PR) {
			#
			# see if this looks like a houston dante, otherwise it's an lax
			#	(this is a an unfortunate hack, which should be cleaned up,
			#		once Houston/Lax allow explicit colo mode on command line)
			#
			$my_hostname = Sys::Hostname->hostname();
			$my_hostname =~ /^.+?\.sl(\d+)\..+\.(\w+)$/;
			my $silonum = $1;
            my $top_level_domain = $2;
			if ($silonum && $top_level_domain eq 'hou') {
				$colo = SZ_COLO_HOU;
            } elsif ($silonum && $top_level_domain eq 'lax') {
				$colo = SZ_COLO_LAX2;
			} elsif ($silonum && $top_level_domain eq 'sea') {
				$colo = SZ_COLO_SEA;
			} else {
				$colo = SZ_COLO_LAX;
			}
		} else {
			die "Cannot start: no colo mode specified, and no default mapping available for deployment mode $dmode";
		}
	} 
	elsif ($dmodect > 1) {
		die "Cannot start: multiple colo modes specified!\n";
	} 
	elsif ($colo eq 'HQCOLO') {
		# for bw compatibility
		$colo = SZ_COLO_HQ;
    }

	# some basic rule testing
	#  (dev and hq are the only colos allowed to mimic other deployments)
	if((($colo eq SZ_COLO_LAX) and ($dmode ne SZ_DEPLOY_PR)) or 
	            (($colo eq SZ_COLO_LAX2) and ($dmode ne SZ_DEPLOY_PR)) or 
				(($colo eq SZ_COLO_HOU) and ($dmode ne SZ_DEPLOY_PR))  or
				(($colo eq SZ_COLO_SEA) and ($dmode ne SZ_DEPLOY_PR))  or
				(($colo eq SZ_COLO_QA) and ($dmode ne SZ_DEPLOY_QA))) {

		die "Cannot start: deploy/colo combination not allowed: '" 
									. $colo . "' / '" . $dmode . ".";
	}
	
	# a simple lookup for colo conf dirs
	%ColoConfDirHash = (
		SZ_COLO_DEV, 'colo/dev',
		SZ_COLO_DEV_QA, 'colo/dev_qa', 
		SZ_COLO_QA, 'colo/qa',
		SZ_COLO_HQ, 'colo/hq',
		SZ_COLO_HOU, 'colo/hou',
		SZ_COLO_SEA, 'colo/sea',
		SZ_COLO_LAX, 'colo/lax',
        SZ_COLO_LAX2, 'colo/lax2');

	$ColoConfDir = $ColoConfDirHash{$colo};
	
	# a simple lookup for colo nums
	%ColoNumHash = (
		SZ_COLO_DEV, SZ_COLO_DEV_NUM,
		SZ_COLO_QA, SZ_COLO_QA_NUM,
		SZ_COLO_HQ, SZ_COLO_HQ_NUM,
		SZ_COLO_HOU, SZ_COLO_HOU_NUM,
		SZ_COLO_SEA, SZ_COLO_SEA_NUM,
		SZ_COLO_LAX, SZ_COLO_LAX_NUM,
		SZ_COLO_LAX2, SZ_COLO_LAX2_NUM);

	$ColoNum = $ColoNumHash{$colo};
	
	# look for a silo number
	$my_hostname = Sys::Hostname->hostname();
	$my_hostname =~ /^.+?\.sl(\d+)\..+\..+$/;
	my $silonum = $1;
	if($silonum) {
		$SiloNum = $silonum;
	}
			
	$DeployMode = $dmode;
	$ColoMode = $colo;
	
	$isInitialized = 1;
	
	dumpConfig("Beginning initialization with config:") unless $SILENT_INIT;
	
	return 1;
} # END of init

=item C<getDeployMode> ( )

Return current deploy mode.  Will be one of:

 SZ_DEPLOY_DEV
 SZ_DEPLOY_QA
 SZ_DEPLOY_PR

=cut

sub getDeployMode {
    
    if(!$isInitialized) {
        carp "Must call ConfInit::init prior to calling this method";
    }
    
	return $DeployMode;
}

=item C<isDeployMode>($deployMode)

Boolean function, tests whether the currently initialized deploy mode is equal to the passed in $deployMode.

=cut

sub isDeployMode {
    
    if(!$isInitialized) {
        carp "Must call ConfInit::init prior to calling this method";
    }
    
	my $testMode = shift;
	if($testMode eq $DeployMode) {
		return 1;
	} else {
		return 0;
	}
}

=item C<getColoMode> ( )

Return current colo mode.  Will be one of:

 SZ_COLO_DEV
 SZ_COLO_QA
 SZ_COLO_HOU
 SZ_COLO_LAX
 SZ_COLO_LAX2
 SZ_COLO_HQ

=cut

sub getColoMode {
    
    if(!$isInitialized) {
        carp "Must call ConfInit::init prior to calling this method";
    }
    
	return $ColoMode;
}

=item C<isColoMode>($coloMode)

Boolean function, tests whether the currently initialized colo mode is equal to the passed in $coloMode.

=cut

sub isColoMode {
    
    if(!$isInitialized) {
        carp "Must call ConfInit::init prior to calling this method";
    }
    
	my $testMode = shift;
	if($testMode eq $ColoMode) {
		return 1;
	} else {
		return 0;
	}
}

=item C<getColoConfDir> ($coloMode)

Return the corresponding colo specific conf sub-directory associated with the given $coloMode.  If no argument is provided, it will default to the currently initialized colo mode.

=cut

sub getColoConfDir {
    
    if(!$isInitialized) {
        carp "Must call ConfInit::init prior to calling this method";
    }
    
	my $coloMode = shift;
	if($coloMode) {
		return $ColoConfDirHash{$coloMode};
	}
	else {
		return $ColoConfDir;
	}
}

=item C<getColoNum> ($coloMode)

Return the corresponding colo number associated with the given $coloMode.  If no argument is provided, it will default to the currently initialized colo number.

=cut

sub getColoNum {
    
    if(!$isInitialized) {
        carp "Must call ConfInit::init prior to calling this method";
    }
    
	my $coloMode = shift;
	if($coloMode) {
		return $ColoNumHash{$coloMode};
	}
	else {
		return $ColoNum;
	}
}

=item C<getSiloNum> ()

Return the currently initialized silo number.  If no silos are in use, it returns 0.

=cut

sub getSiloNum {
    
    if(!$isInitialized) {
        carp "Must call ConfInit::init prior to calling this method";
    }
    
	return $SiloNum;
}

=item C<dumpConfig> (headerMessage)

Dump current config params, using 'warn', prefaced by optional headerMessage.

=cut

sub dumpConfig {
    
    if(!$isInitialized) {
        carp "Must call ConfInit::init prior to calling this method";
    }
    
	my $headerMessage = shift;
	if($headerMessage) {
		warn $headerMessage . "\n";
	}
	
	warn "	DeployMode = $DeployMode\n";
	warn "	ColoMode = $ColoMode\n";
	warn "	ColoConfDir = $ColoConfDir\n";
	warn "	ColoNum = $ColoNum\n";
	warn "	SiloNum = $SiloNum\n";
}


1;

__END__


=head1 AUTHOR

 Jason Rosenberg <jrosenberg@shopzilla.com>

=cut
