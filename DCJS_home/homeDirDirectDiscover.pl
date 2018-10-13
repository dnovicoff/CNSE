#!/usr/bin/perl
#
use strict;
use warnings;

## use Net::SCP qw(scp iscp);


my $NISFile = "./Linux-Servers-ITSM.csv";
## $NISFile = "test";
open(INFO, $NISFile) or die("Could not open  file.");

my %machines = ();
my $count = 0;
foreach my $line (<INFO>)  {   
	chomp($line);
	my @parts = split /,/, $line;
	my $partsLen = @parts;
	if ($partsLen > 42)  {
	## if ($partsLen > 1)  {
		if ($parts[41] =~ /NYS\sDivision\sof\sCriminal\sJustice/i)  {
			if (!$machines{$parts[0]} && $parts[4] =~ m/\d/)  {
				$machines{$parts[0]} = $parts[4];
				## $machines{$parts[0]} = $parts[1];
				## print $parts[0]."  ".$parts[1]."\n";
				$count++;
			}
		}
	}
}
close(INFO);
$count = 0;

## print "MACHINE NAME,IP ADDRESS,HOME ENABLED,USER,PASSWD INFO\n";
print "MACHINE NAME,IP ADDRESS,CONNECTION STATS\n";
while (my ($name,$ip) = each(%machines))  {
	## if ($name =~ /^(P)/i)  {
		$ip = "10.71.34.71";
		print "Grep for home dir\n";
		my $ypwhich = `ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'grep /- /etc/auto.master' 2>&1`;
	
		if ($ypwhich)  {
			print "After grep for home dir\n";
			print $ypwhich."\n";
			$ypwhich =~ s/\v//g;
			if ($ypwhich !~ m/^(ssh|Permission)/)  {
				print "No permissions\n";
				## if ($ypwhich !~ /^#/)  {
					## print $name.",".$ip.",".$ypwhich."\n";
					print "No permissions: no pounds\n";

					my $passwd = `ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'cat /etc/passwd' 2>&1`;
					my @passwdSplit = split(/\n/,$passwd);
					my $auto = "auto.home";
					open(my $fh, '>', $auto) or die "Could not open file '$auto' $!";
					foreach my $user (@passwdSplit)  {
						if ($user =~ /\/home/)  {
							my @uN = split(/:/,$user);
							print $fh "/home/".$uN[0]."\thome-server:/dcjs_home/".$uN[0]."\n";
							## print ",,,".$uN[0].",".$user."\n";
						}
					}
					close $fh;
					my $old_fh = select($fh);
					$| = 1;
					select($old_fh);
					## $scp->put("./".$auto) or die $scp->{errstr};
					`scp ./$auto $ip:/tmp`;


					my $master = `ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'cat /etc/auto.master' 2>&1`;
					my @masterSplit = split(/\n/,$master);
					my $mas = "auto.master";
					open ($fh, '>', $mas) or die "Could not open file '$mas' $!";
					foreach my $data (@masterSplit)  {
						if ($data =~ /^\/home/)  {
							$data = "#".$data."\n/-\t/etc/auto.home\n";
						}
						print $fh $data."\n";
						## print $data."\n";
					}
					close $fh;
					$old_fh = select($fh);
					$| = 1;
					select($old_fh);
					`scp ./$mas $ip:/tmp`;
				
					$count++;
				## }
			}  else  {
				print $name.",".$ip.",".$ypwhich."\n";
			}
		}
	## }
}



