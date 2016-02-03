#!/bin/bash
#
#     Script for converting a LDIF file to a txt file by adding a 
#     break at the 78th character.
#     Bob Brandt <projects@brandt.ie>
#
declare -i maxlen=77
version=0.1

#SCRIPT=/opt/brandt/ldif2txt
#RCSCRIPT=/usr/local/bin/ldif2txt
#test -x $RCSCRIPT || sudo ln -s "$SCRIPT" "$RCSCRIPT"

usage() {
	[ "$2" == "" ] || echo -e "$2"
	echo -e "Usage: $0 [options] [filenames]"
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

if [ -z "$1" ]; then
	tmp=$( cat )
	declare -i c=$maxlen
	while [ $c -lt $( echo -e "$tmp" | wc -L ) ]; do
		tmp=$( echo -e "$tmp" | sed "s|^\(.\{$c\}\)|\1 |g" )
		c=$(($c + $maxlen))
	done
	tmp=$( echo -e "$tmp" | sed "s|[[:space:]]*$||g" | fold -w $maxlen )
	echo -e "$tmp"
else
	while [ -n "$1" ]; do
		tmp=$( cat "$1" )
		declare -i c=$maxlen
		while [ $c -lt $( echo -e "$tmp" | wc -L ) ]; do
			tmp=$( echo -e "$tmp" | sed "s|^\(.\{$c\}\)|\1 |g" )
			c=$(($c + $maxlen))
		done
		tmp=$( echo -e "$tmp" | sed "s|[[:space:]]*$||g" | fold -w $maxlen )
		echo -e "$tmp"
		shift 1
	done
fi
exit $?
