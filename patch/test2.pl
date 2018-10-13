#!/usr/bin/perl
##
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
	my @parts = split(/\s/,$output);
	print "${label}=${$parts[2]}\n";
}

sub run_command_fstab  {
	my $label = shift;
	my $command = shift;
	my $output = qx($command);
	chomp $output;
	my @parts = split(/\n/,$output);
	foreach my $part (@parts)  {
		print "${label}=${part}\n";
	}
}

sub run_command_storage  {
        my $label = shift;
        my $command = shift;
        my $output = qx($command);
        chomp($output);
	chop($output);
        my @parts = split(/\r\n/,$output);
        my $tmp = "";
        foreach my $part (@parts)  {
 		print "${label}=${part}\n";
        }
}


run_command_storage "STORAGE", "ls -l /var/cache/yum/ | grep ^d";




