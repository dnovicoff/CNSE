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

my $ypcatPasswd = `timeout 10 ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no 10.71.34.155 'ypcat passwd' 2>&1`;
my @ypcatPasswdUser = split /\n/,$ypcatPasswd;
my %ypcatPasswdUsers = ();
foreach my $yppu (@ypcatPasswdUser)  {
	my @tmp = split /:/,$yppu;
	## print $yppu."\n";
	if (!$ypcatPasswdUsers{$tmp[0]})  {
		$ypcatPasswdUsers{$tmp[0]} = $yppu;
	}
}

my $ypcatGroup = `timeout 10 ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no 10.71.34.155 'ypcat group' 2>&1`;
my @ypcatGroupUser = split /\n/,$ypcatGroup;
my %ypcatGroupUsers = ();
my %ypcatGroupIDs = ();
my %ypcatSecondaryGroups = ();
my $groupCount = 0;
foreach my $ypgu (@ypcatGroupUser)  {
	## print $ypgu."\n";
	my @tmp = split /:/,$ypgu;
	my $len = @tmp;
	if (!$ypcatGroupUsers{$tmp[0]})  {
		$ypcatGroupUsers{$tmp[0]} = $ypgu;
		$groupCount += 1;
	}
	if (!$ypcatGroupIDs{$tmp[2]})  {
		$ypcatGroupIDs{$tmp[2]} = $ypgu;
	}

	if ($len > 3)  {
		my $secondary = $tmp[3];
		my @secondarySplit = split /,/,$secondary;
		foreach my $ss (@secondarySplit)  {
			if (!$ypcatSecondaryGroups{$ss})  {
				#3 print "     Creating group: ".$ss."  belongs to this group ".$tmp[0]."\n";
				$ypcatSecondaryGroups{$ss} = $tmp[0];
			}  else  {
				## print "     Adding group: ".$tmp[0]."  For goup: ".$ss."\n";
				my $tmpStr = $ypcatSecondaryGroups{$ss};
				$tmpStr = $tmpStr." ".$tmp[0];
				$ypcatSecondaryGroups{$ss} = $tmpStr;
				## print "     Group List: ".$ypcatSecondaryGroups{$ss}."\n";
			}
		}
	}
}

my $inputFile = "./NISDevClientsRun.csv";
open(INFO, $inputFile) or die("Could not open  file.");
my $machine = "";
my @users = [];
my %machines = ();
my %ips = ();
my %accts = ();
foreach my $line (<INFO>)  {
	my @data = split /,/,$line;
	my $dataLen = @data;
	if ($data[0] =~ /(\w+)/ && $data[0] !~ /Machine/)  {
		$machine = $1;
		$ips{$machine} = $data[1];
		## print $ips{$machine}."\n";
	}

	if ($dataLen > 1)  {
		if ($data[3] =~ m/(\w+)/ && $data[3] ne "" && $data[3] ne "User")  {
			if (!$accts{$data[3]})  {
				$accts{$data[3]} = $data[3];
			}
		}
	}

	if ($line =~ /^\n/)  {
		$machines{$machine} = {%accts};
		%accts = ();
	}
}
close(INFO);

foreach my $machine (keys %machines)  {
	print "MACHINE: ".$machine."\n";
	print "IP: ".$ips{$machine}."\n";
	my $ip = $ips{$machine};

	while (my ($key, $value) = each %{$machines{$machine}}) {
		if ($key !~ m/(smardon|rkoster|zabbix|root|postfix)/)  {
			print "CHECKING FOR LOCAL USER $key\n";
			my $localUser = `ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'grep $key /etc/passwd' 2>&1`;
			if ($localUser =~ m/^(\w+)/)  {
				my $userNISValue = $ypcatPasswdUsers{$key};
				my @userTMP = split /:/,$userNISValue;
				my $userName = $userTMP[0];
				my $userUID = $userTMP[2];
				my $groupGID = $userTMP[3];

				my $groupNISValue = $ypcatGroupIDs{$groupGID};
				my @nisGroups = split /:/,$groupNISValue;

				## GETTING THE GID FOR THIS GROUP
				my $select = "SELECT * FROM uids WHERE name = '$nisGroups[0]'";
				my $sth = $connect->prepare($select);
				$sth->execute();
				my $rows = $sth->rows;
				if ($rows > 0)  {
					my @groupMYSQLID = $sth->fetchrow_array;
					my $groupGID = $groupMYSQLID[0];
				}
				print "USING GID: $groupGID FOR USER $key\n";
				
				## GETTING THE UID FOR THIS USER
				print "LOOKING UP UID FOR USER: |$key| EXPECTING $userUID\n";
				$select = "SELECT * FROM uids WHERE name = '$key'";
				my $sthU = $connect->prepare($select);
				$sthU->execute();
				my $rowsU = $sthU->rows;
				if ($rowsU > 0)  {
					my @userMYSQLID = $sthU->fetchrow_array;
					$userUID = $userMYSQLID[0];
				}
				print "USING UID $userUID FOR USER |$key|\n";

				## Primary Group
				my $localGroup = `ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'grep :$nisGroups[2]: /etc/group' 2>&1`;
				if (!$localGroup)  {
					my $groupAddCmd = "groupadd -g $userTMP[3] $nisGroups[0]";
					print $groupAddCmd."\n";
					my $groupAddCmdExec = `ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'sudo $groupAddCmd' 2>&1`;
					if ($groupAddCmdExec)  {
						print $groupAddCmdExec."\n";
					}
				}

				my $userAddCmd = "useradd -m -d ".$userTMP[5]." -u ".$userUID." -g ".$groupGID." -c \"".$userTMP[4]."\" -s ".$userTMP[6]." ".$key;
				print $userAddCmd."\n";
				my $userAddCmdExec = `ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'sudo $userAddCmd' 2>&1`;
				if ($userAddCmdExec)  {
				 	print $userAddCmdExec."\n";
				}
				my $userChPasswdEcho = "echo ".$key.":".$userTMP[1]." > chpasswdFile";
				print $userChPasswdEcho."\n";
				my $userChPasswdExec = `ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'sudo $userChPasswdEcho' 2>&1`;
				if ($userChPasswdExec)  {
					print $userChPasswdExec."\n";
					my $userChPasswd = "chpasswd -e < chpasswdFile";

					my $userChPasswdExec = `ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'sudo $userChPasswd' 2>&1`;
					if ($userChPasswdExec)  {
						print $userChPasswdExec."\n";
					}
				}
		
				if ($ypcatSecondaryGroups{$key})  {
					print "LOOKING FOR SECONDARY GROUPS\n";
					my $secondaryG = $ypcatSecondaryGroups{$key};
					my @secondaryTMP = split / /,$secondaryG;
					foreach my $sTMP (@secondaryTMP)  {
						my $groupID = $ypcatGroupUsers{$sTMP};
						my @gID = split /:/,$groupID;
						my $newG = $gID[2];

						my $sGroup = `ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'grep :$newG: /etc/group' 2>&1`;
						print "Group: ".$sTMP." ID: ".$newG."\n";
						if (!$sGroup)  {
							my $groupID = $ypcatGroupUsers{$sTMP};
							my @gID = split /:/,$groupID;
							my $newG = $gID[2];
							print "GROUP NOT FOUND CREATING: $newG\n";
							my $groupAddCmd = "groupadd -g $newG $sTMP";
							print $groupAddCmd."\n";
							my $sGroup = `ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no $ip $groupAddCmd 2>&1`;
						}
						my $secondaryGroupCmd = "usermod -a -G $sTMP $key";
						print $secondaryGroupCmd."\n";	
						$sGroup = `ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no $ip $secondaryGroupCmd 2>&1`;
					}
				}
			}
		}
	}
	print "\n\n";
}

