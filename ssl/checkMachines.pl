#!/usr/bin/perl
#
use strict;
use warnings;

my $NISFile = "./machines";
my $dir = "./servers/";
open(INFO, $NISFile) or die("Could not open  file.");

my %machines = ();
my $count = 0;
foreach my $line (<INFO>)  {   
	chop($line);
	my @parts = split /,/, $line;
	my $partsLen = @parts;

	my $len = length $line;

	if ($len > 10)  {
		if (!$machines{$parts[0]})  {
			$machines{$parts[0]} = $parts[1];
			$count++;
		}
	}
}
close(INFO);

## print "MACHINE NAME,IP ADDRESS,HOME ENABLED,USER,PASSWD INFO\n";
print "MACHINE NAME,IP ADDRESS,CONNECTION STATS\n";
while (my ($name,$ip) = each(%machines))  {
	chop($ip);
	print $name."  |".$ip."|\n";
	my $machine = `ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'openssl version' 2>&1`;
	## my $result = `curl --head http://$ip/`;
	## print $result."\n";
	$machine =~ s/\v//g;
	$machine =~ s/\*+.+\*+//g;
	
	if ($machine)  {
		my @subs = split(/,/,$machine);
		foreach my $sub (@subs)  {
			print $sub."\n";
		}
		print "\n";
	}
}



