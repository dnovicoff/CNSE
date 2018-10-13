#!/usr/bin/perl
#
use strict;
use warnings;

## use Net::SCP qw(scp iscp);


my $NISFile = "./Linux-Servers-ITSM.csv";
## $NISFile = "test";
open(INFO, $NISFile) or die("Could not open  file.");

my %machines = ();
my $count = 0;
foreach my $line (<INFO>)  {   
	chomp($line);
	my @parts = split /,/, $line;
	my $partsLen = @parts;
	if ($partsLen > 42)  {
	## if ($partsLen > 1)  {
		if ($parts[41] =~ /NYS\sDivision\sof\sCriminal\sJustice/i)  {
			if (!$machines{$parts[0]} && $parts[4] =~ m/\d/)  {
				$machines{$parts[0]} = $parts[4];
				## $machines{$parts[0]} = $parts[1];
				## print $parts[0]."  ".$parts[1]."\n";
				$count++;
			}
		}
	}
}
print $count."\n";
close(INFO);
$count = 0;

## print "MACHINE NAME,IP ADDRESS,HOME ENABLED,USER,PASSWD INFO\n";
print "MACHINE NAME,IP ADDRESS,CONNECTION STATS\n";
while (my ($name,$ip) = each(%machines))  {
	my $nsswitch = `ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'grep passwd /etc/nsswitch.conf' 2>&1`;

	if ($nsswitch)  {
		$nsswitch =~ s/\v//g;
		if ($nsswitch !~ m/^(ssh|Permission)/)  {
			if ($nsswitch =~ m/\snis$/i)  {
				print $name.",".$ip.",".$nsswitch."\n";
				my $ypwhich = `ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'ypwhich' 2>&1`;
				if ($ypwhich)  {
					print $ypwhich."\n";
				}
			}
		}  else  {
			## print "     Permission: ".$name.",".$ip.",".$ypwhich."\n";
		}
	}
	$count++;
}
print "Count: ".$count."\n";


