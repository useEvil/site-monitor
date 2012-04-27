=head1 DESCRIPTION

Class used currently for digesting affiliate stuff.

=cut

package Gandolfini::Affiliate::Auth;
use strict;

use constant DEBUG_NONE		=> 0b00000000;
use constant DEBUG_WARN		=> 0b00000001;
use constant DEBUG_DUMPER	=> 0b00000010;

use Digest::HMAC;
use Digest::SHA1;
use Gandolfini::Error;

use constant HMAC_HASH_METHOD => 'Digest::SHA1';
use constant AFFILIATE_SECRET => 'This is a really long 223923829382 key';

sub new {
    my $class = shift;
    return bless({}, $class);
}

sub is_valid_digest {
	my ($self, $aid, $callid, $digest) = @_;
	if ($self->digest_params($aid, $callid) eq $digest) {
		return 1;
	}
	return 0;
}

sub digest_params {
    my ($self, $aid, $callid) = @_;

    if ( not defined $aid || not defined $callid ) {
        Gandolfini::MethodError->throw->(
            -text => "Can't call hash_affiliate_params without aid or callid"
        );
    }
    return $self->_digest_data_array($aid . $callid);

}

sub _digest_data_array {
    my ($self, $data) = @_;
    my $hmac = Digest::HMAC->new(AFFILIATE_SECRET, HMAC_HASH_METHOD);
    $hmac->add($data);
    return $hmac->b64digest();
}


1;

__END__

=head1 AUTHOR

  Amos Elliston <aelliston@shopzilla.com>

=cut
