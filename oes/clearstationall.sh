#!/bin/bash
#
#     Script for quietly rebooting a OES Linux Server
#     Bob Brandt <projects@brandt.ie>
#          
version=0.1

SCRIPT=/opt/brandt/utilities/oes/clearstationall.sh
RCSCRIPT=/usr/local/bin/clearstationall
test -x $RCSCRIPT || sudo ln -fs "$SCRIPT" "$RCSCRIPT"

usage() {
	[ "$2" == "" ] || echo -e "$2"
	echo -e "Usage: $0 [options]"
	echo -e "\tWill close all active Novell Connections"	
	echo -e "Options:"
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

declare -i SlotsAllocated=$(ncpcon connection 2>&1 | sed -ne "s|.*Connection Slots Allocated\t||pg")
for (( i=0 ; i <= SlotsAllocated ; i++ )); do
	ncpcon connection clear $i 1>/dev/null 2>&1 &
done
echo "All $SlotsAllocated connections cleared."
