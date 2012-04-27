=head1 NAME

Gandolfini::DashProfiler - Wrapper for DashProfiler::Import

=head1 SYNOPSIS

Use Gandolfini::DashProfiler like DashProfiler::Import except that
Gandolfini::DashProfiler will not fail if DashProfiler::Import isn't installed.

=cut

package Gandolfini::DashProfiler;

my $have_dashprofiler = eval {
    require DashProfiler;
    die "Need version >= 1.06\n" unless $DashProfiler::VERSION >= 1.06;
    require DashProfiler::Import;
};

push our @ISA, 'DashProfiler::Import' if $have_dashprofiler;

sub import {
    my $class = shift;
    if ($have_dashprofiler) {
	local $DashProfiler::Import::ExportLevel = $DashProfiler::Import::ExportLevel + 1;
	return $class->SUPER::import( ':optional', @_ );
    }
    else {
	my $pkg = caller;
	for my $var_name (@_) {
	    next unless $var_name =~ m/_profiler$/;
            no strict 'refs'; ## no critic
            *{"${pkg}::$var_name"} = sub { undef };
            *{"${pkg}::${var_name}_enabled"} = sub ( ) { 0 };
	}
    }
}

1;
