#!/bin/bash
#
#     Script to setup the LDAP Samba Admin User
#     Bob Brandt <projects@brandt.ie>
#          

. /etc/rc.status

SAMBA_CONF="/etc/samba/smb.conf"
EDIR_SETUP_CONF="/etc/sysconfig/novell/oes-ldap"
SAMBA_SYSCONFIG="/etc/sysconfig/novell/nvlsamba2_sp2"
test -f "$SAMBA_SYSCONFIG" || SAMBA_SYSCONFIG="/etc/sysconfig/novell/nvlsamba2_sp3"
txt2ldif="/opt/brandt/utilities/txt2ldif"
version=0.2


SCRIPT=/opt/brandt/utilities/oes/samba/samba-check.sh
RCSCRIPT=/usr/local/bin/samba-check

test -x $RCSCRIPT || sudo ln -sf "$SCRIPT" "$RCSCRIPT"

test -f "$SAMBA_CONF" || { echo "$SAMBA_CONF not installed";  exit 6; }
test -f "$SAMBA_SYSCONFIG" || { echo "$SAMBA_SYSCONFIG not installed";  exit 6; }
test -f "$EDIR_SETUP_CONF" || { echo "$EDIR_SETUP_CONF not installed";  exit 6; }

. "$EDIR_SETUP_CONF"
. "$SAMBA_SYSCONFIG"

tolower() { echo "$@" | tr "[:upper:]" "[:lower:]"; }
toupper() { echo "$@" | tr "[:lower:]" "[:upper:]"; }
toproper() { tmp=""; for arg in $@; do tmp="$tmp$( toupper ${arg:0:1} )$( tolower ${arg:1} ) "; done; echo "$tmp" | sed "s|\s*$||"; }

bold=`tput bold`
red=`tput setaf 1`
redbold=`tput bold; tput setaf 1`
normal=`tput sgr0`

convertContext() {
	tmp=$( tolower "$1" )
	shift 1
	if [ "$tmp" == "edir" ]; then
		echo "$@" | sed "s|\([^\\]\),|\1\.|g"
	else
		echo "$@" | sed "s|\([^\\]\)\.|\1,|g";
	fi	
}

getUsername() {
	tmp=$( convertContext "ldap" "$@" )
	echo "$tmp" | sed -e "s|^[^=]*=||" -e "s|\,.*$||"
}


get_permission() {
	read -p "$1 (y/N): " ANSWER
	test "$(echo ${ANSWER:0:1} | tr "[y]" "[Y]")" == "Y"
	return $?
}

get_admin_username() {
	test -f "$EDIR_SETUP_CONF" && . "$EDIR_SETUP_CONF" ; AdminUser=$( getUsername "$CONFIG_LDAP_ADMIN_CONTEXT" )
	test -n "AdminUser" && Prompt=" ($AdminUser)"
	Prompt="Please enter the Admin Username to create the objects$Prompt: "
	Answer=""
	while [ -z "$Answer" ]; do
		read -p "$Prompt" Answer
		test -z "$Answer" && Answer="$AdminUser"
		Answer=$(ldapsearch -LLL -h "$CONFIG_SAMBA_LDAP_SERVER" -s sub -x "(&(objectclass=Person)(cn=$Answer))" 1.1 | sed -n "s|^dn:\s||p" | head -n 1 )
	done

	echo "$Answer"
	return $?
}

get_admin_password() {
	read -s -p "Please enter the Password for ($1): " Answer
	echo "$Answer"
	return $?
}

sambaLDIF() {
	dn="$1"
	cn="$2"
	uidNumber="$3"

	echo -e "version: 1"
	echo -e "dn:  $dn"
	echo -e "changetype: modify"
	echo -e "add: objectClass"
	echo -e "objectClass: sambaSamAccount"
	echo -e "-"
	echo -e "replace: uid"
	echo -e "uid: $cn"
	echo -e "-"
	echo -e "replace: sambaAcctFlags"
	echo -e "sambaAcctFlags: [UX         ]"
	echo -e "-"
	echo -e "replace: sambaPrimaryGroupSID"
	echo -e "sambaPrimaryGroupSID: S-1-5-21-0-0-0-513"
	echo -e "-"
	echo -e "replace: sambaSID"
	echo -e "sambaSID: S-1-5-21-0-0-0-$uidNumber"
}

checkLinuxAttr() {
	rc_reset
	echo -n " Novell Linux user attributes"
	echo "$1" | grep -i "objectClass: posixAccount" > /dev/null 2>&1
	test "$?" == "0" || ( exit 3 )
	rc_status -v
}

checkSambaAttr() {
	rc_reset
	echo -n " Novell Samba user attributes"
	( echo "$1" | grep -i "objectClass: sambaSamAccount" && echo "$1" | grep "sambaAcctFlags: " && echo "$1" | grep "sambaPrimaryGroupSID: " && echo "$1" | grep "sambaSID: " ) > /dev/null 2>&1
	test "$?" == "0" || ( exit 3 )
	rc_status -v
}

checkServerAccess() {
	rc_reset
	echo -n " Check user access to server $HOSTNAME"
	id "$1" > /dev/null 2>&1
	rc_status -v
}

checkuser() {
	filter="$1"
	declare -i test1=1
	declare -i test2=1
	OLDIFS=$IFS
	IFS=$'\n'
	for user in $( ldapsearch -LLL -h "$CONFIG_SAMBA_LDAP_SERVER" -s sub -x "(&(objectclass=Person)$filter)" 1.1 | sed -n "s|^dn:\s||p" )
	do
		object=$( ldapsearch -LLL -h "$CONFIG_SAMBA_LDAP_SERVER" -s sub -b "$user" -x "(objectclass=Person)" objectClass zarafaAccount cn instantMessaging sambaAcctFlags sambaPrimaryGroupSID sambaSID)
		cn=$( echo "$object" | sed -n "s|cn:\s||p" | head -n 1 )

		echo "Checking user $user "
		checkLinuxAttr "$object"
		test1="$?"

		checkSambaAttr "$object"
		test2="$?"

		checkServerAccess "$cn"

	done
	IFS=$OLDIFS
	return $(( $test1 | $test2 ))
}

enableuser() {
	username=$( get_admin_username )
	password=$( get_admin_password "$username" ); echo

	filter="$1"
	OLDIFS=$IFS
	IFS=$'\n'
	for user in $( ldapsearch -LLL -h "$CONFIG_SAMBA_LDAP_SERVER" -s sub -x "(&(objectclass=Person)$filter)" 1.1 | sed -n "s|^dn:\s||p" )
	do
		object=$( ldapsearch -LLL -h "$CONFIG_SAMBA_LDAP_SERVER" -s sub -b "$user" -x "(objectclass=Person)" cn uidNumber )
		cn=$( echo "$object" | sed -n "s|cn:\s||p" | head -n 1 )
		uidNumber=$( echo "$object" | sed -n "s|uidNumber:\s||p" | head -n 1 )

		rc_reset
		echo -n "Checking samba user $cn "
		checkuser "(cn=$cn)" > /dev/null 2>&1
		declare -i test1="$?"
		test $test1 == 0
		rc_status -v
		if [ $test1 != 0 ]; then
			rc_reset
			echo -n " Modify user $cn for samba "
			test -n "$uidNumber" && sambaLDIF "$user" "$cn" "$uidNumber" | $txt2ldif | ldapmodify -F -h "$CONFIG_SAMBA_LDAP_SERVER" -D "$username" -w "$password" -x -Z > /dev/null
			rc_status -v
		fi
	done
	IFS=$OLDIFS
}

usage() {
	[ "$2" == "" ] || echo -e "$2"
	echo -e "Usage: $0 [options] [command]"
	echo -e "Commands:"
	echo -e " user username       Check all users matching the username (wildcards are ok)"
	echo -e " user (ldapfilter)   Check all users matching the ldap filter\n"
	echo -e " enable username     Samba enable all users matching the username"
	echo -e "                     (wildcards are ok)"
	echo -e " enable (ldapfilter) Samba enable all users matching the ldap filter\n"
	echo -e " login username {share} {server}"
	echo -e "                     Login as the user to test access. If password is not"
	echo -e "                     specified (or blank) it will ask. Share will default to "
	echo -e "                     Samba test share. Server will default to local Samba server"
	echo -e "Options:"
	echo -e " -h, --help     display this help and exit"
	echo -e " -v, --version  output version information and exit"	
	exit ${1:-0}
}

version() {
	echo -e "$0 $version"
	echo -e "Copyright (C) 2011 Free Software Foundation, Inc."
	echo -e "License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>."
	echo -e "This is free software: you are free to change and redistribute it."
	echo -e "There is NO WARRANTY, to the extent permitted by law.\n"
	echo -e "Written by Bob Brandt <projects@brandt.ie>."
	exit 0
}

# Execute getopt
ARGS=$(getopt -o vh -l "help,version" -n "$0" -- "$@") || usage 1 " "

#Bad arguments
#[ $? -ne 0 ] && usage 1 "$0: No arguments supplied!\n"

eval set -- "$ARGS";

while /bin/true ; do
	case "$1" in
    	-h | --help )     usage 0 ;;
    	-v | --version )  version ;;
    	-- )              shift ; break ;;
	    * )               usage 1 "$0: Invalid argument!\n" ;;
	esac
done

case "$1" in
    user)
		filter="$2"
		echo -e "$2" | grep "\=" > /dev/null || filter="(cn=$2)"
		checkuser "$filter"
	;;
    enable)
		filter="$2"
		echo -e "$2" | grep "\=" > /dev/null || filter="(cn=$2)"
		enableuser "$filter"
	;;
    login)
		username="${2:-$CONFIG_SAMBA_TEST_USER}"
		read -sp "Password for $username: " password; echo		
		share="${3:-$CONFIG_SAMBA_TEST_SHARE}"
		server="${4:-$CONFIG_SAMBA_NETBIOS_NAME}"
		test -z "$password" && password=$( get_admin_password "$username" ); echo

		echo -e "Testing if $username can connect to //$server/$share"
		echo -e smbclient -U \"$username\" \"//$server/$share\"
		smbclient -U "$username" -c "ls" "//$server/$share" "$password"
	;;
    *) usage 1 "$0: Invalid command!\n" ;;
esac
rc_exit
