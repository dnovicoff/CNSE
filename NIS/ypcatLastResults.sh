#!/bin/bash

OIFS=$IFS;

count=0
users=$(ypcat passwd)
## IFS=$'\n'; arr=($(echo -e $users));
## IFS=$'$' read -a arr <<< "$users"
## arr=($users)
echo "$users" > testFile
IFS=$'\n'
for i in `cat testFile`
do
        message=""
        tmp=""
        IFS=':' read -a array <<< "$i"
        lastLogin=$(last ${array[0]})
        name=${array[0]}
        if [ ${#lastLogin} -ge 38 ]; then
                IFS=$'\n' read -a login <<< "$lastLogin"
                header=$'Last login for user:\n'
                body=$"${login[0]}"
                tmp=$body
                printf ",,$tmp\n"
                let count+=1
        fi
        message+="$tmp"
done
## echo "$users"

