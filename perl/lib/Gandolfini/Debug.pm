# Gandolfini::Debug
# -------------

=head1 NAME

Gandolfini::Debug

=cut

package Gandolfini::Debug;

=head1 SYNOPSIS


=head1 DESCRIPTION


=cut


our ($VERSION, @ISA);
use constant DEBUG_NONE		=> 0b00000000;
use constant DEBUG_WARN 	=> 0b00000001;
use constant DEBUG_DUMPER   => 0b00000010;
use constant DEBUG_TRACE    => 0b00000100;

use constant DEBUG          => DEBUG_NONE; 

use base 'Exporter';
use vars '@EXPORT';
no warnings;


@ISA = qw(Exporter);
@EXPORT = qw(traceme DEBUG_NONE DEBUG_WARN DEBUG_DUMPER DEBUG_TRACE);


BEGIN {
    $VERSION	= do { my @REV = split(/\./, (qw$Revision: 1511 $)[1]); sprintf("%0.3f", $REV[0] + ($REV[1]/1000)) };
}

######################################################################

=head1 METHODS

=cut

sub traceme
{

    my @args = @_ if (@_ > 1);
    my ($TO_package, $TO_filename, $TO_line, $TO_subroutine, $TO_hasargs, $TO_wantarray, $TO_evaltext) = caller(1); 
	print STDERR "-" x 80 . "\n";
	print STDERR "$TO_subroutine (@args) \n";

}

1;

__END__

=back

=head1 REVISION HISTORY
Revision 1.1  2005/60/20 15:27:42  szelnick
Initial proof of concept...

=head1 KNOWN BUGS

None

=head1 TO DO

None

=back

=head1 AUTHOR

 Sagi Zelnick<szelnick@shopzilla.com>

=cut
