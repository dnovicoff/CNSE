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
cur2 = db.cursor()
cur3 = db.cursor()

clusters = {}
servers = {}
file = -1
serverID = 0
selectCluster = "SELECT * FROM cluster"
cur.execute(selectCluster)
for (clusterID,cluster) in cur:
	clusters[cluster] = clusterID
	print str(clusterID)+"  "+cluster

count = 0
for onlyfile in onlyfiles:
	print onlyfile
	tmp = re.search(r'Linux-Servers-ITSM.csv',onlyfile,re.IGNORECASE)
	if tmp:
		file = 1

	if file == 1:
		for line in open(onlyfile,'r').readlines():
			tmp = re.search(r'Name,',line,re.IGNORECASE)
			if not tmp:
				line = line.strip()
				line = re.sub(r'\"',r'',line)
				parts = line.split(',')
				if len(parts) > 10:
					parts[0] = parts[0].upper()
					name = parts[0]
					servers[name] = name
					osID = 0
					osName = parts[34]
					dns = parts[7]
					toolsV = parts[6]
					vmxID = 0
	
					if parts[2]:
						os = parts[2].split(':')
						if len(os) > 1:
							osName = os[1]

					selectServer = "SELECT * FROM server WHERE name LIKE '%s' AND ITSM = %s" % ('%'+parts[0]+'%',file)
					insertServer = "INSERT INTO server (name,recorded,ITSM) VALUES ('%s',Now(),%s)" % (parts[0],file)
					selectOS = "SELECT * FROM os WHERE name = '%s'" % (osName)
					insertOS = "INSERT INTO os (name) VALUES ('%s')" % (osName)
					selectDNS = "SELECT * FROM dns WHERE name = '%s'" % (dns)
					insertDNS = "INSERT INTO dns (name) VALUES ('%s')" % (dns)
					selectVMX = "SELECT * FROM vmx WHERE name = '%s'" % (toolsV)
					insertVMX = "INSERT INTO vmx (name) VALUES ('%s')" % (toolsV)
					rows = cur.execute(selectServer)
					osRows = cur2.execute(selectOS)
					vmxRows = cur3.execute(selectVMX)

					if not vmxRows:
						tst = ""
						## cur3.execute(insertVMX)
						## vmxID = cur3.lastrowid
					else:
						data = cur3.fetchone()
						vmxID = data[0]

					if not osRows:
						cur2.execute(insertOS)
						osID = cur2.lastrowid
					else:
						res2 = cur2.fetchone()
						osID = res2[0]
	
					if file == 1 and parts:
						if not rows and not (name == "NAME" and not name == ""):
							count = count+1
							print insertServer
							cur.execute(insertServer)
						if rows:
							data = cur.fetchone()
							serverID = data[0]
							updateOS = "UPDATE server SET osID = %s,vmxID = %s WHERE serverID = %s" % (osID,vmxID,data[0])
							cur2.execute(updateOS)
							ips = parts[4].split(' ')
							for ip in ips:
								if len(ip) > 4:
									insertIP = "INSERT INTO serverIP (serverID,IP,recorded) VALUES (%s,'%s',Now()) ON DUPLICATE KEY UPDATE IP = '%s'" % (data[0],ip,ip)
									cur.execute(insertIP)
					else:
						print "Did not find record"
	file = -1

select = "SELECT serverID,name FROM server WHERE ITSM = 1"
cur.execute(select)
for (serverID,name) in cur:
	if not servers.has_key(name):
		delete = "DELETE FROM server WHERE serverID = %s" % (serverID)
		cur.execute(delete)
		print str(serverID)+"  "+name

print str(count)
