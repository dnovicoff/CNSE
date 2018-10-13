import datetime
import _mysql
import MySQLdb
import sys
import re
import subprocess
from time import sleep

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

servers = {}
serverIDS = {}
count = 0

serverIP = "SELECT t1.serverID,t1.name,t2.IP FROM server AS t1,serverIP AS t2 " \
	"WHERE t1.serverID = t2.serverID ORDER BY t1.name"
cur.execute(serverIP)
for (id,name,ip) in cur:
	tmp = re.search(r'^\d',ip,re.IGNORECASE)
	if tmp:
		if not servers.has_key(name):
			servers[name] = ip
			serverIDS[name] = id
			count = count + 1

for name in servers:
	osID = 0
	ip = servers[name]
	id = serverIDS[name]
	print name+"   "+servers[name]
	process = subprocess.Popen("ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=no "+ip+" cat /etc/issue", shell=True,stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

	output,stderr = process.communicate()
	status = process.poll()
	if output:
		outputTMP = output.split("\n")
		tmp = re.search(r'^(ssh|Permission|Warning|\\S|You)',outputTMP[0],re.IGNORECASE)
		if not tmp:
			print outputTMP[0]
			selectOS = "SELECT * FROM os WHERE name = '%s'" % (outputTMP[0])
			row = cur.execute(selectOS)
			if not row:
				insertOS = "INSERT INTO os (name) VALUES ('%s')" % (outputTMP[0])
				print insertOS
				## cur2.execute(insertOS)
				## osID = cur2.lastrowid
			else:
				data = cur.fetchone()
				osID = data[0]

			if not osID == 0:
				updateServer = "UPDATE server SET osID = %s " \
						"WHERE serverID = %s" % (osID,id)
				print updateServer
				## cur2.execute(updateServer)

print str(count)
