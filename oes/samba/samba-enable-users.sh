#!/bin/bash
#
#     Script to Samba enable LDAP Users
#     Bob Brandt <projects@brandt.ie>
#          

SAMBA_CONF="/etc/samba/smb.conf"
EDIR_SETUP_CONF="/etc/sysconfig/novell/oes-ldap"
SAMBA_SYSCONFIG="/etc/sysconfig/novell/nvlsamba2_sp*"

. $EDIR_SETUP_CONF
. $SAMBA_SYSCONFIG
. /etc/rc.status

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

get_input() {
	if [ -n "$4" ]; then
		read -s -p "$1: " ANSWER
		echo 1>&2
	else
		read -p "$1: " ANSWER
	fi
	test -z "$ANSWER" && ANSWER="$2"
	test "$3" == "lower" && ANSWER=$( tolower "$ANSWER" )
	test "$3" == "upper" && ANSWER=$( toupper "$ANSWER" )
	echo "$ANSWER"
}

ldif2txt() {
	cat "$2" | perl -p00e 's/\r?\n //g'
}

txt2ldif() {
	declare -i ldiflen=77
	declare -i c=$ldiflen
	tmp=$( cat "$2" )
	while [ $c -lt $( echo -e "$tmp" | wc -L ) ]; do
		tmp=$( echo -e "$tmp" | sed "s|^\(.\{$c\}\)|\1 |g" )
		c=$(($c + $ldiflen))
	done
	tmp=$( echo -e "$tmp" | sed "s|[[:space:]]*$||g" | fold -w $ldiflen )
	echo -e "$tmp" 
}

getUID() {
	user=$( tolower $( convertContext "ldap" "$1" ) )
	if [ "${user:0:3}" == "cn=" ]; then
		filter="(objectClass=person)"
		base=$( convertContext "ldap" "$user" )
	else
		filter="(&(objectClass=person)(cn=$user))"
	fi
	user=$( ldapsearch -h "$host" -x -Z -b "$base" -s "sub" -LLL "$filter" 1.1 | perl -p00e 's/\r?\n //g' | sed -n 's|^dn:\s||Ip' | sort -fu )
	case $( echo "$user" | wc -l ) in 
	    1 ) test -z "$user" && echo "The username entered is not valid!" 1>&2 && sleep 1
		user="$user" ;;
	    * ) PS3="The username entered matches multiple DNs. Please select one: "
		IFS=$'\n'
		user=$( echo -e "{None}\n$user" )
		select user in $user; do 
			test "$user" == "{None}" && user=
			break
		done
		;;
	esac
	echo "$user"
}

getldapusername() {
	defaultbase="$base"
	prompt="Enter the Administrator username"
	test -n "$1" && prompt="$prompt ($1)"
	while [ -z "$adminuser" ]; do
		adminuser=$( getUID $( get_input "$prompt" "$1" "lower") )
	done
	echo $adminuser
}
getpassword() {
	echo $( get_input "Enter the Password for $1" "" "" "password")
}

listusers() {
	filter="(&(objectclass=posixAccount)(objectClass=uamPosixUser)(objectClass=person)(uid=*)(!(objectClass=sambaSamAccount))(!(givenName=System))(!(cn=*admin*)))"
	case "$1" in
	    any )	filter="(&(objectClass=person)(!(givenName=System))(!(cn=*admin*)))" ;;
	    mail )	filter="(&(objectClass=person)(mail=*))" ;;
	    lum )	filter="(&(objectclass=posixAccount)(objectClass=uamPosixUser)(objectClass=person)(uid=*)(!(givenName=System))(!(cn=*admin*)))" ;;
	    samba ) 	filter="(&(objectclass=posixAccount)(objectClass=uamPosixUser)(objectClass=person)(uid=*)(objectClass=sambaSamAccount)(!(givenName=System))(!(cn=*admin*)))" ;;
	    nonsamba )	filter="(&(objectclass=posixAccount)(objectClass=uamPosixUser)(objectClass=person)(uid=*)(!(objectClass=sambaSamAccount))(!(givenName=System))(!(cn=*admin*)))" ;;
	    * )	filter="(&(objectClass=person)(cn=$1))" ;;
	esac
	ldapsearch -h "$host" -x -Z -b "$base" -s "sub" -LLL "$filter" 1.1 | perl -p00e 's/\r?\n //g' | sed -n 's|^dn:\s||Ip' | sort -fu
}

checkuser() {
	test -n "$1" && base=$( getUID "$1" )
	if [ -n "$base" ]; then
		tmp=$( ldapsearch -h "$host" -x -Z -b "$base" -s "base" -LLL "(objectClass=person)" "objectClass" | perl -p00e 's/\r?\n //g' )

		echo "Checking Schema extentions for object $base"
		rc_reset
		echo -n "objectClass: inetOrgPerson "
		echo "$tmp" | egrep -i "^objectClass:[[:space:]]*inetOrgPerson$" > /dev/null
		personStatus=$? ; [ $personStatus -eq 0 ]
		rc_status -v

		rc_reset
		echo -n "objectClass: organizationalPerson "
		echo "$tmp" | egrep -i "^objectClass:[[:space:]]*organizationalPerson" > /dev/null
		rc_status -v

		rc_reset
		echo -n "objectClass: person "
		echo "$tmp" | egrep -i "^objectClass:[[:space:]]*person" > /dev/null
		rc_status -v

		rc_reset
		echo -n "objectClass: posixAccount "
		echo "$tmp" | egrep -i "^objectClass:[[:space:]]*posixAccount" > /dev/null
		posixStatus=$? ; [ $posixStatus -eq 0 ]
		rc_status -v

		rc_reset
		echo -n "objectClass: uamPosixUser "
		echo "$tmp" | egrep -i "^objectClass:[[:space:]]*uamPosixUser" > /dev/null
		rc_status -v

		rc_reset
		echo -n "objectClass: sambaSamAccount "
		echo "$tmp" | egrep -i "^objectClass:[[:space:]]*sambaSamAccount" > /dev/null
		sambaStatus=$? ; [ $sambaStatus -eq 0 ]
		rc_status -v

		rc_reset
		echo -n "objectClass: zarafa-user "
		echo "$tmp" | egrep -i "^objectClass:[[:space:]]*zarafa-user" > /dev/null
		rc_status -v

		rc_reset
		echo -n "objectClass: instantMessage "
		echo "$tmp" | egrep -i "^objectClass:[[:space:]]*instantMessage" > /dev/null
		rc_status -v

		[ $personStatus -eq 0 ] && [ $posixStatus -eq 0 ] && [ $sambaStatus -eq 0 ] && return 0
		[ $personStatus -eq 0 ] && [ $posixStatus -eq 0 ] && return 1
		[ $personStatus -eq 0 ]  && return 2
		return 3
	fi
	return 4
}

sambaenable() {
	dn="$1"
	adminuser="$2"
	adminpass="$3"
	checkuser "$dn" > /dev/null 2> /dev/null
	tmp=$?
	case $tmp in
	    0 ) echo "The user ($dn) is already Samba enabled." 1>&2 ; return 1 ;;
	    1 ) echo "" ;;
	    2 ) echo "The user ($dn) is not LUM enabled." 1>&2 ; return 2 ;;
	    * ) echo "The user ($dn) does not exist." 1>&2 ; return 2 ;;
	esac

	tmp=$( ldapsearch -h "$host" -D "$adminuser" -w "$adminpass" -x -Z -b "$dn" -s "base" -LLL "(objectClass=person)" uidNumber uid cn | perl -p00e 's/\r?\n //g' )

	uidNumber=$( echo "$tmp" | sed -n 's|^uidNumber:\s*||Ip' )
	uid=$( echo "$tmp" | sed -n 's|^uid:\s*||Ip' )
	cn=$( tolower $( echo "$tmp" | sed -n 's|^cn:\s*||Ip' | head -n 1 ) )

	tmp="dn: $dn"
	tmp="$tmp\r\nchangetype: modify"
	tmp="$tmp\r\nadd: objectClass"
	tmp="$tmp\r\nobjectClass: sambaSamAccount"
	test -z "$uid" && tmp="$tmp\r\n-\r\nadd: uid\r\nuid: $cn"
	tmp="$tmp\r\n-\r\nadd: sambaSID"
	tmp="$tmp\r\nsambaSID: S-1-5-21-0-0-0-$uidNumber"
	# RID Listing
	# http://www.samba.org/samba/docs/man/Samba-HOWTO-Collection/groupmapping.html
	tmp="$tmp\r\n-\r\nadd: sambaPrimaryGroupSID"
	tmp="$tmp\r\nsambaPrimaryGroupSID: S-1-5-21-0-0-0-513"
	tmp="$tmp\r\n-\r\nadd: sambaAcctFlags"
	tmp="$tmp\r\nsambaAcctFlags: [UX         ]\r\n"

#	echo -e "$tmp\n\n"

	rc_reset
	echo -n "Extending Schema for ($cn) "
	echo -e "$tmp" > test.ldif
	cat test.ldif | ldapmodify -avv -h "$host" -D "$adminuser" -w "$adminpass" -x -Z 
	rc_status -v
	return $?
}



usage() {
	echo -e "Usage: $0 [username password]"
	exit ${1:-0}
}

host="$CONFIG_SAMBA_LDAP_SERVER"
filter="(&(objectclass=posixAccount)(objectClass=uamPosixUser)(objectClass=person)(uid=*)(!(objectClass=sambaSamAccount))(!(givenName=System))(!(cn=*admin*)))"
base=$( convertContext ldap "$CONFIG_SAMBA_USER_CONTEXT" )
user=$( convertContext "ldap" "$CONFIG_SAMBA_PROXY_USER_CONTEXT" )
pass="$CONFIG_SAMBA_PROXY_USER_PASSWORD"

case "$1" in
    usage|help|-h|--help) usage 0 ;;
    --list | -l) listusers "$2" ;;
    --check | -c) 
	user=$( getUID "$2" )
	if [ -z "$user" ]; then
		echo "You must supply a valid username" 1>&2
	else
		checkuser "$user" 
	fi
	;;
    --enable | -e)
	adminuser=$( getldapusername "$user" )
	if [ $( tolower $( convertContext "ldap" "$adminuser" ) ) == $( tolower $( convertContext "ldap" "$user" ) ) ]; then
		adminpass="$pass"
	else
		adminpass=$( getpassword "$adminuser" )
	fi
	IFS=$'\n'
	for user in $( listusers "$2" )
	do
		sambaenable "$user" "$adminuser" "$adminpass"
	done
	
#	
	;;
esac

rc_exit	

