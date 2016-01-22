#!/bin/bash
#
#     Script to setup the add a LDAP sambaWorkstation Object
#     Bob Brandt <projects@brandt.ie>
#          

. /etc/rc.status

SAMBA_CONF="/etc/samba/smb.conf"
SAMBA_SYSCONFIG="/etc/sysconfig/novell/nvlsamba2_sp2"
test -f "$SAMBA_SYSCONFIG" || SAMBA_SYSCONFIG="/etc/sysconfig/novell/nvlsamba2_sp3"

test -f "$SAMBA_CONF" || { echo "$SAMBA_CONF not installed";  exit 6; }
test -f "$SAMBA_SYSCONFIG" || { echo "$SAMBA_SYSCONFIG not installed";  exit 6; }

. "$SAMBA_SYSCONFIG"

convertContext() {
	tmp=$( echo "$1" | tr "[:upper:]" "[:lower:]" )
	if [ "$tmp" == "edir" ]; then
		echo "$2" | sed "s|\([^\\]\),|\1\.|g"
	else
		echo "$2" | sed "s|\([^\\]\)\.|\1,|g";
	fi	
}

sambaComputerLDIF() {
	CAPcomputer=$( echo "$1" | tr "[:lower:]" "[:upper:]" )

	echo -e "dn: "$( convertContext "ldap" "cn=$CAPcomputer.$2" )
	echo -e "changetype: add"
	echo -e "objectClass: top"
	echo -e "objectClass: computer"
	echo -e "objectClass: device"
#	echo -e "objectClass: inetOrgPerson"
#	echo -e "objectClass: organizationalPerson"
#	echo -e "objectClass: person"
#	echo -e "objectClass: ndsLoginProperties"
#	echo -e "uid: $CAPcomputer"
#	echo -e "givenName: System"
#	echo -e "sn: $CAPcomputer"
#	echo -e "fullName: Samba Machine Account"
	echo -e "cn: $CAPcomputer"
	echo -e "server: "$( convertContext "ldap" "$3" )
#	echo -e "memberOf: "$( convertContext "ldap" "$4" )
	echo -e "description: Samba Machine Account"
}

usage() {
	echo -e "Usage: $0 [status|add] computername"
	exit ${1:-0}
}

case "$1" in
    ldif)
	sambaComputerLDIF "$2" "${3:-$CONFIG_SAMBA_MACHINE_SUFFIX,$CONFIG_SAMBA_USER_CONTEXT}" "${4:-CN=$HOSTNAME.$CONFIG_EDIR_SERVER_CONTEXT}" "${5:-$CONFIG_SAMBA_DOMAIN_COMPUTERS_GROUP_CONTEXT}"
	;;
    add)
	test -z "$2" && usage 1;
	rc_reset
	echo -n "Installing a Computer object for ($2) "
	$0 ldif "$2" |  ldapmodify -a -h "$CONFIG_SAMBA_LDAP_SERVER" -D "$CONFIG_SAMBA_PROXY_USER_CONTEXT" -w "$CONFIG_SAMBA_PROXY_USER_PASSWORD" -x -Z > /dev/null
	rc_status -v
	;;
    status|check)
	test -z "$2" && usage 1;
	rc_reset
	echo -n "Checking for a Computer object for ($2) "
	test=$(ldapsearch -h "$CONFIG_SAMBA_LDAP_SERVER" -D "$CONFIG_SAMBA_PROXY_USER_CONTEXT" -w "$CONFIG_SAMBA_PROXY_USER_PASSWORD" -x -Z -b "$CONFIG_EDIR_SERVER_CONTEXT" -LLL "(&(objectClass=computer)(cn=$2))" dn )
	test -n "$test"
	rc_status -v
	;;
    usage|help|?|-?|-h|--help)
	usage 0
	;;
    *)
	usage 1
	;;
esac
rc_exit
