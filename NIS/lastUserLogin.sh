#!/bin/bash

printf "Machine Name,IP Address,User,LOCAL/NIS\n"
INPUT=NISMachines
OLDIFS=$IFS
IFS=','
## [ ! -f $INPUT ] && { echo "$INPUT file not found"; exit 99; }
## while read mach ip name rest
## do 
	printf "$name,$ip\n"
	## result=$(timeout 10 ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'sudo perl' < ypcatLastResults.pl 2>&1)
	result=$(ssh root@10.71.34.118 'sudo perl' < ypcatLastResults.pl 2>&1)
	printf "$result"
	printf "\n\n"

## done < $INPUT
## IFS=$OLDIFS

