#!/usr/bin/perl
#
use strict;
use warnings;

my $NISFile = "./NISMachines";
open(INFO, $NISFile) or die("Could not open  file.");

my %machines = ();
my $count = 0;
foreach my $line (<INFO>)  {   
	my @parts = split /,/, $line;
	my $partsLen = @parts;
	if ($partsLen > 3)  {
		if (!$machines{$parts[2]} && $parts[1] =~ m/\d/)  {
			$machines{$parts[2]} = $parts[1];
		}
		$count++;
	}
}
close(INFO);

print "MACHINE NAME,IP ADDRESS,WHEEL ENABLED\n";
while (my ($name,$ip) = each(%machines))  {
	my $ypwhich = `ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'grep /home /etc/auto.master' 2>&1`;
	
	if ($ypwhich)  {
		$ypwhich =~ s/\v//g;
		if ($ypwhich !~ m/^(ssh|Permission)/)  {
			print $name."  ".$ip."  ".$ypwhich."\n";
		}
	}
}
print $count."\n";
