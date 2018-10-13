import datetime
import sys
import re
import os
from os import listdir
from os.path import isfile, join
from time import sleep

import smtplib
from email.MIMEMultipart import MIMEMultipart 
from email.MIMEBase import MIMEBase 
from email.MIMEText import MIMEText 
from email.Utils import COMMASPACE, formatdate 
from email import Encoders

from_addr = 'david.novicoff@its.ny.gov'
to_addr = 'its.dl.dch.linux@its.ny.gov'


today = datetime.date.today()
day = today.day
mon = today.month
year = today.year
if day < 10:
	day = "0"+str(day)

if mon < 10:
	mon = "0"+str(mon)

myfile = "vCenter-ITSM-%s%s%s.csv" % (year,mon,day)
mypath = "."
onlyfiles = [ f for f in listdir(mypath) if isfile(join(mypath,f)) ]

vCenter = {}
vCenterIP = {}
vCenterState = {}
vCenterToolsV = {}
vCenterVMStatus = {}
vCenterNIC = {}
vCenterAppliance = {}
itsm = {}
itsmIP = {}
file = -1

count = 0
for onlyfile in onlyfiles:
	tmp = re.search(r'vCenter(\d+).(csv)',onlyfile,re.IGNORECASE)
	if tmp:
		file = 0
	else:
		tmp = re.search(r'Linux-Servers-(ITSM).csv',onlyfile,re.IGNORECASE)
		if tmp:
			file = 1

	if file == 0:
		for line in open(onlyfile,'r').readlines():
			if count > 1:
				line = line.strip()
				line = re.sub(r'\"',r'',line)
				parts = line.split(',')
				name = parts[0].upper()
				os = parts[2]
				os = os.split(':')
				os = os[1]
				ip = parts[3]
				state = parts[1]
				tools = parts[4]
				status = parts[5]
				nic = parts[9]
				appliance = parts[8]
				if not vCenter.has_key(name):
					vCenter[name] = os
					vCenterIP[name] = ip
					vCenterState[name] = state
					vCenterToolsV[name] = tools
					vCenterVMStatus[name] = status
					vCenterNIC[name] = nic
					vCenterAppliance[name] = appliance

				## print "VCenter "+name+"  "+os+"  "+ip

			count = count + 1

	if file == 1:
		for line in open(onlyfile,'r').readlines():
			line = line.strip()
			line = re.sub(r'\"',r'',line)
			parts = line.split(',')
			if len(parts) > 34 and count > 0:
				name = parts[0].upper()
				os = parts[34]
				ip = parts[4]
	
				if not itsm.has_key(name):
					itsm[name] = os
					itsmIP[name] = ip

				## print "ITSM "+name+" "+os+" "+ip
			count = count + 1

	file = -1
	count = 0

f = open(myfile,'w')
f.write("ITSM Name,ITSM OS,ITSM IP,vCenter Name,vCenter OS,vCenter IP,vCenter State,vCenter Tools V,vCenter Status,vCenter NIC,vCenter Appliance\n")
for name in itsm:
	output = name+","+itsm[name]+","+itsmIP[name]
	if vCenter.has_key(name):
		output = output+","+name+","+vCenter[name]+","+vCenterIP[name]+","+vCenterState[name]+","+vCenterToolsV[name]+","+vCenterVMStatus[name]+","+vCenterNIC[name]+","+vCenterAppliance[name]+"\n"
		del vCenter[name]
	else:
		output = output+"\n"

	f.write(output)

for name in vCenter:
	output = ",,,"+name+","+vCenter[name]+","+vCenterIP[name]+","+vCenterState[name]+","+vCenterToolsV[name]+","+vCenterVMStatus[name]+vCenterNIC[name]+","+vCenterAppliance[name]+"\n"
	f.write(output)
f.close()
