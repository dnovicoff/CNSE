#!/bin/bash

INPUT=NISMachines
OLDIFS=$IFS
IFS=','
printf "Machine Name,IP Address,User,LOCAL/NIS,Directory\n"
[ ! -f $INPUT ] && { echo "$INPUT file not found"; exit 99; }
while read mach ip name rest
do 
	printf "$name,$ip,,\n"
	result=$(timeout 20 ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'sudo perl' < crontabLastResults.pl 2>&1)
	echo "$result"
	printf "\n\n"
done < $INPUT
IFS=$OLDIFS

## users=$(ypcat passwd)

