#!/usr/bin/perl
#
$ypcat = `ypcat passwd`;
@ypcatSplit = split /\n/,$ypcat;
%users = ();

for $yp (@ypcatSplit)  {
	@tmp = split /:/,$yp;
	if (!$users{$tmp[0]})  {
		$users{$tmp[0]} = "NIS";
	}
}

while (my ($key, $value) = each(%users)) {
	$lastlog = `last $key`;
	if ($lastlog !~ m/^\n/)  {
		@tmp = split /\n/,$lastlog;
		@sub = split /\s/,$tmp[0];
		if ($users{$sub[0]})  {
			print ",,".$sub[0].",".$users{$sub[0]}."\n";
		}
	}
}
