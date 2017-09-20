#!/usr/bin/env python2.7
"""
Script for a outputing OES LDAP DHCP usage stats
"""
import argparse, textwrap, errno, json, syslog
import fnmatch, subprocess, re, datetime, bisect

# Import Brandt Common Utilities
import sys, os
sys.path.append( os.path.realpath( os.path.join( os.path.dirname(__file__), "/opt/brandt/common" ) ) )
import brandt
sys.path.pop()

version = 0.3
args = {}
args['output'] = 'text'
args['select'] = 'all'
args['leaseFile'] = '/var/lib/dhcp/db/dhcpd.leases'
args['configFile'] = '/etc/dhcpd.conf'
args['ldapConfigFile'] = '/var/log/dhcp-ldap-startup.log'
encoding = "utf-8"

class customUsageVersion(argparse.Action):
  def __init__(self, option_strings, dest, **kwargs):
    self.__version = str(kwargs.get('version', ''))
    self.__prog = str(kwargs.get('prog', os.path.basename(__file__)))
    self.__row = min(int(kwargs.get('max', 80)), brandt.getTerminalSize()[0])
    self.__exit = int(kwargs.get('exit', 0))
    super(customUsageVersion, self).__init__(option_strings, dest, nargs=0)
  def __call__(self, parser, namespace, values, option_string=None):
    # print('%r %r %r' % (namespace, values, option_string))
    if self.__version:
      print self.__prog + " " + self.__version
      print "Copyright (C) 2013 Free Software Foundation, Inc."
      print "License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>."
      version  = "This program is free software: you can redistribute it and/or modify "
      version += "it under the terms of the GNU General Public License as published by "
      version += "the Free Software Foundation, either version 3 of the License, or "
      version += "(at your option) any later version."
      print textwrap.fill(version, self.__row)
      version  = "This program is distributed in the hope that it will be useful, "
      version += "but WITHOUT ANY WARRANTY; without even the implied warranty of "
      version += "MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the "
      version += "GNU General Public License for more details."
      print textwrap.fill(version, self.__row)
      print "\nWritten by Bob Brandt <projects@brandt.ie>."
    else:
      print "Usage: " + self.__prog + " [-s SELECT] [-o OUTPUT]"
      print "\nScript for a outputing OES LDAP DHCP usage stats\n"
      print "Options:"
      options = []
      options.append(("-h, --help",           "Show this help message and exit"))
      options.append(("-v, --version",        "Show program's version number and exit"))
      options.append(("-s, --select SELECT",  "Select data to show [config|leases|pools|all]"))
      options.append(("-o, --output OUTPUT",  "How to display data [text|json|syslog]"))
      length = max( [ len(option[0]) for option in options ] )
      for option in options:
        description =  textwrap.wrap(option[1], (self.__row - length - 5))
        print "  " + option[0].ljust(length) + "   " + description[0]
        for n in range(1,len(description)): print " " * (length + 5) + description[n]
    exit(self.__exit)
def command_line_args():
  global args
  parser = argparse.ArgumentParser(add_help=False)
  parser.add_argument('-v', '--version', action=customUsageVersion, version=version, max=80)
  parser.add_argument('-h', '--help', action=customUsageVersion) 
  parser.add_argument('-o', '--output',
  					type=str, 
  					choices=['text','json','syslog'],
  					default=args['output'],
            required=False)
  parser.add_argument('-s', '--select', 
  					type=str, 
  					choices=['config','leases','pools','all'],
  					default=args['select'],  					
            required=False)  
  args.update(vars(parser.parse_args()))

##############################################################################

def parse_str(raw_str, length, err_str):
	tokens = raw_str.split()
	if len(tokens) == int(length):
		return tokens[int(length - 1)]
	else:
		raise Exception(str(err_str))

def parse_timestamp(raw_str):
	tokens = raw_str.split()
	if len(tokens) == 1 and tokens[0].lower() == 'never':
		return 'never';
	elif len(tokens) == 3:
		return datetime.datetime.strptime(' '.join(tokens[1:]), '%Y/%m/%d %H:%M:%S')
	raise Exception('Parse error in timestamp')

def timestamp_is_ge(t1, t2):
	try: return (t1 == 'never') or (t1 >= t2)
	except: return False

def timestamp_is_lt(t1, t2):
	try: return (t2 == 'never') or (t1 < t2)
	except: return False

def timestamp_is_between(t, tstart, tend):
	return timestamp_is_ge(t, tstart) and timestamp_is_lt(t, tend)

def parse_hardware(raw_str):
	return str(parse_str(raw_str, 2, 'Parse error in hardware')).upper()

def strip_endquotes(raw_str):
	return raw_str.strip('"')

def strip_endquotes_lower(raw_str):
	return raw_str.strip('"').lower()

def identity(raw_str):
	return raw_str

def parse_binding_state(raw_str):
	return parse_str(raw_str, 2, 'Parse error in binding state')

def parse_next_binding_state(raw_str):
	return parse_str(raw_str, 3, 'Parse error in binding state')

def parse_rewind_binding_state(raw_str):
	return parse_str(raw_str, 3, 'Parse error in binding state')	

def parse_leases_file(leases_file):
	valid_keys = {
		'starts':               parse_timestamp,
		'ends':                 parse_timestamp,
		'tstp':                 parse_timestamp,
		'tsfp':                 parse_timestamp,
		'atsfp':                parse_timestamp,
		'cltt':                 parse_timestamp,
		'hardware':             parse_hardware,
		'binding':              parse_binding_state,
		'next':                 parse_next_binding_state,
		'rewind':               parse_rewind_binding_state,
		'uid':                  strip_endquotes,
		'client-hostname':      strip_endquotes_lower,
		'option':               identity,
		'set':                  identity,
		'on':                   identity,
		'abandoned':            None,
		'bootp':                None,
		'reserved':             None,
		}

	leases_db = {}

	lease_rec = {}
	in_lease = False
	in_failover = False

	for line in leases_file:
		if line.lstrip().startswith('#'):
			continue

		tokens = line.split()

		if len(tokens) == 0:
			continue

		key = tokens[0].lower()

		if key == 'lease':
			if not in_lease:
				ip_address = tokens[1]

				lease_rec = {'ip_address' : ip_address}
				in_lease = True

			else:
				raise Exception('Parse error in leases file')

		elif key == 'failover':
			in_failover = True
		elif key == '}':
			if in_lease:
				for k in valid_keys:
					if callable(valid_keys[k]):
						lease_rec[k] = lease_rec.get(k, '')
					else:
						lease_rec[k] = False

				ip_address = lease_rec['ip_address']

				if ip_address in leases_db:
					leases_db[ip_address].insert(0, lease_rec)

				else:
					leases_db[ip_address] = [lease_rec]

				lease_rec = {}
				in_lease = False

			elif in_failover:
				in_failover = False
				continue
			else:
				raise Exception('Parse error in leases file')

		elif key in valid_keys:
			if in_lease:
				value = line[(line.index(key) + len(key)):]
				value = value.strip().rstrip(';').rstrip()

				if callable(valid_keys[key]):
					lease_rec[key] = valid_keys[key](value)
				else:
					lease_rec[key] = True

			else:
				raise Exception('Parse error in leases file')

		else:
			if in_lease:
				raise Exception('Parse error in leases file')

	if in_lease:
		raise Exception('Parse error in leases file')

	return leases_db


def round_timedelta(tdelta):
	return datetime.timedelta(tdelta.days, tdelta.seconds + (0 if tdelta.microseconds < 500000 else 1))

def timestamp_now():
	n = datetime.datetime.utcnow()
	return datetime.datetime(n.year, n.month, n.day, n.hour, n.minute, n.second + (0 if n.microsecond < 500000 else 1))

def lease_is_active(lease_rec, as_of_ts):
	return timestamp_is_between(as_of_ts, lease_rec['starts'], lease_rec['ends'])

def ipv4_to_int(ipv4_addr):
	parts = ipv4_addr.split('.')
	return (int(parts[0]) << 24) + (int(parts[1]) << 16) + (int(parts[2]) << 8) + int(parts[3])

def select_active_leases(leases_db, as_of_ts):
	retarray = []
	sortedarray = []

	for ip_address in leases_db:
		lease_rec = leases_db[ip_address][0]

		if lease_is_active(lease_rec, as_of_ts):
			ip_as_int = ipv4_to_int(ip_address)
			insertpos = bisect.bisect(sortedarray, ip_as_int)
			sortedarray.insert(insertpos, ip_as_int)
			retarray.insert(insertpos, lease_rec)

	return retarray

def parse_pools(config_file):
	pattern = r'.*?pool\s*{(.*?)}'
	return re.findall(pattern, config_file, re.DOTALL)

def parse_range(range_string):
	pattern = r'\s*range\s*[a-zA-Z\-]*\s*([0-9\.]*?)\s*([0-9\.]*?);.*'
	return re.findall(pattern, pool, re.DOTALL)

##############################################################################


# Start program
if __name__ == "__main__":
	command_line_args()

	myfile = open(args['leaseFile'], 'r')
	leases = parse_leases_file(myfile)
	myfile.close()

	myfile = open(args['configFile'], 'r')
	config = str(myfile.read())
	myfile.close()

	try:
		myfile = open(args['ldapConfigFile'], 'r')
		config += str(myfile.read())
	finally:	
		myfile.close()

	now = timestamp_now()
	report_dataset = select_active_leases(leases, now)
	report_pools = []
	for pool in parse_pools(config):
	        for ip_range in parse_range(pool):
			start_num = ipv4_to_int(ip_range[0])
			end_num = ipv4_to_int(ip_range[1])
			report_pools.append({"start-ip":ip_range[0], \
					     "end-ip":ip_range[1] , \
				             "start-num":start_num, \
					     "end-num":end_num, \
					     "total":(end_num - start_num) + 1, \
					     "active":0})

	for lease in report_dataset:
		for pool in report_pools:
			ip_num = ipv4_to_int(lease['ip_address'])
			if ip_num >= pool["start-num"] and ip_num <= pool["end-num"]:
				pool["active"] += 1

	if args['output'] == 'text':
		if args['select'] in ['all','config']:
			print('+------------------------------------------------------------------------------')
			print('| DHCPD CONFIG PARAMETERS')
			print('+-----------------+-------------------+----------------------+-----------------')
			for line in config.splitlines():
				print('| ' + line)

		if args['select'] in ['all','leases']:
			print('+------------------------------------------------------------------------------')
			print('| DHCP ACTIVE LEASES REPORT')
			print('+-----------------+-------------------+----------------------+-----------------')
			print('| IP Address      | MAC Address       | Expires (days,H:M:S) | Client Hostname ')
			print('+-----------------+-------------------+----------------------+-----------------')
			for lease in report_dataset:
				print('| ' + format(lease['ip_address'], '<15') + ' | ' + \
					format(lease['hardware'], '<17') + ' | ' + \
					format(str((lease['ends'] - now) if lease['ends'] != 'never' else 'never'), '>20') + ' | ' + \
					lease['client-hostname'])


			print('+-----------------+-------------------+----------------------+-----------------')
			print('| Total Active Leases: ' + str(len(report_dataset)))


		if args['select'] in ['all','pools']:
			print('+-----------------+-------------------+----------------------+-----------------')
			print('| DHCP POOL STATUS REPORT')
			print('+-----------------+-------------------+----------------------+-----------------')
			print('| Range Start     | Range End         |        Active Leases | Total Size      ')
			print('+-----------------+-------------------+----------------------+-----------------')

			active_leases = 0
			total_leases = 0
			for pool in report_pools:
				print('| ' + format(pool["start-ip"], '<15') + ' | ' + \
			                     format(pool["end-ip"], '<17') + ' | ' + \
			                     format(str(pool["active"]), '>20') + ' | ' + \
			                     str(pool["total"]))
				active_leases += pool["active"]
				total_leases  += pool["total"]

			print('+-----------------+-------------------+----------------------+-----------------')
			print('|                               Total | ' + \
			                     format(str(active_leases), '>20') + ' | ' + \
			                     str(total_leases))
			print('+-------------------------------------+----------------------+-----------------')


		print('| Report generated (UTC): ' + str(now))
		print('+------------------------------------------------------------------------------')
	elif args['output'] in ['json','syslog']:
		output = {}
		if args['select'] in ['all','leases']:
			output['leases'] = {}
			for lease in report_dataset:
				output['leases'].update({lease['ip_address']:{'hardware': lease['hardware'],
															 			                'expire': str(lease['ends']),
															 			                'client-hostname': lease['client-hostname']}})									 
		if args['select'] in ['all','pools']:
			output['pools'] = {}
			for pool in report_pools:
				tmp = pool["start-ip"] + '-' + pool["end-ip"]
				output['pools'].update({tmp: {'pool':tmp, 'active':pool["active"], 'total':pool["total"]}})

		if args['output'] == 'json':
			print json.dumps(output)
		else:
			syslog.openlog('dhcp-pools')
			for pool in output['pools']:
				syslog.syslog(json.dumps({"dhcp":output['pools'][pool]}))
			syslog.closelog()
