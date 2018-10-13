#!/usr/bin/perl
#
#
use strict;
use warnings;

my $file = "Linux-Servers-ITSM.csv";
my $pFile = "rootpasswds.txt";
my %pWords = ();
open (my $f, $pFile) or die "Could not open file $pFile $!";
while (my $row = <$f>)  {
	my @parts = split(/\t/,$row);
	if (!$pWords{$parts[0]})  {
		chop $parts[3];
		$pWords{$parts[0]} = $parts[3];
	}
}
close($f);

my %sshMachines = ();
open (my $fh, $file) or die "Could not open file $file $!";
while (my $row = <$fh>)  {
	my @parts = split(/,/,$row);
	if (@parts > 42)  {
		if ($parts[6] =~ /SSH DOWN/)  {
			if ($pWords{$parts[0]})  {
				my $machine = $parts[0];
				my $pass = $pWords{$parts[0]};
				print $parts[0]." ".$pWords{$parts[0]}."\n";
			}
		}
	}
}
