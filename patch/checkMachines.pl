#!/usr/bin/perl
#
use strict;
use warnings;

use JSON;
use Storable;
use Text::CSV;
use IPC::Open3;
use IO::Socket::INET;
use Net::Ping::External;
use Excel::Writer::XLSX;
use Excel::Writer::XLSX::Utility;
use Getopt::Long;

use Net::SCP qw(scp iscp);


my $script_functions = << '__EOL__';
use strict;
use warnings;

sub run_command  {
	my $label = shift;
	my $command = shift;
	my $output = qx($command);
	chomp $output;
	print "${label}=${output}\n";
}

sub run_command_code {
 	my $label = shift;
 	my $command = shift;
 	my $output = qx($command);
 	my $ret = $? >> 8;
 	if ($ret == 0) {
 		print "${label}=1\n";
 	} else {
 		print "${label}=0\n";
 	}
}

sub run_command_kernel  {
	my $label = shift;
	my $command = shift;
	my $output = qx($command);
	chomp $output;
	my @parts = split(/\s/,$output);
	print "${label}=${parts[2]}\n";
}

sub run_command_mount  {
	my $label = shift;
	my $command = shift;
	my $output = qx($command);
	chomp($output);
	my @parts = split(/\n/,$output);
	my $tmp = "";
	foreach my $part (@parts)  {
		$part =~ s/=/-/g;
		$tmp .= $part."|";
	}
	print "${label}=${tmp}\n";
}

sub run_command_multiline  {
	my $label = shift;
	my $command = shift;
	my $output = qx($command);
	chomp($output);
	my @parts = split(/\n/,$output);
	my $tmp = "";
	foreach my $part (@parts)  {
		$tmp .= $part."|";
	}
	print "${label}=${tmp}\n";
}

__EOL__

my $script_check_server = $script_functions . "\n" . << '__EOL__';
run_command "YUM", "[ -e /var/run/yum/pid ] && echo Pid_exists || echo Pid_does_not_exits";
run_command_code "NetworkManager", "/sbin/chkconfig --list NetworkManager | grep ':on'";
run_command_code "SELinux", "getenforce";
run_command_code "CIFS", "grep -i cifs /etc/fstab";
run_command_multiline "STORAGE", "ls -l /var/cache/yum/ | grep ^d";
run_command_multiline "DISKFREE", "df  -h";
run_command_mount "MOUNT", "mount";
run_command_mount "FSTAB", "cat /etc/fstab";
run_command_kernel "KERNEL", "uname -a";
run_command_code "STEALTH", "ip addr | grep Stealth";
run_command "SYSMEMORY", "grep MemTotal /proc/meminfo";
__EOL__

sub headless_ssh_script {
 	my $host = shift;
 	my $interpreter = shift;
 	my $script = shift;
 	my $timeout = shift;

 	my $pid = -1;
 	my $output = '';
 	my @ssh_options = ("-o UserKnownHostsFile=/dev/null", "-o StrictHostKeyChecking=no", "-o ConnectTimeout=5", "-o PasswordAuthentication=no", "-o BatchMode=yes", "-o IdentitiesOnly=yes", "-o IdentityFile=~/.ssh/id_rsa", "-o ForwardX11=no", "-o ForwardX11Trusted=no", "-o ProxyCommand=none");

 	eval {
 		local $SIG{ALRM} = sub { die "alarm\n"; };
 		alarm $timeout;
 		$pid = open3(*WTR, *RDR, *ERR, "ssh", @ssh_options, $host, $interpreter);

 		print WTR $script;

 		close WTR;

 		waitpid($pid, 0);

 		while (<RDR>) {
 			chomp;
 			$output .= "$_\n";
 		}
		close RDR;
 		close ERR;

 		alarm 0;
 	};
 	if ($@) {
 		if ($@ eq "alarm\n") {
			if ($pid != -1) {
 				kill 'KILL', $pid;
 			}
 		} else {
 			die
 		}
 	}

 	chomp $output;
 	return $output;
}

sub get_server_results {
 	my $host = shift;
 	my $script = shift;
 	my $output = headless_ssh_script($host, "/usr/bin/perl", $script, 120);
 	my %hash = ();
 	open my $fh, '<', \$output or die $!;

 	while (my $row = <$fh>) {
 		chomp $row;
 		my @parts = split(/=/, $row);

 		$hash{$parts[0]} = $parts[1];
 	}
 	close $fh or die $!;
 	return %hash;
}



my $NISFile = "./machines";
my $dir = "./servers/";
open(INFO, $NISFile) or die("Could not open  file.");

my %machines = ();
my $count = 0;
foreach my $line (<INFO>)  {   
	chop($line);
	my @tmp = split(/,/,$line);
	if (!$machines{$tmp[0]})  {
		$machines{$tmp[0]} = $tmp[1];
		$count++;
	}
}
close(INFO);

## print "MACHINE NAME,IP ADDRESS,HOME ENABLED,USER,PASSWD INFO\n";
while (my ($name,$ip) = each(%machines))  {
	print "\nAdministering machine: ".$name." Using IP: ".$ip."\n";
	my $test = `ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'echo ready' 2>&1`;
	if ($test)  {
 		my %results = get_server_results($ip,$script_check_server);
 		foreach my $key (sort(keys(%results)))  {
			my $result = $results{$key};
			my $output = "";
			$result =~ s/\|$//;
			if ($result =~ /\|/)  {
				my @tmp = split(/\|/, $result);
				foreach my $t (@tmp)  {
					$output .= $key."  ".$t."\n";
				}
				chomp($output);
			}  else  {
				$output = $key."  ".$result;
			}
			print $output."\n";
		}
	}  else  {
		print "Can't connect\n";
	}
}



