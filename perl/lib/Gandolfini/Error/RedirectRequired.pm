=head1 NAME

Gandolfini::Error::RedirectRequired - Redirect to another URL

=head1 SYNOPSIS

 use Gandolfini::Error::RedirectRequired;
 sub do_stuff {
     # issue a permanent redirect
     Gandolfini::Error::RedirectRequired->throw('http://www.foobar.com', 301);
 }

 # later, inside of an apache handler....
 use Error ':try';
 my $r = Apache->request;
 my $do_redirect = 0;
 try {
     do_stuff();
 } catch Gandolfini::Error::RedirectRequired with {
     my $e = shift;
     $r->status($e->status);
     $r->header_out(Location => $e->location);
     $do_redirect = 1;
 };
 return REDIRECT if $do_redirect;

=head1 DESCRIPTION

Throw this exception when you want to trigger an HTTP redirect.
An exception is useful for this purpose because you can catch it
in a top-level handler. Then you can simply throw the exception
anywhere below that handler to climb back up the stack to the
place where the exception is caught, making a redirect practical.

=cut

package Gandolfini::Error::RedirectRequired;
use warnings;
use strict;
use base qw(Gandolfini::Error);

=head2 CLASS METHODS

=item new ( URL [, HTTP_CODE ] )

URL is the destination of the redirect, with the redirect code HTTP_CODE.
If no redirect code is provided it defaults to 302 (REDIRECT).

This method is used internally when this exception is thrown, it should
not be necessary to call it in client code. Throw will pass the arguments
to new unmodified.

=cut

sub new {
    my ($class, $url, $http_code) = @_;
    warn 'Missing or empty redirect target' unless $url;
    my $self = $class->SUPER::new( -text => "redirect required: $url", -value => $url );
    $self->{_http_code} = $http_code || 302;
    return $self;
}

=head2 OBJECT METHODS

=item location

Returns the destination URL.

=item status

Returns the HTTP status code.

=cut

sub location { shift->value; }

sub status { shift->{_http_code}; }

1;

