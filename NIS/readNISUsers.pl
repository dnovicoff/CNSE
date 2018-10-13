#!/usr/bin/perl
#
use strict;
use warnings;

my $NISFile = "./NISMachines";
open(INFO, $NISFile) or die("Could not open  file.");

my $dirname = "./";
opendir(Dir, $dirname) or die "cannot open directory $dirname";
my @docs = grep(/\.csv$/,readdir(Dir));
close(Dir);

my %ypcatUsers = ();
my $ypcatData = `timeout 10 ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no 10.71.34.155 'ypcat passwd' 2>&1`;
my @ypcatSplit = split /\n/,$ypcatData;
foreach my $line (@ypcatSplit)  {
	my @tmp = split /:/,$line;
	if (!$ypcatUsers{$tmp[0]})  {
		$ypcatUsers{$tmp[0]} = $line;
	}
}

my %machines = ();
my $count = 0;
foreach my $line (<INFO>)  {   
	if ($line =~ m/management/)  {
		## my @parts = split / /,$line;
		my @parts = split /,/, $line;
		if (!$machines{$parts[2]})  {
			$machines{$parts[2]} = $parts[1];
		}
		$count++;
	}
}
close(INFO);

print "Machine Name,IP Address,File,User,NIS,,UID,GID,HOME,SHELL\n";
while (my ($key,$value) = each(%machines))  {
	my $firstFile = "";
	my $lastFile = "";
	print $key.",".$value.",,,\n";
	foreach my $file (@docs)  {
		if ($file =~ m/^(process|crontab|secure|lastlog)/)  {
			print ",,".$file.",,\n";
			open(FILE,$dirname.$file) or die("cannot open file.");
			foreach my $line (<FILE>)  {
				if ($line =~ m/^(\w+),/)  {
					$firstFile = $1;
					## print "FIRSTFILE: ".$firstFile."\n";
				}
				if ($line =~ m/$key/)  {
					$lastFile = $key;
				}
				if ($firstFile eq $lastFile && $firstFile ne "")  {
					if ($line =~ m/NIS/)  {
						my $add = ",";
						## print ",".$line;
						chomp $line;
						my @nisUsers = split /,/,$line;
						if ($key =~ /TVLWAIJ02/)  {
							print $line."\n";
						}
						if ($ypcatUsers{$nisUsers[2]})  {
							my $userYP = $ypcatUsers{$nisUsers[2]};
							my @yp = split /:/,$userYP;
							if (@yp)  {
								$add .= $yp[2].",".$yp[3].",".
									$yp[5].",".$yp[6]."\n";
							}
						}
						print ",".$line.",".$add;
					}
				}
			}
		}	
	}
	print "\n";
}
