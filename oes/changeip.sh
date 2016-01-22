#!/bin/bash
#
#     Script for changing the IP Address of the server
#     Bob Brandt <projects@brandt.ie>
#          

tolower() { echo "$@" | tr "[:upper:]" "[:lower:]"; }
toupper() { echo "$@" | tr "[:lower:]" "[:upper:]"; }
toproper() { tmp=""; for arg in $@; do tmp="$tmp$( toupper ${arg:0:1} )$( tolower ${arg:1} ) "; done; echo "$tmp" | sed "s|\s*$||"; }

bold=`tput bold`
red=`tput setaf 1`
redbold=`tput bold; tput setaf 1`
normal=`tput sgr0`

SCRIPT=/opt/brandt/utilities/oes/changeip.sh
RCSCRIPT=/usr/local/bin/changeip

if [ ! "$( id -u )" == "0" ]; then
	echo "This program must be run as root!"
	sudo "$SCRIPT" $@
	exit 0
fi

test -x $RCSCRIPT || sudo ln -fs "$SCRIPT" "$RCSCRIPT"

get_input() {
	read -p "$1: " ANSWER
	test -z "$ANSWER" && ANSWER="$2"
	test "$3" == "lower" && ANSWER=$( tolower "$ANSWER" )
	test "$3" == "upper" && ANSWER=$( toupper "$ANSWER" )
	echo "$ANSWER"
}

get_ip() {
	IPADDRESSES=$( ifconfig | grep -i "inet addr" | grep -v "127.0.0" | sed -e "s|\s*inet addr:||gI" -e "s|\s*Bcast.*||gI" -e "s|\s*Mask.*||gI" | sort -u )
	IPADDRESSES="$IPADDRESSES Other None"
	PS3="Which IP Address would you like to change? "
	select FIND_IPADDRESS in $IPADDRESSES; do break; done

	case "$FIND_IPADDRESS" in
	"Other")	FIND_IPADDRESS=$( get_input "Enter Custom IP Address" ) ;;
	"None")		FIND_IPADDRESS="" ;;
	esac
	echo "$FIND_IPADDRESS"
}

get_mask() {
	SUBNETMASKS=$( ifconfig | grep -i "mask" | grep -v "127.0.0" | sed "s|.*mask:||gI" | sort -u )
	SUBNETMASKS="$SUBNETMASKS Other None"
	PS3="Which Subnet Mack would you like to change? "
	select FIND_SUBNETMASK in $SUBNETMASKS; do break; done

	case "$FIND_SUBNETMASK" in
	"Other")	FIND_SUBNETMASK=$( get_input "Enter Custom IP Address" ) ;;
	"None")		FIND_SUBNETMASK="" ;;
	esac
	echo "$FIND_SUBNETMASK"
}

get_gateway() {
	GATEWAYS=$( ip r | grep -i "via" | sed -e "s|.*via\s*||" -e "s|\s*dev.*||" | sort -u )
	GATEWAYS="$GATEWAYS Other None"
	PS3="Which Gateway would you like to change? "
	select FIND_GATEWAY in $GATEWAYS; do break; done

	case "$FIND_GATEWAY" in
	"Other")	FIND_GATEWAY=$( get_input "Enter Custom IP Address" ) ;;
	"None")		FIND_GATEWAY="" ;;
	esac
	echo "$FIND_GATEWAY"
}

replace_ip() {
	FIND="$1"
	REPLACE="$2"
	echo -e "\nReplacing all $FIND for $REPLACE"

	for file in $( ( find /etc -exec grep "$FIND" {} \; -print ) 2>/dev/null )
	do 
		if [ -f "$file" ]; then
			echo "Modifying file $file"
			sed -i "s|$FIND|$REPLACE|g" "$file"
		fi
	done

	for file in $( find /etc -iname "$FIND" )
	do 
		if [ -f "$file" ]; then
			echo "Renaming the file $file"
			mv "$file" "${file%/*}/$REPLACE"
		fi
	done
}

version=0.1
FIND_IPADDRESS=
FIND_SUBNETMASK=
FIND_GATEWAY=

usage() {
	[ "$2" == "" ] || echo -e "$2"
	echo -e "Usage: $0 [options]"
	echo -e "Options:"
	echo -e " -i, --ip       IP Address"	
	echo -e " -m, --mask     Subnet Mask"
	echo -e " -g, --gate     Default Gateway"	
	echo -e " -h, --help     display this help and exit"
	echo -e " -v, --version  output version information and exit"
	exit ${1-0}
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
ARGS=$(getopt -o i:m:g:vh -l "ip:,mask:,gate:,help,version" -n "$0" -- "$@") || usage 1 " "

#Bad arguments
#[ $? -ne 0 ] && usage 1 "$0: No arguments supplied!\n"

eval set -- "$ARGS";

while /bin/true ; do
	case "$1" in
    	-i | --ip )       FIND_IPADDRESS="$2" ; shift 2 ;;
    	-m | --mask )     FIND_SUBNETMASK="$2" ; shift 2 ;;
    	-g | --gate )     FIND_GATEWAY="$2" ; shift 2 ;;
    	-h | --help )     usage 0 ;;
    	-v | --version )  version ;;
    	-- )              shift ; break ;;
	    * )               usage 1 "$0: Invalid argument!\n" ;;
	esac
done

test -z "$FIND_IPADDRESS" && clear && FIND_IPADDRESS=$( get_ip )
test -z "$FIND_SUBNETMASK" && clear && FIND_SUBNETMASK=$( get_mask )
test -z "$FIND_GATEWAY" && clear && FIND_GATEWAY=$( get_gateway )

test -n "$FIND_IPADDRESS" && clear && REPLACE_IPADDRESS=$( get_input "Enter IP Address to replace $FIND_IPADDRESS" )
test -n "$FIND_SUBNETMASK" && clear && REPLACE_SUBNETMASK=$( get_input "Enter Subnet Mask to replace $FIND_SUBNETMASK" )
test -n "$FIND_GATEWAY" && clear && REPLACE_GATEWAY=$( get_input "Enter Gateway to replace $FIND_GATEWAY" )

test -n "$FIND_IPADDRESS" && replace_ip "$FIND_IPADDRESS" "$REPLACE_IPADDRESS"
test -n "$FIND_SUBNETMASK" && replace_ip "$FIND_SUBNETMASK" "$REPLACE_SUBNETMASK"
test -n "$FIND_GATEWAY" && replace_ip "$FIND_GATEWAY" "$REPLACE_GATEWAY"

echo -e "\n\nPleas verify that all the information below is correct!"
ip a
ip r
cat /etc/resolv.conf
