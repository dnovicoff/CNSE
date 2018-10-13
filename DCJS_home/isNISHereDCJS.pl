#!/usr/bin/perl
#
use strict;
use warnings;

## use Net::SCP qw(scp iscp);


my $NISFile = "./DCJS.csv";
## $NISFile = "test";
open(INFO, $NISFile) or die("Could not open  file.");

my %machines = ();
my $count = 0;
foreach my $line (<INFO>)  {   
	chomp($line);
	my @parts = split /,/, $line;
	my $partsLen = @parts;
	if ($partsLen > 1)  {
		if (!$machines{$parts[0]} && $parts[1] =~ m/\d/)  {
			$machines{$parts[0]} = $parts[1];
			$count++;
		}
	}
}
print $count."\n";
close(INFO);
$count = 0;

## print "MACHINE NAME,IP ADDRESS,HOME ENABLED,USER,PASSWD INFO\n";
print "MACHINE NAME,IP ADDRESS,CONNECTION STATS\n";
while (my ($name,$ip) = each(%machines))  {
	my $nsswitch = `ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'ps -ef | grep yp' 2>&1`;

	## if ($nsswitch)  {
		$nsswitch =~ s/\v//g;
		if ($nsswitch !~ m/^(ssh|Permission)/)  {
			if ($nsswitch =~ m/\snis$/i)  {
				print "HELLO: ".$name." ".$ip."\n";
				print $nsswitch."\n";
				my $ypwhich = `ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'ypwhich' 2>&1`;
				if ($ypwhich)  {
					print $ypwhich."\n";
				}
			}
		}  else  {
			print "HELLO: ".$name." ".$ip."\n";
			print $nsswitch."\n\n";
		}
	## }
	$count++;
}
print "Count: ".$count."\n";


