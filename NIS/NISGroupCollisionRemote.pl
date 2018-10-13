#!/usr/bin/perl
use strict;
use warnings;

use Scalar::Util qw(reftype);

my $ypcatGroup = `ypcat group`;
my @ypcatGroupUser = split /\n/,$ypcatGroup;
my %ypcatGroups = ();
my %ypcatGroupIDs = ();
my %ypcatSecondaryGroups = ();
my $groupCount = 0;
foreach my $ypgu (@ypcatGroupUser)  {
	my @tmp = split /:/,$ypgu;
	my $len = @tmp;
	if (!$ypcatGroups{$tmp[0]})  {
		$ypcatGroups{$tmp[0]} = $tmp[2];
		$groupCount += 1;
	}
	if (!$ypcatGroupIDs{$tmp[2]})  {
		$ypcatGroupIDs{$tmp[2]} = $tmp[0];
	}

	if ($len > 3)  {
		my $secondary = $tmp[3];
		my @secondarySplit = split /,/,$secondary;
		foreach my $ss (@secondarySplit)  {
			if (!$ypcatSecondaryGroups{$ss})  {
				$ypcatSecondaryGroups{$ss} = $tmp[0];
			}  else  {
				my $tmpStr = $ypcatSecondaryGroups{$ss};
				$tmpStr = $tmpStr." ".$tmp[0];
				$ypcatSecondaryGroups{$ss} = $tmpStr;
			}
		}
	}
}

my $catGroup = `cat /etc/group`;
my @catGroupSplit = split /\n/,$catGroup;
my %localGroups = ();
my %localIDS = ();
foreach my $grp (@catGroupSplit)  {
	my @tmp = split /:/,$grp;
	if (!$localGroups{$tmp[0]})  {
		$localGroups{$tmp[0]} = $tmp[2];
	}
	if (!$localIDS{$tmp[2]})  {
		$localIDS{$tmp[2]} = $tmp[0];
	}
}

while (my ($name, $id) = each(%ypcatGroups)) {
	if ($localGroups{$name} && !$localIDS{$id})  {
		print ",,$name,$id,$localGroups{$name},$name\n";
	}
	if ($localIDS{$id} && !$localGroups{$name})  {
		print ",,$name,$id,$id,$localIDS{$id}\n";
	}
}
