#!/usr/bin/perl

$dirname = "/var/spool/";
opendir my($dh), $dirname or die "Couldn't open dir '$dirname': $!";
my @dirs = readdir $dh;
closedir $dh;

%users = ();
$ypcat = `ypcat passwd`;
@ypcatUsers = split /\n/,$ypcat;
for my $yp (@ypcatUsers)  {
	@tmp = split /:/,$yp;
	if (!$users{$tmp[0]})  {
		$users{$tmp[0]} = "NIS";
	}
}

for (@dirs)  {
	if ($_ =~ m/^cron/)  {
		$test = $dirname.$_;
		if (-d $test)  {
			opendir my($dh),$test or die "Couldn't open dir '$test': $!";
			my @subs = readdir $dh;
			closedir $dh;
			for my $sub (@subs)  {
				if ($sub !~ m/^\./)  {
					$acct = "LOCAL";
					if ($users{$sub})  {
						$acct = "NIS";
					}
					print ",,".$sub.",".$acct."\n";
				}
			}
		}
	}
}

