#!/bin/bash

machine=$(/bin/hostname -f)
tmp=$(/sbin/ifconfig | awk '/inet addr/{print substr($2,6)}')


## mail -s "$machine" david.novicoff@its.ny.gov <<< "$machine"

/usr/sbin/sendmail -i -- david.novicoff@its.ny.gov <<EOF
subject: $tmp
from: david.novicoff@its.ny.gov

$machine
EOF

