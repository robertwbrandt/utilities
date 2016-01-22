#!/bin/bash
#
#     Script for quietly rebooting a OES Linux Server
#     Bob Brandt <projects@brandt.ie>
#          
version=0.2

SCRIPT=/opt/brandt/utilities/oes/restart.sh
RCSCRIPT=/usr/local/bin/restart

if [ ! "$( id -u )" == "0" ]; then
	echo "This program must be run as root!"
	sudo "$SCRIPT" $@
	exit 0
fi

test -x $RCSCRIPT || sudo ln -fs "$SCRIPT" "$RCSCRIPT"

confirm() {
	read -p "Are you sure you want to continue? (y/N): " ANSWER
	ANSWER=`echo ${ANSWER:=NO} | tr "[:upper:]" "[:lower:]"`
	test "${ANSWER:0:1}" == "y" && return 0
	return 1
}


usage() {
	[ "$2" == "" ] || echo -e "$2"
	echo -e "Usage: $0 [options]"
	echo -e " options:"
	echo -e "\t  -h, --help     display this help and exit"
	echo -e "\t  -v, --version  output version information and exit"
	/sbin/shutdown /? 2>&1 | sed -e "s|Usage:\t| options:|" -e "s|\t\t|\t|g"
	echo 
	/sbin/reboot /? 2>&1 | sed -e "s|usage:|\t|" -e "s|\t\t|\t|g"
	echo -e "\n\tWill reboot/shutdown a Novell OES server after closing all active Novell\n\tConnections (So the users will not receive a server shutdown message).\n\tThe default options are: shutdown -fr now"
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

case "$1" in
    -h | --help )       usage 0 ;;
    -v | --version )    version ;;
    shutdown | down )   shift 1 ; confirm && /opt/brandt/clearstationall && /sbin/shutdown $@ ;;
    reboot | restart )  shift 1 ; confirm && /opt/brandt/clearstationall && /sbin/reboot $@ ;;
    *) 	                confirm && /opt/brandt/clearstationall && /sbin/shutdown -fr now ;;
esac
