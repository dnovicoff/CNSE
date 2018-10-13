#!/usr/bin/perl
#

use strict;
use warnings;

my $file = "servers";
open my $handle, '<', $file;
chomp(my @lines = <$handle>);
close $handle;

foreach (@lines)  {
	my @parts = split(/,/,$_);

	print $parts[0]."  ".$parts[1]."\n";
	my $master = `ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=no $parts[1] 'rpm -qa | grep -i ssl' 2>&1`;
	print $master;
}
