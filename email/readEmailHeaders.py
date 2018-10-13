import smtplib
import socket
import re


hops = {}
hopCount = 1
hopPosition = 1
with open("emailOutput.txt", "r") as ins:
	print "SOURCE HOST,HOPS,HOP ORDER"
	for line in ins:
		line = line[:-2]
		## |Received: from its618pl5ecmicn02 (161.11.225.52) by|

		messageHop = re.search('Received:\sfrom\s(.+)\s\((.+)\)\s',line,re.IGNORECASE)
		if (messageHop):
			if not hops.has_key(hopCount):
				hops[hopCount] = messageHop.group(1)
			hopCount = hopCount + 1

		messageFrom = re.search('From:\sDavid\sNovicoff\s<dnovicoff@(.+)>',line,re.IGNORECASE)
		if (messageFrom):
			for hopPos in reversed(sorted(hops.keys())):
				print messageFrom.group(1)+","+hops[hopPos]+","+str(hopPosition)
				hopPosition = hopPosition + 1

			print "\n"
			hopPosition = 1
			hopCount = 1
			hops = {}

