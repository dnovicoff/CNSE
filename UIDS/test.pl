#!/usr/bin/perl
#
my $value = `grep -i dnovicoff /etc/passwd`;

if ($value)  {
	print $value."\n";
}
