#!/usr/bin/perl
#
use strict;
use warnings;
use IO::Handle;

my $file = `hostname`;
chop $file;
my $remoteIP = "10.77.236.31";
my $remoteDir = "./servers/";
open (my $fhs, '>',$file) or die "Could not open file $!\n";

my $yumPid = `[ -e /var/run/yum/pid ] && echo "Pid exists" || echo "Pid does not exits"`;
printf $fhs "YUM: ".$yumPid."\n";

my $varSize = `df -h | grep /var`;
print $fhs "VAR: ".$varSize."\n";

my $netManager = `chkconfig NetworkManager --list`;
print $fhs "NETWORK MANAGER: ".$netManager."\n";

my $selinux = `getenforce`;
print $fhs "SELinux: ".$selinux."\n";

## my $yumRepo = `grep -i enabled /etc/yum.repos.d/*.repo`;
my $yumRepo = `ls /etc/yum.repos.d/*.repo`;
my @repos = split(/\n/,$yumRepo);
foreach my $repo (@repos)  {
	my $repoEnabled = `grep -i enabled $repo`;
	print $fhs "Repo File: ".$repo."\n";
	if ($repoEnabled =~ /enabled=1/i)  {
		my $edit = `cat $repo`;
		my @lines =  split(/\n/,$edit);
		my $repoFile = $repo;
		open (my $fh, '>', $repoFile) or die "Could not open file $!";
		foreach my $line (@lines)  {
			if ($line =~ /enabled=1/i)  {
				$line = "enabled=0";
			}
			print $fh $line."\n";
		}
		close $fh;
		my $old = select($fh);
		$| = 1;
		select($old);
	}
}

my $kernel = `uname -a`;
my @kerns = split(/ /,$kernel);
$kernel = $kerns[2];
print $fhs "\nCurrent Kernel: ".$kernel."\n";
my $rpmKernel = `rpm -qa | grep -i ^kernel`;
my @rpmKerns = split(/\n/,$rpmKernel);
foreach my $rpms (@rpmKerns)  {
	if ($rpms =~ /$kernel/i)  {
		print $fhs "Kernel: $rpms\n";
	}
}

my $cifs = `grep -i cifs /etc/fstab`;
print $fhs "\nCIFS: ".$cifs."\n";

my $mount = `mount`;
print $fhs "\nMount: ".$mount."\n";

my $storage = `ls -l /var/cache/yum/`;
print $fhs "\nVAR CACHE YUM: \n".$storage;
if ($storage !~ m/0/gi)  {
	print $fhs "Deleting /var/cache/yum/\n";
	my $delResults = `rm -rf /var/cache/yum/.`;
	print $fhs $delResults."\n";
}
print $fhs "\n";

my $fstab = `cat /etc/fstab`;
print $fhs "FSTAB: ".$fstab."\n";

my $dfh = `df -h`;
print $fhs "Disk Free:\n$dfh\n";

print $fhs "Copying directory /etc/sysconfig/network-scripts/\n";
my $ips = `ls /etc/sysconfig/network-scripts/*`;
print $fhs $ips."\n";
my $mkdir = `mkdir /$file`;
my $ipCopy = `cp -a /etc/sysconfig/network-scripts/* /$file`;

print $fhs "Checking for Stealth configuration\n";
my $stealth = `ip addr | grep Stealth`;
print $fhs $stealth."\n";

print $fhs "Checking system ram memory\n";
my $mem = `grep MemTotal /proc/meminfo`;
print $fhs $mem."\n";

close $fhs;
my $myFile = `cat $file`;
print $myFile;
