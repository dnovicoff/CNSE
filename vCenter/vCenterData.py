import datetime
import _mysql
import MySQLdb
import sys
import re
from os import listdir
from os.path import isfile, join
from time import sleep
from pysphere import VIServer

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

property_names = ['name', 'guest.toolsVersion', 'config.files.vmPathName']
serverVMToolVersion = {}

count = 0
clusters = {'10.127.209.21':1,'10.95.209.21':2,'10.64.211.139':3}
for ip in clusters:
	print ip
	server = VIServer()
	server.connect(ip,"nys\dnovicoff","pitIfu12345")

	serverType = server.get_server_type()
	print serverType

	serverAPI = server.get_api_version()
	print serverAPI

	vmlist = server.get_registered_vms()

	properties = server._retrieve_properties_traversal(property_names=property_names, obj_type="VirtualMachine")
	for propset in properties:
		vmToolsVersion = ""
		vmPropPath = ""
		host = ""
		for prop in propset.PropSet:
			if prop.Name == "name":
				host = prop.Val
			elif prop.Name == "guest.toolsVersion":
				vmToolsVersion = prop.Val
			elif prop.Name == "config.files.vmPathName":
				vmPropPath = prop.Val
		
		if not serverVMToolVersion.has_key(host):
			serverVMToolVersion[host] = vmToolsVersion

	for vms in vmlist:
		print vms
		vm = server.get_vm_by_path(vms)
		vmGuestFullName = vm.get_property('guest_full_name')
		if not re.search('Microsoft',vmGuestFullName,re.IGNORECASE):
			vmStatus = vm.get_status()
			print "VM STATUS: "+vmStatus
			guestID = vm.get_property('guest_id')
			print "VM GUEST ID: "+guestID
			vmPath = vm.get_property('path')
			print "VM PATH: "+vmPath
			vmName = vm.get_property('name')
			print "VM NAME: "+vmName
			print "VM GUEST FULL NAME: "+vmGuestFullName
			vmHostname = vm.get_property('hostname')
			print "VM HOSTNAME: "+str(vmHostname)
			vmCPU = vm.get_property('num_cpu')
			print "VM NUMBER CPU: "+str(vmCPU)
			vmMemory = vm.get_property('memory_mb')
			print "VM MEMORY: "+str(vmMemory)

			## properties = server._retrieve_properties_traversal(property_names=property_names, obj_type="VirtualMachine")
			## for propset in properties:
			##	vmToolsVersion = ""
			##	vmPropPath = ""
			##	for prop in propset.PropSet:
			##		if prop.Name == "guest.toolsVersion":
			##			vmToolsVersion = prop.Val
			##		elif prop.Name == "config.files.vmPathName":
			##			vmPropPath = prop.Val

			print "VM TOOLS VERSION: "+serverVMToolVersion[vmName]
			
			vmToolsStatus = vm.properties.guest.toolsVersionStatus
			print "VM TOOLS STATUS: "+vmToolsStatus
			vmMac = vm.get_property('mac_address')
			print "VM MAC: "+str(vmMac)
			vmIPAddress = vm.get_property('ip_address')
			print "VM IP Address: "+str(vmIPAddress)
			vmNet = vm.get_property('net')
			if vmNet:
				for network in vmNet:
					for net in network:
						print net
						if isinstance(network[net],(list)):
							for n in network[net]:
								print str(n)
						else:
							print str(network[net])
			vmRPN = vm.get_resource_pool_name() 
			print "VM RESOURCE POOL NAME: "+str(vmRPN)
			print "\n"
			count = count + 1
		
	server.disconnect()
	print "\n"


