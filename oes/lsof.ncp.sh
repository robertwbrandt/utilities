#!/bin/sh
#
#     Script for displaying all open NCP files
#     Bob Brandt <projects@brandt.ie>
#
bold=`tput bold`
red=`tput setaf 1`
redbold=`tput bold; tput setaf 1`
normal=`tput sgr0`

version=0.1
ncp=1
samba=1
declare -i maxlen=10
export maxlen

SCRIPT=/opt/brandt/lsof.ncp
RCSCRIPT=/usr/local/bin/lsof.ncp
test -x $RCSCRIPT || sudo ln -s "$SCRIPT" "$RCSCRIPT"

getncpfiles() {
	pattern="${1:-.*}"
	declare -i SlotsAllocated=$(ncpcon connection 2>&1 | sed -ne "s|.*Connection Slots Allocated\t||Ipg")
	echo -e "$boldUser Name\tConnection\tOpen File$normal"

	IFS_OLD="$IFS"
	IFS=$'\n'

	for (( connection=0 ; connection <= SlotsAllocated ; connection++ )); do
		if ncpcon connection $connection 2>&1 | grep -i "open files" > /dev/null
		then
			username=$(ncpcon connection $connection 2>&1 | sed -ne "s|.*name:\s*||Ipg")
			test ${#username} -gt $maxlen && maxlen=${#username}

			for filename in ` ncpcon connections $connection 2> /dev/null | sed '1,/open files/Id' | sed "s|^\s*||"`
			do
				echo "$filename" | grep -i "$pattern" 2>&1 > /dev/null && echo -e "$username\t$connection\t$filename"
			done

		fi
	done
	IFS="$IFS_OLD"
	echo "maxlen=$maxlen"
}

getsmbfiles() {
	pattern="${1:-.*}"
	output=$( smbstatus -L | sed -n '4~1p' )
	echo -e "$boldUser Name\tPID\tOpen File$normal"

	IFS_OLD="$IFS"
	IFS=$'\n'

	for line in $( echo -e "$output" ) ; do
		pid=$( echo "$line" | cut -d " " -f 1 ) ; line=$( echo "$line" | sed "s|[0-9]* *||" )
		uid=$( echo "$line" | cut -d " " -f 1 ) ; line=$( echo "$line" | sed "s|[0-9]* *||" )
		denymode=$( echo "$line" | cut -d " " -f 1 ) ; line=$( echo "$line" | sed "s|[^ ]* *||" )
		access=$( echo "$line" | cut -d " " -f 1 ) ; line=$( echo "$line" | sed "s|[^ ]* *||i" )
		rw=$( echo "$line" | cut -d " " -f 1 ) ; line=$( echo "$line" | sed "s|[^ ]* *||" )
		oplock=$( echo "$line" | cut -d " " -f 1 ) ; line=$( echo "$line" | sed "s|[^ ]* *||" )
		share=$( echo "$line" | cut -d " " -f 1 ) ; line=$( echo "$line" | sed "s|[^ ]* *||" )
		share=$(echo "$share/" | sed "s|//|/|g" )
		filename=$( echo "$line" | sed "s|   .*||" )

		if [ "$filename" != "." ] && [ -n "$filename" ] && [ "$( echo $pid | sed 's|[0-9]*|ok|')" == "ok" ] && [ "$( echo $uid | sed 's|[0-9]*|ok|')" == "ok" ]; then
			if username=$( getent passwd $uid )
			then
				username=$( echo $username | cut -d ":" -f 1 )
				test ${#username} -gt $maxlen && maxlen=${#username}

				echo "$share$filename" | grep -i "$pattern" 2>&1 > /dev/null && echo -e "$username\t$pid\t$share$filename"
			fi
		fi
	done

	IFS="$IFS_OLD"
	echo "maxlen=$maxlen"
}

usage() {
	[ "$2" == "" ] || echo -e "$2"
	echo -e "Usage: $0 [options] [pattern]"
	echo -e "\tWill show all open files matching [pattern]\n"

	echo -e "Options:"
	echo -e " -n, --ncp      Show only file open via NCP"
	echo -e " -s, --samba    Show only file open via Samba"
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
ARGS=$(getopt -o nsavh -l "ncp,samba,all,help,version" -n "$0" -- "$@") || usage 1 " "

#Bad arguments
#[ $? -ne 0 ] && usage 1 "$0: No arguments supplied!\n"

eval set -- "$ARGS";

while /bin/true ; do
	case "$1" in
    	-n | --ncp )      ncp=1 ; samba=0 ; shift ;;
    	-s | --samba )    ncp=0 ; samba=1 ; shift ;;
    	-h | --help )     usage 0 ;;
    	-v | --version )  version ;;
    	-- )              shift ; break ;;
	    * )               usage 1 "$0: Invalid argument!\n" ;;
	esac
done

if [ "$ncp" == "1" ]; then
	if /etc/init.d/novell-nss status 2>&1 > /dev/null
	then
		ncpfiles=$( getncpfiles "$*" )
		maxlen=$( echo -e "$ncpfiles" | sed -n 's|maxlen=||p' )
		ncpfiles=$( echo -e "$ncpfiles" | grep -v 'maxlen=' )
	else
		ncp=0
		echo -e "Novell NSS and NCP services are not running"
	fi
fi
if [ "$samba" == "1" ]; then
	if /etc/brandt/samba status 2>&1 > /dev/null
	then
		smbfiles=$( getsmbfiles "$*" )
		maxlen=$( echo -e "$smbfiles" | sed -n 's|maxlen=||p' )
		smbfiles=$( echo -e "$smbfiles" | grep -v 'maxlen=' )
	else
		samba=0
		echo -e "Samba services are not running"
	fi		
fi

IFS_OLD="$IFS"
IFS=$'\n'
format="%-$maxlen"s"\t%10s\t%s\n"
if [ "$ncp" == "1" ]; then
	for line in $( echo -e "$ncpfiles" )
	do
		printf "$format" $( echo -e "$line" | cut -f 1 ) $( echo -e "$line" | cut -f 2 ) $( echo -e "$line" | cut -f 3 )
	done
fi
echo ""
if [ "$samba" == "1" ]; then
	for line in $( echo -e "$smbfiles" )
	do
		printf "$format" $( echo -e "$line" | cut -f 1 ) $( echo -e "$line" | cut -f 2 ) $( echo -e "$line" | cut -f 3 )
	done
fi

IFS="$IFS_OLD"


exit 0
