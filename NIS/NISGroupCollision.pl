#!/usr/bin/perl
use strict;
use warnings;

use DBI;
use Scalar::Util qw(reftype);


my $host = "localhost";
my $database = "UIDS";
my $user = "root";
my $pw = "";
my $connect = DBI->connect("dbi:mysql:dbname=".$database,$user, $pw);

my %machines = ();
my $file='./NISMachines';
open(INFO, $file) or die("Could not open  file.");
foreach my $line (<INFO>)  {   
	my @tmp = split /,/,$line;
	if (!$machines{$tmp[2]})  {
		$machines{$tmp[2]} = $tmp[1];
	}
}
close(INFO);

print "NAME,IP ADDRESS,NIS GROUP,NIS GID,FILE GID,FILE GROUP\n";
while (my ($machName, $machIP) = each(%machines)) {
	print "$machName,$machIP,,,,\n";
	my $ypcatGroup = `timeout 10 ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no $machIP 'sudo perl' < NISGroupCollisionRemote.pl 2>&1`;
	if ($ypcatGroup)  {
		print $ypcatGroup."\n";
	}
}
