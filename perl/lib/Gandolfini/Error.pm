#!/usr/bin/perl

package Gandolfini::Error;

use base qw{Error};


package Gandolfini::ArgumentError;

use base qw{Gandolfini::Error};

package Gandolfini::MethodError;

use base qw{Gandolfini::Error};

1;
