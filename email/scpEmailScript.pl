#!/usr/bin/perl

use strict;
use warnings;

my $file='Linux-Servers-ITSM.csv';
open(INFO, $file) or die("Could not open  file.");

my $cvs = "EmailResults.csv";
open(my $fh, '>', $cvs);
foreach my $line (<INFO>)  {
	my @values = split /,/,$line;
	my $serverName = $values[0];
	my $ip = $values[4];

	my $result = `timeout 5 ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'sudo perl' < determineSMTPRelay.pl 2>&1`;
	print "|".$result."|\n";
	
	print $fh "$serverName,$ip,$result\n";
}
