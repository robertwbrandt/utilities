#!/bin/bash
#
#     Script for converting a LDIF file to a txt file by adding a 
#     break at the 78th character and back again.
#     Bob Brandt <projects@brandt.ie>
#

_version=0.4
_brandt_utils=/opt/brandt/common/brandt.sh
_this_script=/opt/brandt/utilities/ldifConvert.sh
_this_rc=/usr/local/bin/bssh
declare -i _maxlen=77

[ ! -r "$_brandt_utils" ] && echo "Unable to find required file: $_brandt_utils" 1>&2 && exit 6
. "$_brandt_utils"

function setup() {  
    echo "Creating Symbolic link $_this_rc" >&2
    sudo ln -vsf "$_this_script" "$_this_rc"

    exit 0
}

function usage() {
    local _exitcode=${1-0}
    local _output=2
    [ "$_exitcode" == "0" ] && _output=1
    [ "$2" == "" ] || echo -e "$2"
    ( echo -e "Usage: $0 [options] [filetoconvert]"
      echo -e "Options:"
      echo -e " -l, --ldif     input file is a LDIF file"
      echo -e " -t, --text     input file is a TEXT file"
      echo -e " -h, --help     display this help and exit"
      echo -e " -v, --version  output version information and exit" ) >&$_output
    exit $_exitcode
}

function txt2ldif() {
	tmp=$( cat )
	declare -i c=$_maxlen
	while [ $c -lt $( echo -e "$tmp" | wc -L ) ]; do
		tmp=$( echo -e "$tmp" | sed "s|^\(.\{$c\}\)|\1 |g" )
		c=$(($c + $maxlen))
	done
	tmp=$( echo -e "$tmp" | sed "s|[[:space:]]*$||g" | fold -w $maxlen )
	echo -e "$tmp"
}

function ldif2txt() {
	cat | perl -p00e 's/\r?\n //g'
}

# Execute getopt
_args=$(getopt -o lthv -l "ldif,text,help,version" -n "$0" -- "$@") || usage 1 " "

#Bad arguments
#[ $? -ne 0 ] && usage 1 "$0: No arguments supplied!\n"

_fileType=""
eval set "$_args";
case "$1" in
	-l | --ldif )      _fileType="ldif" ; shift ;;
	-t | --text )      _fileType="text" ; shift ;;
    -h | --help )      usage 0 ;;
    -v | --version )   brandt_version $_version ;;
    --setup )          setup ;;
esac

if [ -z "$1" ]; then
	_file=$( cat )
else
	_file=$( cat "$1" )
fi

echo -e "$_file"
exit $?










# if [ -z "$1" ]; then
# 	tmp=$( cat )
# 	declare -i c=$maxlen
# 	while [ $c -lt $( echo -e "$tmp" | wc -L ) ]; do
# 		tmp=$( echo -e "$tmp" | sed "s|^\(.\{$c\}\)|\1 |g" )
# 		c=$(($c + $maxlen))
# 	done
# 	tmp=$( echo -e "$tmp" | sed "s|[[:space:]]*$||g" | fold -w $maxlen )
# 	echo -e "$tmp"
# else
# 	while [ -n "$1" ]; do
# 		tmp=$( cat "$1" )
# 		declare -i c=$maxlen
# 		while [ $c -lt $( echo -e "$tmp" | wc -L ) ]; do
# 			tmp=$( echo -e "$tmp" | sed "s|^\(.\{$c\}\)|\1 |g" )
# 			c=$(($c + $maxlen))
# 		done
# 		tmp=$( echo -e "$tmp" | sed "s|[[:space:]]*$||g" | fold -w $maxlen )
# 		echo -e "$tmp"
# 		shift 1
# 	done
# fi
# exit $?
