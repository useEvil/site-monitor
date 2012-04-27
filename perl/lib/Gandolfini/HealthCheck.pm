# ---------------------------------------------------------
# Gandolfini::HealthCheck
# HealthCheck.pm
# -----------------
# $Revision: 1584 $
# $Date: 2006-12-18 13:16:03 -0800 (Mon, 18 Dec 2006) $
# ---------------------------------------------------------

package Gandolfini::HealthCheck;

=head1 NAME

Gandolfini::HealthCheck

=head1 SYNOPSIS
 
=head1 DESCRIPTION

=head1 REQUIRES

=cut

use Carp;
use strict;
use YAML;
use Gandolfini::Utility::ConfInit;

######################################################################

our ($VERSION);
use constant DEBUG_NONE		=> 0b00000000;
use constant DEBUG_WARN		=> 0b00000001;
use constant DEBUG_DUMPER	=> 0b00000010;
use constant DEBUG_TRACE	=> 0b00000100;
use constant DEBUG_INIT		=> 0b00001000;
use constant DEBUG_SUBCLASS	=> 0b00010000;
use constant DEBUG_TEST		=> 0b00100000;
use constant DEBUG_ALL		=> 0b00111111;
use constant DEBUG			=> DEBUG_NONE;# | DEBUG_WARN | DEBUG_DUMPER | DEBUG_TRACE | DEBUG_INIT | DEBUG_SUBCLASS | DEBUG_TEST | DEBUG_ALL;

BEGIN {
	$VERSION	= do { my @REV = split(/\./, (qw$Revision: 1584 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
}

######################################################################

sub CONSTANTS { }

=head1 CONSTANTS

=cut


sub CONSTRUCTORS { }

=head1 METHODS

=head2 CONSTRUCTORS

=over 4

=cut


sub INITIALIZATION_METHODS { }

=back

=head2 INITIALIZATION METHODS

=over 4

=cut


sub OBJECT_METHODS { }

=back

=head2 OBJECT METHODS

=over 4

=cut


sub STATIC_METHODS { }

=back

=head2 STATIC METHODS

=over 4

=item C<health_check> ( $filename [, $desc ] )

Parses the health check yaml file and sends the params to the corresponding resource methods.

=cut

sub health_check {
	my $self	= shift;
	my $class	= ref($self) || $self;
	my $file	= shift || 'conf/gandolfini_health_check.yaml';
	my $desc	= shift;
	my $conf	= YAML::LoadFile( $file ) or do { warn "$!" if (DEBUG & DEBUG_WARN); return undef; };
	warn __PACKAGE__ . "->health_check: file[${file}]\n" if (DEBUG & DEBUG_WARN);
	my $failed	= 0;
	while (my($cname, $cdata) = each(%{ $conf->{'configure'} })) {
		$failed	+= $class->_check_method_init( $cname, $cdata, $desc );
	}
	return $failed;
} # END of health_check


=item C<dbh> ( $cdata [, $desc ] )

Resource method that executes database calls using either the Business or Data 
classes.  eval{ } is used to execute the class method.

=cut

sub dbh {
	my $self	= shift;
	my $cdata	= shift || return undef;
	my $desc	= shift;
	warn __PACKAGE__ . "->dbh: desc[${desc}]\n" if (DEBUG & DEBUG_WARN);
	warn __PACKAGE__ . '->dbh: ' . Data::Dumper::Dumper( $cdata ) if (DEBUG & DEBUG_DUMPER);
	my $failed	= 0;
	foreach my $key (keys %$cdata) {
		my $data	= $cdata->{$key};
		my $class	= $data->{'class'} || return undef;
		warn __PACKAGE__ . "->db_query: class[${class}] dbh[${key}]\n" if (DEBUG & DEBUG_WARN);
		my $dbh		= $class->_dbh( $key );
		eval { $dbh->quote( 'OK' ); };
		print "DBH Check:                 [" . ($@ ? 'Failed' : 'OK') . "]\n";
#		print "DBH Check:                 [" . (ref($result) ? 'OK' : 'Failed') . "]\n";
		print '    ' . $data->{'description'} . "\n\n" if (isDeployMode( SZ_DEPLOY_DEV ) || $desc);
		$failed++ if ($@);
	}
	return $failed;
} # END of dbh


=item C<db_query> ( $cdata [, $desc ] )

Resource method that executes database calls using either the Business or Data 
classes.  eval{ } is used to execute the class method.

=cut

sub db_query {
	my $self	= shift;
	my $cdata	= shift || return undef;
	my $desc	= shift;
	warn __PACKAGE__ . "->db_query: desc[${desc}]\n" if (DEBUG & DEBUG_WARN);
	warn __PACKAGE__ . '->db_query: ' . Data::Dumper::Dumper( $cdata ) if (DEBUG & DEBUG_DUMPER);
	my $failed	= 0;
	foreach my $key (keys %$cdata) {
		my $data	= $cdata->{$key};
		my $class	= $data->{'class'}	|| return undef;
		my $method	= $data->{'method'}	|| return undef;
		my $params	= $data->{'params'}	|| '';
		warn __PACKAGE__ . "->db_query: class[${class}] method[${method}] params[${params}]\n" if (DEBUG & DEBUG_WARN);
		eval { $class->$method( split(/,/, $params) ); };
		print "DB Query:                  [" . ($@ ? 'Failed' : 'OK') . "]\n";
		print '    ' . $data->{'description'} . "\n\n" if (isDeployMode( SZ_DEPLOY_DEV ) || $desc);
		$failed++ if ($@);
	}
	return $failed;
} # END of db_query


=item C<slu> ( $cdata [, $desc ] )

Resource method to execute the SLU Search Engine API using the Business class 
method.  The method returns values for success and failuers.  This might not 
work for the consumer site, the API to the Search Engine is different.

=cut

sub slu {
	my $self	= shift;
	my $cdata	= shift || return undef;
	my $desc	= shift;
	warn __PACKAGE__ . "->slu: desc[${desc}]\n" if (DEBUG & DEBUG_WARN);
	warn __PACKAGE__ . '->slu: ' . Data::Dumper::Dumper( $cdata ) if (DEBUG & DEBUG_DUMPER);
	my $failed	= 0;
	foreach my $key (keys %$cdata) {
		my $data	= $cdata->{$key};
		my $class	= $data->{'class'}	|| return undef;
		my $method	= $data->{'method'}	|| return undef;
		my $params	= $data->{'params'}	|| [ ];
		my %args	= (ref($params) eq 'HASH') ? %{ $params } : map { %$_ } @$params;
		warn __PACKAGE__ . "->slu: class[${class}] method[${method}]\n" if (DEBUG & DEBUG_WARN);
		warn __PACKAGE__ . '->slu: ' . Data::Dumper::Dumper( \%args ) if (DEBUG & DEBUG_DUMPER);
		my $result	= $class->$method( \%args );
		print "SLU Server Query:          [" . (($result < 0) ? 'Failed' : 'OK') . "]\n";
		print '    ' . $data->{'description'} . "\n\n" if (isDeployMode( SZ_DEPLOY_DEV ) || $desc);
		$failed++ if ($result < 0);
	}
	return $failed;
} # END of slu


=item C<smtp> ( $cdata [, $desc ] )

Resource method to send mail using the API to the Net::SMTP module.

=cut

sub smtp {
	my $self	= shift;
	my $cdata	= shift || return undef;
	my $desc	= shift;
	warn __PACKAGE__ . "->smtp: desc[${desc}]\n" if (DEBUG & DEBUG_WARN);
	warn __PACKAGE__ . '->smtp: ' . Data::Dumper::Dumper( $cdata ) if (DEBUG & DEBUG_DUMPER);
	my $failed	= 0;
	foreach my $key (keys %$cdata) {
		my $data	= $cdata->{$key};
		my $class	= $data->{'class'}	|| return undef;
		my $method	= $data->{'method'}	|| return undef;
		my $params	= $data->{'params'}	|| [ ];
		my %args	= (ref($params) eq 'HASH') ? %{ $params } : map { %$_ } @$params;
		warn __PACKAGE__ . "->smtp: class[${class}] method[${method}]\n" if (DEBUG & DEBUG_WARN);
		warn __PACKAGE__ . '->smtp: ' . Data::Dumper::Dumper( \%args ) if (DEBUG & DEBUG_DUMPER);
		my $result	= $class->$method( $args{'server'}, $args{'email'}, $args{'email'}, $args{'subject'}, $args{'body'}, $args{'email'} );
		print "SMTP email:                [" . ($result ? 'OK' : 'Failed') . "]\n";
		print '    ' . $data->{'description'} . ' [' . $args{'server'} . "]\n\n" if (isDeployMode( SZ_DEPLOY_DEV ) || $desc);
		$failed++ unless ($result);
	}
	return $failed;
} # END of smtp


=item C<annuncio> ( $cdata [, $desc ] )

Resource method to execute the LiveWire call for Annuncio.  Uses LWP to execute 
the call.

=cut

sub annuncio {
	my $self	= shift;
	my $cdata	= shift || return undef;
	my $desc	= shift;
	warn __PACKAGE__ . "->annuncio: desc[${desc}]\n" if (DEBUG & DEBUG_WARN);
	warn __PACKAGE__ . '->annuncio: ' . Data::Dumper::Dumper( $cdata ) if (DEBUG & DEBUG_DUMPER);
	my $failed	= 0;
	foreach my $key (keys %$cdata) {
		my $data	= $cdata->{$key};
		my $class	= $data->{'class'}	|| return undef;
		my $method	= $data->{'method'}	|| return undef;
		my $params	= $data->{'params'}	|| [ ];
		my %args	= (ref($params) eq 'HASH') ? %{ $params } : map { %$_ } @$params;
		warn __PACKAGE__ . "->annuncio: class[${class}] method[${method}]\n" if (DEBUG & DEBUG_WARN);
		warn __PACKAGE__ . '->annuncio: ' . Data::Dumper::Dumper( \%args ) if (DEBUG & DEBUG_DUMPER);
		my $result	= $class->$method( \%args );
		print "Annuncio LiveWire Call:    [" . ($result ? 'OK' : 'Failed') . "]\n";
		print '    ' . $data->{'description'} . "\n\n" if (isDeployMode( SZ_DEPLOY_DEV ) || $desc);
		$failed++ unless ($result);
	}
	return $failed;
} # END of annuncio


=item C<vat_validation> ( $cdata [, $desc ] )

Resource method to execute the LiveWire call for Annuncio.  Uses LWP to execute 
the call.

=cut

sub vat_validation {
	my $self	= shift;
	my $cdata	= shift || return undef;
	my $desc	= shift;
	warn __PACKAGE__ . "->vat_validation: desc[${desc}]\n" if (DEBUG & DEBUG_WARN);
	warn __PACKAGE__ . '->vat_validation: ' . Data::Dumper::Dumper( $cdata ) if (DEBUG & DEBUG_DUMPER);
	## only run once per hour ##
	my $date	= Gandolfini::Date->new;
	return undef unless (($date->min > 7) && ($date->min < 21));
	use Business::Tax::VAT::Validation;
	my $valid	= new Business::Tax::VAT::Validation;
	my $failed	= 0;
	foreach my $key (keys %$cdata) {
		my $data	= $cdata->{$key};
		my $class	= $data->{'class'}	|| return undef;
		my $method	= $data->{'method'}	|| return undef;
		my $params	= $data->{'params'}	|| return undef;
		warn __PACKAGE__ . "->vat_validation: class[${class}] method[${method}] params[${params}]\n" if (DEBUG & DEBUG_WARN);
		my $result	= '';
		if ($valid->check( split(/,/, $params) )) {
			$result	= 'OK';
		} else {
			$result	= 'Failed';
			warn warn __PACKAGE__ . '->vat_validation:' . $valid->get_last_error . "\n";
			$failed++;
		}
		print "VAT Validation:            [${result}]\n";
		print '    ' . $data->{'description'} . "\n\n" if (isDeployMode( SZ_DEPLOY_DEV ) || $desc);
	}
	return $failed;
} # END of vat_validation


=item C<corda> ( $cdata [, $desc ] )

Resource method to execute the image creator for Corda.  Uses LWP to execute the call.

=cut

sub corda {
	my $self	= shift;
	my $cdata	= shift || return undef;
	my $desc	= shift;
	warn __PACKAGE__ . "->corda: desc[${desc}]\n" if (DEBUG & DEBUG_WARN);
	warn __PACKAGE__ . '->corda: ' . Data::Dumper::Dumper( $cdata ) if (DEBUG & DEBUG_DUMPER);
	## only run once per hour ##
#	my $date	= Gandolfini::Date->new;
#	return undef unless (($date->min > 0) && ($date->min < 15));
	my $failed	= 0;
	foreach my $key (keys %$cdata) {
		my $data	= $cdata->{$key};
		my $class	= $data->{'class'}	|| return undef;
		my $method	= $data->{'method'}	|| return undef;
		my $params	= $data->{'params'}	|| [ ];
		my %args	= (ref($params) eq 'HASH') ? %{ $params } : map { %$_ } @$params;
		warn __PACKAGE__ . "->corda: class[${class}] method[${method}]\n" if (DEBUG & DEBUG_WARN);
		warn __PACKAGE__ . '->corda: ' . Data::Dumper::Dumper( \%args ) if (DEBUG & DEBUG_DUMPER);
		my $result	= $class->$method( $args{'url'} );
		print "Corda Call:                [" . ($result->is_success ? 'OK' : 'Failed') . "]\n";
		print '    ' . $data->{'description'} . "\n\n" if (isDeployMode( SZ_DEPLOY_DEV ) || $desc);
		$failed++ unless ($result->is_success);
	}
	return ($failed > 1) ? $failed : 0;
} # END of corda


sub PROTECTED_METHODS { }

=back

=head2 PROTECTED METHODS

These methods should only be used by Gandolfini::HealthCheck.

=over 4

=cut

=item C<_check_method_init> ( $cname, $cdata [, $desc ] )

Executes the virtual methods for the Health Check configuration.

=cut


sub _check_method_init {
	my $self	= shift;
	my $class	= ref($self) || $self;
	my $method	= shift;
	my $cdata	= shift;
	my $desc	= shift;
	warn __PACKAGE__ . "->_check_method_init: method[${method}]\n" if (DEBUG & DEBUG_INIT);
	return $self->$method( $cdata, $desc );
} # END of _check_method_init



1;

__END__

=back

=head1 REVISION HISTORY

 $Log$
 Revision 1.9  2005/09/12 23:44:41  thai
  - removed time condition

 Revision 1.8  2005/09/12 23:36:25  thai
  - added corda service

 Revision 1.7  2005/06/23 22:09:59  thai
  - added Apache->define() for descriptions

 Revision 1.6  2005/06/15 23:58:10  thai
  - updated code to return an accumulated total of failures

 Revision 1.5  2005/06/02 19:38:02  thai
  - changed check for dbh()

 Revision 1.4  2005/05/13 00:14:55  thai
  - changed print statements

 Revision 1.3  2005/05/13 00:04:14  thai
  - added vat_validation() method to check VAT validation website

 Revision 1.2  2005/04/13 21:59:47  thai
  - added db_query() to distinguish it from dbh()

 Revision 1.1  2005/04/07 23:31:16  thai
  - new base Health Check module


=head1 AUTHOR

Thai Nguyen <thai@shozilla.com>

=cut
