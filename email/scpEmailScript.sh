#!/bin/bash

INPUT=Linux-Servers-ITSM.csv
OLDIFS=$IFS
IFS=,
[ ! -f $INPUT ] && { echo "$INPUT file not found"; exit 99; }

while read flname b c d ip e f g h i j k l m n o p q r s t u v w x y z aa bb cc dd ee ff gg hh ii jj kk ll mm nn telcom rest

do
	## echo "Name: $flname"
	## echo "    IP: $ip"
	## echo "    TELCOM: |$telcom|"
	if [[ ! $flname =~ (CFS481DL5APP) ]]; then
		## result=$(ssh -o ConnectTimeout=10 $ip 'bash -s' < determineSMTPRelay.pl 2>&1)
		 result=$(timeout 5 ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no $ip 'sudo perl' < determineSMTPRelay.pl 2>&1)
	fi
	echo "$flname,$ip,$result"
	results="$results\n$flname,$ip,$result\n"
done < $INPUT
IFS=$OLDIFS

printf $results >> results.txt
