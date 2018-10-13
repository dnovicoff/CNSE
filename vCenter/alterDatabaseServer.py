import datetime
import _mysql
import MySQLdb
import sys
import re
from os import listdir
from os.path import isfile, join
from time import sleep

mypath = "."
onlyfiles = [ f for f in listdir(mypath) if isfile(join(mypath,f)) ]
records = {}
ip = {}
countV = 0
for onlyfile in onlyfiles:
	tmp = re.search(r'vCenter(\d+).(csv)',onlyfile,re.IGNORECASE)
	if tmp:
		for line in open(onlyfile,'r').readlines():
			line = line.strip()
 			line = re.sub(r'\"',r'',line)
			tmp = re.search(r'^(Name,|,)',line,re.IGNORECASE)
			if not tmp and line:
				lineSp = line.split(",")
				if lineSp:
					ipSplit = lineSp[3].split(" ")
					ips = {}
					for ipS in ipSplit:
						if not ips.has_key(ipS):
							ips[ipS] = ipS
					ip[lineSp[0].upper()] = ips

					records[lineSp[0].upper()] = lineSp[0].upper()
					countV = countV + 1

con = _mysql.connect('localhost', 'root', '', 'servers')
con.query("SELECT VERSION()")
result = con.use_result()
print "MySQL version: %s" % \
        result.fetch_row()[0]

db = MySQLdb.connect(host="localhost",
			user="root",
			passwd="",
			db="servers")
cur = db.cursor()

servers = {}
file = ""
count = 0
selectServer = "SELECT * FROM server WHERE ITSM = 0"
cur.execute(selectServer)
countS = 0
for (id,name,recorded,ITSM,osID) in cur:
	servers[name] = id
	countS = countS + 1

for vName in servers:
	if not records.has_key(vName):
		id = servers[vName]
		delete = "DELETE FROM server WHERE serverID = %s" % (id)
		deleteIP = "DELETE FROM serverIP WHERE serverID = %s" % (id)
		cur.execute(delete)
		cur.execute(deleteIP)
		count = count + 1

print str(count)+" FILE: "+str(countV)+"  SERVERS: "+str(countS)

for vName in records:
	id = 0
	if not servers.has_key(vName):
		insert = "INSERT INTO server (name,recorded,ITSM) VALUES ('%s',Now(),0)" % (vName)
		print insert
		cur.execute(insert)
		id = cur.lastrowid

		tmp = ip[vName]
		for t in tmp:
			if t:
				insert = "INSERT INTO serverIP VALUES (%s,'%s',Now())" % (id,t)
				print insert
				cur.execute(insert)




