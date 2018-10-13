#!/usr/bin/perl
use POSIX qw( geteuid getuid setuid getgid getegid setgid );

my $ypcatPasswd = `ypcat passwd`;
my @passwd = split /\n/,$ypcatPasswd;
%pass = ();
for my $p (@passwd)  {
	my @tmp = split /:/,$p;
	if (!$pass{$tmp[0]})  {
		$pass{$tmp[0]} = "NIS";
	}
}

my $dir = '/var/log';
%users = ();
foreach my $fp (glob("$dir/secure*")) {
	open(INFO, $fp) or die("Could not open  file.");
	foreach $line (<INFO>)  {
		if ($line =~ m/Accepted\spassword\sfor\s(.+)\sfrom/)  {
			if (!$users{$1}) {
				$users{$1} = "LOCAL";
			}
		}
		if ($line =~ m/Accepted\spublickey\sfor\s(.+)\sfrom/)  {
			if (!$users{$1})  {
				$users{$1} = "LOCAL";
			}
		}
	}
}

foreach my $key (keys %users) {
	if ($pass{$key})  {
		$users{$key} = "NIS";
	}
	print ",,".$key.",".$users{$key}."\n";
}
print "\n\n";
