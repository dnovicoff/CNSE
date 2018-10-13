#!/usr/bin/perl
#
#
my $results = "";
for ($i=0;$i<10;$i++)  {
	$results .= `nslookup NFS1-95X.ISILON1-95X.SVC.NY.GOV`;
	$results .= ",";
	sleep 5;
}
print $results;
