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
close(INFO);
$count = 0;

## print "MACHINE NAME,IP ADDRESS,HOME ENABLED,USER,PASSWD INFO\n";
print "MACHINE NAME,IP ADDRESS,CONNECTION STATS\n";
while (my ($name,$ip) = each(%machines))  {
	## if ($name =~ /^(P)/i)  {
		my $ypwhich = `ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'grep /- /etc/auto.master' 2>&1`;
		if ($ypwhich)  {
			my $nslookup = `ssh $ip 'perl' < nslookup.pl  2>&1`;
	
			if ($nslookup)  {
				$nslookup =~ s/\v//g;
				if ($nslookup)  {
					my @subs = split(/,/,$nslookup);
					print $name." ".$ip."\n";
					foreach my $sub (@subs)  {
						print $sub."\n";
					}
				}
			}
		}
	## }
}



