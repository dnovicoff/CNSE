import datetime
import _mysql
import MySQLdb
import sys
import re


con = _mysql.connect('localhost', 'root', '', 'UIDS')
con.query("SELECT VERSION()")
result = con.use_result()
print "MySQL version: %s" % \
        result.fetch_row()[0]

db = MySQLdb.connect(host="localhost",
			user="root",
			passwd="",
			db="UIDS")
cur = db.cursor()
newList = []
uidlist = {}

select = "SELECT * FROM uids"
cur.execute(select)
numrows = cur.rowcount
for x in xrange(0,numrows):
	row = cur.fetchone()
	if row[0] not in uidlist.keys():
		print "UID: |%s| NAME: |%s|" % (row[0],row[1])
		## uidlist[row[0]] = row[1]
		numrows = numrows

count = 0
for line in open('free_ids.txt','r').readlines():
	line = line.strip()
	line = line+" "
	splitLine = list(line)
	if splitLine:
		val = []
		string = ""
		for i in splitLine:
			extract = ""
			letter = re.search(r'(\w+)',i,re.IGNORECASE)
			if letter:
			 	extract = letter.group()
			if extract != "":
				val.append(i)
			else:
				str = ''.join(val)
				string += str+"-"
				val = []

		values = string.split("-")
		for i in values:
			if len(i) != 0:
				newList.append(i)


		uid = ""
		name = ""
		desc = ""
		a = 0
		b = newList.__len__()
		if newList.__len__() > 1:
			for i in newList:
				if a == 0:
					uid = i
				elif a == 1:
					name = i
				else:
					desc = desc+i+" "
				a = a + 1

			insert = "INSERT INTO uids VALUES ('%s','%s','%s')" % (uid,name,desc)
			tmp = re.search(r'(\d{2,})',uid,re.IGNORECASE)
			if uid not in uidlist.keys():
				if tmp:
					## print insert
					count = count + 1
					## cur.execute(insert)
			else:
				print "USER ID: %s CREATED\n" % (uid)
			uidlist[uid] = name
			newList = []


print "COUNT: %s\n" % (count)
