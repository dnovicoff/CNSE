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

sub run_command_release  {
	my $label = shift;
	my $command = shift;
	my $output = qx($command);
	chomp $output;
	my @tmp = split(/\s/,$output);
	print "${label}=${tmp[2]}\n";
}

__EOL__

my $script_create_users = $script_functions . "\n" . << '__EOL__';
run_command "HOSTNAME", "hostname";
run_command "OPENSSL", "rpm -qa | grep openssl- | head -1";
run_command_release "LSB_Release", "uname -a";
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


my $adminFile = "./machines";
my $dir = "./servers/";
open(INFO, $adminFile) or die("Could not open  file.");

my %machines = ();
my $count = 0;
foreach my $line (<INFO>)  {   
	chop($line);
	my @parts = split /,/, $line;
	my $partsLen = @parts;

	my $len = length $line;

	if ($len > 10)  {
		if (!$machines{$parts[0]})  {
			$machines{$parts[0]} = $parts[1];
			$count++;
		}
	}
}
close(INFO);

my $userDir = "./keys/";
while (my ($name,$ip) = each(%machines))  {
	my $test = `ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'echo ready' 2>&1`;
	if ($test)  {
		my %results = get_server_results($ip,$script_create_users);
		foreach my $key (keys(%results))  {
			print $key.",".$results{$key}.",";
		}
		print "\n";
	}
}



