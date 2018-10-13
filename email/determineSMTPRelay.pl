#!/usr/bin/perl
#
use strict;
use warnings;

my $mailProgram = "";
$mailProgram = `netstat -tanpl|grep :25`;
my @mailProgramSplit = split /\n/,$mailProgram;
my $result = "";
foreach my $mail (@mailProgramSplit)  {
	$mail =~ s/\s+$//;
	if ($mail =~ /master$/)  {
		$result = "POSTFIX\n";
		my $relay = `grep relayhost /etc/postfix/main.cf`;
		my @lines = split /\n/,$relay;
		my $grepResult = "";
		foreach my $line (@lines)  {
			if ($line =~ /^relayhost/)  {
				$grepResult = $line;
			}
		}
		$result = "POSTFIX,".$grepResult;
	}
	if ($mail =~ /sendmail$/)  {
		my $relay = `grep DS /etc/mail/sendmail.cf`;
		my @lines = split /\n/,$relay;
		my $grepResult = "";
		foreach my $line (@lines)  {
			if ($line =~ m/^DS/)  {
				$grepResult= substr($line,2);
			}
		}
		$result = "SENDMAIL,".$grepResult;
	}
}
print $result;
