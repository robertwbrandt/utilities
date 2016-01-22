#!/bin/bash
#
#     Script to setup the custom Samba smb.conf file
#     Bob Brandt <projects@brandt.ie>
#          

. /etc/rc.status

EDIR_CONF="/etc/opt/novell/eDirectory/conf/nds.conf"
SAMBA_DIR="/etc/samba"
SAMBA_CONF="$SAMBA_DIR/smb.conf"
SAMBA_SMBD="$SAMBA_DIR/smb.d"
TEMPLATE_SMB="/opt/brandt/templates/samba"
TEMPLATE_SMB_CONF="$TEMPLATE_SMB/smb.conf"
TEMPLATE_SMBD="$TEMPLATE_SMB/smb.d"
LUM_SYSCONFIG="/etc/sysconfig/novell/lum2_sp2"
SAMBA_SYSCONFIG="/etc/sysconfig/novell/nvlsamba2_sp2"
test -f "$SAMBA_SYSCONFIG" || SAMBA_SYSCONFIG="/etc/sysconfig/novell/nvlsamba2_sp3"
test -f "$LUM_SYSCONFIG" || LUM_SYSCONFIG="/etc/sysconfig/novell/lum2_sp3"

defaultsambapasswd="SambaR0cks"

test -f "$EDIR_CONF" || { echo "$EDIR_CONF not installed";  exit 6; }
test -f "$SAMBA_CONF" || { echo "$SAMBA_CONF not installed";  exit 6; }
test -f "$LUM_SYSCONFIG" || { echo "$LUM_SYSCONFIG not installed";  exit 6; }
test -f "$SAMBA_SYSCONFIG" || { echo "$SAMBA_SYSCONFIG not installed";  exit 6; }

. "$LUM_SYSCONFIG"
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

get_input() {
	read -p "$1: " ANSWER
	test -z "$ANSWER" && ANSWER="$2"
	test "$3" == "lower" && ANSWER=$( tolower "$ANSWER" )
	test "$3" == "upper" && ANSWER=$( toupper "$ANSWER" )
	echo "$ANSWER"
}

modify_sysconfig() {
	variable="$1"
	value="\"$2\""
	type="$3"
	if [ -n "$4" ]; then
		default="$4"
		test "$type" == "string" && default="\"$default\""
	else
		default="none"
	fi
	description="$5"

	if grep "\s*$variable" "$SAMBA_SYSCONFIG" > /dev/null 2>&1
	then
		sed -i "s|\s*$variable\s*=\s*.*|$variable=$value|" "$SAMBA_SYSCONFIG"
	else
		echo -e "\n## Path:\tSystem/Yast2/novell-samba\n## Description:\tNovell Samba configuration (extra switch added by Bob Brandt (projects@brandt.ie)" >> "$SAMBA_SYSCONFIG"
		echo -e "## Type:\t$type" >> "$SAMBA_SYSCONFIG"
		echo -e "## Default:\t$default" >> "$SAMBA_SYSCONFIG"
		echo -e "#\n# $description\n#\n#" >> "$SAMBA_SYSCONFIG"
		echo -e "$variable=$value\n" >> "$SAMBA_SYSCONFIG"
	fi
}

check_ldap_object() {
	LDAP_OBJECT=$( convertContext ldap "$1" )
	LDAP_FILTER=${2:-"(objectClass=*)"}
	CONFIG_SAMBA_LDAP_SERVER=${CONFIG_SAMBA_LDAP_SERVER:="127.0.0.1"}
	ldapsearch -h "$CONFIG_SAMBA_LDAP_SERVER" -s base -b "$LDAP_OBJECT" -x -Z -LLL "$LDAP_FILTER" 1.1 > /dev/null 2>&1
	return $?
}

is_subcontext() {
	subcontext=$( tolower $( convertContext edir "$1" ) )
	context=$( tolower $( convertContext edir "$2" ) )
	declare -i subcontextlen=${#subcontext}
	declare -i contextstart=$( expr ${#context} - $subcontextlen )

	test "$subcontext" == "${context:$contextstart}"
	return $?
}

remove_subcontext() {
	subcontext=$( tolower $( convertContext edir "$1" ) )
	context=$( tolower $( convertContext edir "$2" ) )
	declare -i subcontextlen=${#subcontext}
	declare -i contextlen=$( expr ${#context} - $subcontextlen - 1)

	echo "${context:0:$contextlen}"
}



get_defaults() {
	NDSSERVERCONTEXT=$( tolower $( sed -n "s|n4u.nds.server-context\s*=\s*||pI" "$EDIR_CONF" ) )
	NDSBASE=$( tolower $( echo "$NDSSERVERCONTEXT" | sed "s|.*\.\s*||" ) )
	TMP_HOSTNAME=$( tolower "${HOSTNAME:0:11}" )
	TMP_PROPER_HOSTNAME=$( toproper "$TMP_HOSTNAME" )

	SERVICE_CONFIGURED=${SERVICE_CONFIGURED:="yes"}
	CONFIG_SAMBA_LDAP_SERVER=$( tolower ${CONFIG_SAMBA_LDAP_SERVER:="127.0.0.1"} )
	CONFIG_SAMBA_INTERFACE=$( tolower ${CONFIG_SAMBA_INTERFACE:=""} )
	CONFIG_SAMBA_NETBIOS_NAME=$( tolower ${CONFIG_SAMBA_NETBIOS_NAME:="$TMP_HOSTNAME-pdc"} )
	CONFIG_SAMBA_WORKGROUP_NAME=$( tolower ${CONFIG_SAMBA_WORKGROUP_NAME:="$TMP_HOSTNAME-dom"} )
	CONFIG_SAMBA_SERVER_STRING=${CONFIG_SAMBA_SERVER_STRING:="$TMP_PROPER_HOSTNAME PDC Server (Samba %v)"}
	CONFIG_SAMBA_SID=$( toupper ${CONFIG_SAMBA_SID:="S-1-5-21-0-0-0"} )
	CONFIG_SAMBA_ALGORITHMIC_RID_BASE=${CONFIG_SAMBA_ALGORITHMIC_RID_BASE:="1000"}
	CONFIG_SAMBA_LUM_CONTEXT=$( tolower ${CONFIG_SAMBA_LUM_CONTEXT:="$CONFIG_LUM_WS_CONTEXT"} )
	CONFIG_EDIR_SERVER_CONTEXT=$( tolower ${CONFIG_EDIR_SERVER_CONTEXT:="$NDSSERVERCONTEXT"} )
	CONFIG_SAMBA_USER_CONTEXT=$( tolower ${CONFIG_SAMBA_USER_CONTEXT:="$NDSBASE"} )
	CONFIG_SAMBA_DEFAULT_BASE_CONTEXT=$( tolower ${CONFIG_SAMBA_DEFAULT_BASE_CONTEXT:="OU=Samba.$CONFIG_EDIR_SERVER_CONTEXT"} )
	CONFIG_SAMBA_PROXY_USER_CONTEXT=$( tolower ${CONFIG_SAMBA_PROXY_USER_CONTEXT:="CN=SambaAdmin.$CONFIG_SAMBA_DEFAULT_BASE_CONTEXT"} )
	CONFIG_SAMBA_PROXY_USER_PASSWORD=${CONFIG_SAMBA_PROXY_USER_PASSWORD:="$defaultsambapasswd"}
	CONFIG_SAMBA_GROUP_CONTEXT=$( tolower ${CONFIG_SAMBA_GROUP_CONTEXT:=$( echo "$CONFIG_EDIR_SERVER_CONTEXT" | sed "s|\.\s*$CONFIG_SAMBA_USER_CONTEXT||I" )} )
	CONFIG_SAMBA_MACHINE_CONTEXT=$( tolower ${CONFIG_SAMBA_MACHINE_CONTEXT:=$( echo "$CONFIG_SAMBA_DEFAULT_BASE_CONTEXT" | sed "s|\.\s*$CONFIG_SAMBA_USER_CONTEXT||	I" )} )
	CONFIG_SAMBA_DOMAIN_ADMINS_GROUP_CONTEXT=$( tolower ${CONFIG_SAMBA_DOMAIN_ADMINS_GROUP_CONTEXT:="CN=Domain Admins.$CONFIG_SAMBA_DEFAULT_BASE_CONTEXT"} )
	CONFIG_SAMBA_DOMAIN_USERS_GROUP_CONTEXT=$( tolower ${CONFIG_SAMBA_DOMAIN_USERS_GROUP_CONTEXT:="CN=Domain Users.$CONFIG_SAMBA_DEFAULT_BASE_CONTEXT"} )
	CONFIG_SAMBA_DOMAIN_GUESTS_GROUP_CONTEXT=$( tolower ${CONFIG_SAMBA_DOMAIN_GUESTS_GROUP_CONTEXT:="CN=Domain Guests.$CONFIG_SAMBA_DEFAULT_BASE_CONTEXT"} )
	CONFIG_SAMBA_DOMAIN_COMPUTERS_GROUP_CONTEXT=$( tolower ${CONFIG_SAMBA_DOMAIN_COMPUTERS_GROUP_CONTEXT:="CN=Domain Computers.$CONFIG_SAMBA_DEFAULT_BASE_CONTEXT"} )
	CONFIG_SAMBA_TEST_USER=$( tolower ${CONFIG_SAMBA_TEST_USER:="scanner"} )
	CONFIG_SAMBA_TEST_PASSWORD=${CONFIG_SAMBA_TEST_PASSWORD:="scanner"}
	CONFIG_SAMBA_TEST_SHARE=$( tolower ${CONFIG_SAMBA_TEST_SHARE:="scanner$"} )
}

print_error() {
	declare -i errorcode=$1
	value="$2"
	errormessage="$3"
	test $errorcode -ne 0 && echo -en "${redbold}"
	echo -e "$value"
	test $errorcode -ne 0 && echo -e "$errormessage${normal}"
}

verify_info() {
	echo -e "\n\nWe are about to use this information for the Samba Setup."
	echo -en "\tWorkgroup = "
		host "$CONFIG_SAMBA_WORKGROUP_NAME" > /dev/null 2>&1
		print_error $? "$CONFIG_SAMBA_WORKGROUP_NAME" "\t\tUnable to resolve DNS name!"
	echo -en "\tNetbios Name = "
		host "$CONFIG_SAMBA_NETBIOS_NAME" > /dev/null 2>&1
		print_error $? "$CONFIG_SAMBA_NETBIOS_NAME" "\t\tUnable to resolve DNS name!"
	echo -e "\tServer String = $CONFIG_SAMBA_SERVER_STRING"
	echo -en "\tLDAP Server = "
		ldapsearch -h "$CONFIG_SAMBA_LDAP_SERVER" -x -Z -s one -LLL 1.1 > /dev/null 2>&1
		print_error $? "$CONFIG_SAMBA_LDAP_SERVER" "\t\tThe LDAP Server is not reachable."
	echo -en "\tLDAP Admin DN = "
		check_ldap_object "$CONFIG_SAMBA_PROXY_USER_CONTEXT" "(objectClass=person)"
		print_error $? "$CONFIG_SAMBA_PROXY_USER_CONTEXT" "\t\tThis user does not exist!"
	echo -e "\tLDAP Admin PW = $CONFIG_SAMBA_PROXY_USER_PASSWORD"
	echo -en "\tLDAP User Context = "
		check_ldap_object "$CONFIG_SAMBA_USER_CONTEXT"
		print_error $? "$CONFIG_SAMBA_USER_CONTEXT" "\t\tThis context does not exist!"
	echo -en "\tLDAP Group Context = "
		if ! check_ldap_object "$CONFIG_SAMBA_GROUP_CONTEXT"
		then
			print_error 1 "$CONFIG_SAMBA_GROUP_CONTEXT" "\t\tThis context does not exist!"
		else
			is_subcontext "$CONFIG_SAMBA_USER_CONTEXT" "$CONFIG_SAMBA_GROUP_CONTEXT"
			print_error $? "$CONFIG_SAMBA_GROUP_CONTEXT" "\t\tThis context is not a sub context of $CONFIG_SAMBA_USER_CONTEXT!"
		fi
	echo -en "\tLDAP Machine Context = "
		if ! check_ldap_object "$CONFIG_SAMBA_MACHINE_CONTEXT"
		then
			print_error 1 "$CONFIG_SAMBA_MACHINE_CONTEXT" "\t\tThis context does not exist!"
		else
			is_subcontext "$CONFIG_SAMBA_USER_CONTEXT" "$CONFIG_SAMBA_MACHINE_CONTEXT"
			print_error $? "$CONFIG_SAMBA_MACHINE_CONTEXT" "\t\tThis context is not a sub context of $CONFIG_SAMBA_USER_CONTEXT!"
		fi
	echo -en "\tNetwork Interface = "
		( ping -c 1 $CONFIG_SAMBA_INTERFACE &&  ip a | grep -ie " $CONFIG_SAMBA_INTERFACE/" ) > /dev/null 2>&1
		print_error $? "$CONFIG_SAMBA_INTERFACE" "\t\tThis interface is not present or not responding.!"
	echo -e "\tSamba SID = $CONFIG_SAMBA_SID"
	echo -e "\tSamba Algorithmic RID Base = $CONFIG_SAMBA_ALGORITHMIC_RID_BASE"
	echo -en "\tServer Context = "
		check_ldap_object "$CONFIG_EDIR_SERVER_CONTEXT"
		print_error $? "$CONFIG_EDIR_SERVER_CONTEXT" "\t\tThis context does not exist!"
	echo -en "\tSamba Context = "
		check_ldap_object "$CONFIG_SAMBA_DEFAULT_BASE_CONTEXT"
		print_error $? "$CONFIG_SAMBA_DEFAULT_BASE_CONTEXT" "\t\tThis context does not exist!"
	echo -en "\tDomain Admins Group = "
		check_ldap_object "$CONFIG_SAMBA_DOMAIN_ADMINS_GROUP_CONTEXT" "(objectClass=groupOfNames)"
		print_error $? "$CONFIG_SAMBA_DOMAIN_ADMINS_GROUP_CONTEXT" "\t\tThis group does not exist!"
	echo -en "\tDomain Users Group = "
		check_ldap_object "$CONFIG_SAMBA_DOMAIN_USERS_GROUP_CONTEXT" "(objectClass=groupOfNames)"
		print_error $? "$CONFIG_SAMBA_DOMAIN_USERS_GROUP_CONTEXT" "\t\tThis group does not exist!"
	echo -en "\tDomain Guests Group = "
		check_ldap_object "$CONFIG_SAMBA_DOMAIN_GUESTS_GROUP_CONTEXT" "(objectClass=groupOfNames)"
		print_error $? "$CONFIG_SAMBA_DOMAIN_GUESTS_GROUP_CONTEXT" "\t\tThis group does not exist!"
	echo -en "\tDomain Computers Group = "
		check_ldap_object "$CONFIG_SAMBA_DOMAIN_COMPUTERS_GROUP_CONTEXT" "(objectClass=groupOfNames)"
		print_error $? "$CONFIG_SAMBA_DOMAIN_COMPUTERS_GROUP_CONTEXT" "\t\tThis group does not exist!"
	echo -e "\tSamba Test Username = $CONFIG_SAMBA_TEST_USER"
	echo -e "\tSamba Test User Password = $CONFIG_SAMBA_TEST_PASSWORD"
	echo -e "\tSamba Test Share = $CONFIG_SAMBA_TEST_SHARE"

	ANSWER=$( get_input "Is this information correct? (yes/No/Exit)" "n" "lower" )
	ANSWER=${ANSWER:0:1}
}

get_info() {
	CONFIG_SAMBA_WORKGROUP_NAME=$( get_input "Samba Workgroup ($CONFIG_SAMBA_WORKGROUP_NAME)" "$CONFIG_SAMBA_WORKGROUP_NAME" "lower" )
	CONFIG_SAMBA_NETBIOS_NAME=$( get_input "Samba NetBIOS Name ($CONFIG_SAMBA_NETBIOS_NAME)" "$CONFIG_SAMBA_NETBIOS_NAME" "lower" )
	CONFIG_SAMBA_SERVER_STRING=$( get_input "Samba Server Comments ($CONFIG_SAMBA_SERVER_STRING)" "$CONFIG_SAMBA_SERVER_STRING" "" )
	CONFIG_SAMBA_LDAP_SERVER=$( get_input "Samba LDAP Server ($CONFIG_SAMBA_LDAP_SERVER)" "$CONFIG_SAMBA_LDAP_SERVER" "lower" )
	CONFIG_SAMBA_PROXY_USER_CONTEXT=$( convertContext edir $( get_input "Samba LDAP Admin ($CONFIG_SAMBA_PROXY_USER_CONTEXT)" "$CONFIG_SAMBA_PROXY_USER_CONTEXT" "lower" ) )
	CONFIG_SAMBA_PROXY_USER_PASSWORD=$( get_input "Samba LDAP Admin Password ($CONFIG_SAMBA_PROXY_USER_PASSWORD)" "$CONFIG_SAMBA_PROXY_USER_PASSWORD" "" )
	CONFIG_SAMBA_USER_CONTEXT=$( convertContext edir $( get_input "Samba Base LDAP Context ($CONFIG_SAMBA_USER_CONTEXT)" "$CONFIG_SAMBA_USER_CONTEXT" "lower" ) )
	CONFIG_SAMBA_GROUP_CONTEXT=$( convertContext edir $( get_input "Samba LDAP Group Context ($CONFIG_SAMBA_GROUP_CONTEXT)" "$CONFIG_SAMBA_GROUP_CONTEXT" "lower" ) )
	CONFIG_SAMBA_MACHINE_CONTEXT=$( convertContext edir $( get_input "Samba LDAP Computer Context ($CONFIG_SAMBA_MACHINE_CONTEXT)" "$CONFIG_SAMBA_MACHINE_CONTEXT" "lower" ) )

	IPADDRESSES=$(  ifconfig | grep -i "inet addr" | grep -v "127.0.0" | sed -e "s|\s*inet addr:||gI" -e "s|\s*Bcast.*||gI" -e "s|\s*Mask.*||gI" )
	declare -i NUMIPADDRESSES=$( ifconfig | grep -i "inet addr" | grep -v "127.0.0" | wc -l )
	if [ $NUMIPADDRESSES -gt 1 ]; then
		PS3="Which IP Address would you like to use for Samba? "
		select CONFIG_SAMBA_INTERFACE in $IPADDRESSES; do break; done
	else
		CONFIG_SAMBA_INTERFACE=$IPADDRESSES
	fi

	CONFIG_SAMBA_SID=$( get_input "Samba Domain SID ($CONFIG_SAMBA_SID)" "$CONFIG_SAMBA_SID" "upper" )
	declare -i CONFIG_SAMBA_ALGORITHMIC_RID_BASE=$( get_input "Samba Algorithmic RID Base ($CONFIG_SAMBA_ALGORITHMIC_RID_BASE)" "$CONFIG_SAMBA_ALGORITHMIC_RID_BASE" "" )
	CONFIG_SAMBA_DOMAIN_ADMINS_GROUP_CONTEXT=$( convertContext edir $( get_input "Samba Domain Admins Group Context ($CONFIG_SAMBA_DOMAIN_ADMINS_GROUP_CONTEXT)" "$CONFIG_SAMBA_DOMAIN_ADMINS_GROUP_CONTEXT" "lower" ) )
	CONFIG_SAMBA_DOMAIN_USERS_GROUP_CONTEXT=$( convertContext edir $( get_input "Samba Domain Users Group Context ($CONFIG_SAMBA_DOMAIN_USERS_GROUP_CONTEXT)" "$CONFIG_SAMBA_DOMAIN_USERS_GROUP_CONTEXT" "lower" ) )
	CONFIG_SAMBA_DOMAIN_GUESTS_GROUP_CONTEXT=$( convertContext edir $( get_input "Samba Domain Guests Group Context ($CONFIG_SAMBA_DOMAIN_GUESTS_GROUP_CONTEXT)" "$CONFIG_SAMBA_DOMAIN_GUESTS_GROUP_CONTEXT" "lower" ) )
	CONFIG_SAMBA_DOMAIN_COMPUTERS_GROUP_CONTEXT=$( convertContext edir $( get_input "Samba Domain Computers Group Context ($CONFIG_SAMBA_DOMAIN_COMPUTERS_GROUP_CONTEXT)" "$CONFIG_SAMBA_DOMAIN_COMPUTERS_GROUP_CONTEXT" "lower" ) )

	CONFIG_SAMBA_TEST_USER=$( get_input "Samba Test Username ($CONFIG_SAMBA_TEST_USER)" "$CONFIG_SAMBA_TEST_USER" "lower" )
	CONFIG_SAMBA_TEST_PASSWORD=$( get_input "Samba Test User Password ($CONFIG_SAMBA_TEST_PASSWORD)" "$CONFIG_SAMBA_TEST_PASSWORD" "" )
	CONFIG_SAMBA_TEST_SHARE=$( get_input "Samba Test Share ($CONFIG_SAMBA_TEST_SHARE)" "$CONFIG_SAMBA_TEST_SHARE" "lower" )
}

copy_smbd() {
	echo "Copy smb.d directory contents"
	cp -ai "$TEMPLATE_SMBD" "$SAMBA_DIR"

	# Find all the mounted nss volumes
	for NSSVOL in `sed -n "s|\snssvol\s|&|pI" /etc/fstab | cut -f 1 -d " " | sort -u`; do
		# Add the share information if it is not already present
		if ! grep -i "^\[$NSSVOL\]" "$SAMBA_SMBD/services" > /dev/null 2>&1
		then
			NSSVOLPROPER=$( toproper "$NSSVOL" )
			NSSVOLLOWER=$( tolower "$NSSVOL" )	
			MNTPOINT=$( sed -n "s|^$NSSVOL\s*.*\snssvol\s|&|pI" /etc/fstab | tail -n 1 | sed -e "s|\s*nssvol.*||I" -e "s|$NSSVOL\s*||I" )
			echo -e "\n[$NSSVOLLOWER]\n\tcomment = Novell $NSSVOLPROPER NSS Volume\n\tpath = $MNTPOINT\n" >> "$SAMBA_SMBD/services"
		fi
	done

	cat "$SAMBA_SMBD/services"
	ANSWER=$( get_input "${bold}Is this share information correct? (Yes/no)${normal}" "y" "lower" )
	ANSWER=${ANSWER:0:1}
	[ "$ANSWER" != "y" ] && nano "$SAMBA_SMBD/services"

	cat "$SAMBA_SMBD/scanner"
	ANSWER=$( get_input "${bold}Is this scanner information correct? (Yes/no)${normal}" "y" "lower" )
	ANSWER=${ANSWER:0:1}
	[ "$ANSWER" != "y" ] && nano "$SAMBA_SMBD/scanner"
}


update_sysconfig() {
	modify_sysconfig "SERVICE_CONFIGURED" "yes" "yesno" "no" "Novell Samba successfully configured"
	modify_sysconfig "CONFIG_SAMBA_LDAP_SERVER" "$CONFIG_SAMBA_LDAP_SERVER" "string" "" "eDirectory LDAP Server address"
	modify_sysconfig "CONFIG_SAMBA_INTERFACE" "$CONFIG_SAMBA_INTERFACE" "string" "" "Samba Interface"
	modify_sysconfig "CONFIG_SAMBA_NETBIOS_NAME" "$CONFIG_SAMBA_NETBIOS_NAME" "string" "" "Netbios Name"
	modify_sysconfig "CONFIG_SAMBA_WORKGROUP_NAME" "$CONFIG_SAMBA_WORKGROUP_NAME" "string" "" "Samba Workgroup/Domain Name"
	modify_sysconfig "CONFIG_SAMBA_SERVER_STRING" "$CONFIG_SAMBA_SERVER_STRING" "string" "" "Samba Server String"
	modify_sysconfig "CONFIG_SAMBA_SID" "$CONFIG_SAMBA_SID" "string" "S-1-5-21-0-0-0" "Base Samba Domain Security ID"
	modify_sysconfig "CONFIG_SAMBA_ALGORITHMIC_RID_BASE" "$CONFIG_SAMBA_ALGORITHMIC_RID_BASE" "string" "1000" "Base Samba Algorithmic RID"
	modify_sysconfig "CONFIG_SAMBA_LUM_CONTEXT" "$CONFIG_SAMBA_LUM_CONTEXT" "string" "" "LUM workstation context"
	modify_sysconfig "CONFIG_EDIR_SERVER_CONTEXT" "$CONFIG_EDIR_SERVER_CONTEXT" "string" "" "Novell server context"
	modify_sysconfig "CONFIG_SAMBA_DEFAULT_BASE_CONTEXT" "$CONFIG_SAMBA_DEFAULT_BASE_CONTEXT" "string" "" "Default base Context for Samba objects"
	modify_sysconfig "CONFIG_SAMBA_PROXY_USER_CONTEXT" "$CONFIG_SAMBA_PROXY_USER_CONTEXT" "string" "cn=SambaAdmin...." "Proxy user name with context (e.g. cn=proxy.o=novell)"
	modify_sysconfig "CONFIG_SAMBA_PROXY_USER_PASSWORD" "$CONFIG_SAMBA_PROXY_USER_PASSWORD" "string" "" "Proxy user password"
	modify_sysconfig "CONFIG_SAMBA_PROXY_USER_NEW" "no" "yesno" "no" "Proxy user is a new user or existing user"
	modify_sysconfig "CONFIG_SAMBA_USER_CONTEXT" "$CONFIG_SAMBA_USER_CONTEXT" "string" "" "Base context for Samba users (e.g. ou=site.o=novell)"
	modify_sysconfig "CONFIG_SAMBA_GROUP_CONTEXT" "$CONFIG_SAMBA_GROUP_CONTEXT" "string" "" "Base context for Samba groups (e.g. ou=groups.ou=samba.o=novell)"
	modify_sysconfig "CONFIG_SAMBA_MACHINE_CONTEXT" "$CONFIG_SAMBA_MACHINE_CONTEXT" "string" "" "Base context for Samba machines (e.g. ou=computers.ou=samba.o=novell)"
	modify_sysconfig "CONFIG_SAMBA_DOMAIN_ADMINS_GROUP_CONTEXT" "$CONFIG_SAMBA_DOMAIN_ADMINS_GROUP_CONTEXT" "string" "" "Domain Admins group with context (e.g. cn=Domain Admins.o=novell)"
	modify_sysconfig "CONFIG_SAMBA_DOMAIN_USERS_GROUP_CONTEXT" "$CONFIG_SAMBA_DOMAIN_USERS_GROUP_CONTEXT" "string" "" "Domain Users group with context (e.g. cn=Domain Users.o=novell)"
	modify_sysconfig "CONFIG_SAMBA_DOMAIN_GUESTS_GROUP_CONTEXT" "$CONFIG_SAMBA_DOMAIN_GUESTS_GROUP_CONTEXT" "string" "" "Domain Guests group with context (e.g. cn=Domain Guests.o=novell)"
	modify_sysconfig "CONFIG_SAMBA_DOMAIN_COMPUTERS_GROUP_CONTEXT" "$CONFIG_SAMBA_DOMAIN_COMPUTERS_GROUP_CONTEXT" "string" "" "Domain Computers group with context (e.g. cn=Domain Computers.o=novell)"
	modify_sysconfig "CONFIG_SAMBA_TEST_USER" "$CONFIG_SAMBA_TEST_USER" "string" "" "Samba Test Username"
	modify_sysconfig "CONFIG_SAMBA_TEST_PASSWORD" "$CONFIG_SAMBA_TEST_PASSWORD" "string" "" "Samba Test User Password"
	modify_sysconfig "CONFIG_SAMBA_TEST_SHARE" "$CONFIG_SAMBA_TEST_SHARE" "string" "" "Samba Test Share"
}

write_smb_conf() {
	cp -af "$TEMPLATE_SMB_CONF" "$SAMBA_CONF"
	echo -e "\n\tinclude = $SAMBA_SMBD/printers" >> "$SAMBA_CONF"
	echo -e "\tinclude = $SAMBA_SMBD/services" >> "$SAMBA_CONF"
	for includefile in $( ls "$SAMBA_SMBD" | grep -v "\(printers\|services\|~\)" )
	do
		echo -e "\tinclude = $SAMBA_SMBD/$includefile" >> "$SAMBA_CONF"		
	done

	sed -i "s|\s*workgroup\s*=.*|\tworkgroup = $CONFIG_SAMBA_WORKGROUP_NAME|I" "$SAMBA_CONF"
	sed -i "s|\s*netbios name\s*=.*|\tnetbios name = $CONFIG_SAMBA_NETBIOS_NAME|I" "$SAMBA_CONF"
	sed -i "s|\s*server string\s*=.*|\tserver string = $CONFIG_SAMBA_SERVER_STRING|I" "$SAMBA_CONF"
	sed -i "s|\s*passdb backend\s*=.*|\tpassdb backend = NDS_ldapsam:ldaps://$CONFIG_SAMBA_LDAP_SERVER:636|I" "$SAMBA_CONF"

	tmp=$( convertContext ldap "$CONFIG_SAMBA_PROXY_USER_CONTEXT" )
	sed -i "s|\s*ldap admin dn\s*=.*|\tldap admin dn = $tmp|I" "$SAMBA_CONF"

	tmpusr=$( convertContext ldap "$CONFIG_SAMBA_USER_CONTEXT" )
	sed -i "s|\s*ldap suffix\s*=.*|\tldap suffix = $tmpusr|I" "$SAMBA_CONF"

	tmp=$( remove_subcontext "$tmpusr" "$CONFIG_SAMBA_GROUP_CONTEXT" )
	tmp=$( convertContext ldap "$tmp" )
	sed -i "s|\s*ldap group suffix\s*=.*|\tldap group suffix = $tmp|I" "$SAMBA_CONF"

	tmp=$( remove_subcontext "$tmpusr" "$CONFIG_SAMBA_MACHINE_CONTEXT" )
	tmp=$( convertContext ldap "$tmp" )
	sed -i "s|\s*ldap machine suffix\s*=.*|\tldap machine suffix = $tmp|I" "$SAMBA_CONF"

	sed -i "s|\s*interfaces\s*=.*|\tinterfaces = $CONFIG_SAMBA_INTERFACE|I" "$SAMBA_CONF"
	sed -i "s|\s*socket address\s*=.*|\tsocket address = $CONFIG_SAMBA_INTERFACE|I" "$SAMBA_CONF"
}

usage() {
	echo -e "Usage: $0 {status|setup}"
	exit ${1:-0}
}

case "$1" in
    status)
	rc_reset
	echo -n "Novell eDirectory nds.conf file exists "
	test -f "$EDIR_CONF"
	rc_status -v

	rc_reset
	echo -n "Samba smb.conf file exists "
	test -f "$SAMBA_CONF"
	rc_status -v	
	;;
    setup)
	get_defaults
	ANSWER="n"
	while [ "$ANSWER" != "y" ]; do
		verify_info
		test "$ANSWER" == "e" && exit 0
		test "$ANSWER" == "x" && exit 0
		test "$ANSWER" == "n" && get_info
	done

	copy_smbd

	rc_reset
	echo -n "Update Novell Samba sysconfig file "
	update_sysconfig
	rc_status -v

	rc_reset
	echo -n "Write Samba smb.conf file "
	write_smb_conf
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
