#!/bin/bash
#
#     Script to setup the LDAP sambaDomain Object
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

sambaDomainLDIF() {
	CAPsambadomain=$( echo "$1" | tr "[:lower:]" "[:upper:]" )
	echo -e "dn: "$( convertContext "ldap" "sambaDomainName=$CAPsambadomain.$2" )
	echo -e "changetype: add"
	echo -e "sambaNextUserRid: $3"
	echo -e "sambaSID: $4"
	echo -e "objectClass: sambaDomain"
	echo -e "objectClass: top"
	echo -e "sambaDomainName: $CAPsambadomain"
	echo -e "sambaAlgorithmicRidBase: $3"
}

sambaDomainLDAPSearch() {
	basecontext=$( convertContext "ldap" "$1" )
	searchfilter="$2"
	attrs="$3"
	adminuser=$( convertContext "ldap" "$CONFIG_SAMBA_PROXY_USER_CONTEXT" )
	ldapsearch -h "$CONFIG_SAMBA_LDAP_SERVER" -D "$adminuser" -w "$CONFIG_SAMBA_PROXY_USER_PASSWORD" -x -Z -b "$basecontext" -LLL "$searchfilter" "$attrs"
}

usage() {
	echo -e "Usage: $0 {status|setup}"
	exit ${1:-0}
}

case "$1" in
    ldif)
	sambaDomainLDIF "${2:-$CONFIG_SAMBA_WORKGROUP_NAME}" "${3:-$CONFIG_SAMBA_MACHINE_CONTEXT}" "${4:-$CONFIG_SAMBA_ALGORITHMIC_RID_BASE}" "${5:-$CONFIG_SAMBA_SID}"
	;;
    exists)
	rc_reset
	echo -n "Checking for this Server's sambaDomain object "
	test=$( sambaDomainLDAPSearch "${2:-$CONFIG_EDIR_SERVER_CONTEXT}" "${3:-(&(objectClass=sambaDomain)(sambaDomainName=$CONFIG_SAMBA_WORKGROUP_NAME))}" "${4:-dn}" )
	test -n "$test"
	rc_status -v
	;;
    duplicates)
	rc_reset
	echo -n "Making sure there are not duplicate sambaDomain objects "
	declare -i num=$( sambaDomainLDAPSearch "${2:-$CONFIG_SAMBA_USER_CONTEXT}" "${3:-(&(objectClass=sambaDomain)(sambaDomainName=$CONFIG_SAMBA_WORKGROUP_NAME))}" "${4:-dn}" | grep "dn" | wc -l )
	test $num -eq 1
	rc_status -v
	;;
    create)
	rc_reset
	echo -n "Installing this Server's sambaDomain object "
	adminuser=$( convertContext "ldap" "$CONFIG_SAMBA_PROXY_USER_CONTEXT" )
	$0 ldif | ldapmodify -a -h "$CONFIG_SAMBA_LDAP_SERVER" -D "$adminuser" -w "$CONFIG_SAMBA_PROXY_USER_PASSWORD" -x -Z > /dev/null
	rc_status -v
	;;
    status)
	$0 exists && $0 duplicates
	;;
    setup)
	$0 exists || $0 create
	;;
    usage|help|?|-?|-h|--help)
	usage 0
	;;
    *)
	usage 1
	;;
esac
rc_exit
