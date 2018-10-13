#!/usr/bin/perl
use File::Basename;

%user = ();
$ypcat = `ypcat passwd`;
@ypcatSplit = split /\n/,$ypcat;
for my $yp (@ypcatSplit)  {
	@tmp = split /:/,$yp;
	if (!$user{$tmp[0]})  {
		$user{$tmp[0]} = "NIS";
	}
}

$running = `ps -e -o user= | sort | uniq`;
@processes = split /\n/g,$running;
for my $process (@processes)  {
	if ($user{$process})  {
		$processes{$process} = "NIS";
	}  else  {
		$processes{$process} = "LOCAL";
	}
	print ",,".$process.",".$processes{$process}."\n";
}
