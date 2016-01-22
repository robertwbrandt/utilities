#!/bin/bash
# Create a script file on each volume that will reflect the current state of the trustees for DIRECTORIES in that volume.
# debug echo lines are still available but have been commented out

SCRIPT=/opt/brandt/utilities/oes/tbackup.sh
LINK_SCRIPT=/usr/local/bin/tbackup
test -x $LINK_SCRIPT || sudo ln -sf "$SCRIPT" "$LINK_SCRIPT"

oldIFS=`echo $IFS`
export IFS=$'\n'

nssvolumes() { mount | sed -n "s|.*on\s*\(\S*\)\s*type\s*nssvol.*|\1/|p" ; }
isunderdirectory() { echo "$2" | grep "$1" > /dev/null ; return $? ; }

convertrights() {
	while read userrights
	do
		if echo -e "$userrights" | grep -E "^\[.*\]$" > /dev/null
		then
			userrights=$( echo -e "$userrights" | sed -e "s|supervisor|s|" -e "s|read|r|" -e "s|write|w|" -e "s|create|c|" -e "s|erase|e|" -e "s|access control|a|" -e "s|scan|f|" -e "s|modify|m|" | sed "s|\W||g" )
#			test -z "$userrights" && userrights="none"
#			test "$userrights" == "srwceafm" && userrights="all"
		fi
		echo -e "$userrights"
	done
}

converttrustees() {
	while read username
	do
		username=$( echo -e "$username"  | sed -e "s|.*([0-9]*)\s||" -e "s|\.$||g" )
		read userrights
		userrights=$( echo -e "$userrights" | convertrights )
		echo -e "-r $userrights trustee \"$username\""
	done
}

get_rights() {
	file="$1"
	temp=$( rights -f "$file" show | sed -e "s|^[ \t]*||" -e "s|[ \t]*$||")
	trustees=$( echo -e "$temp" | awk ' /Trustees:/ {flag=1;next} /^$/{flag=0} flag { print }' | sed -n "s|^[\(\[].*|&|p" | converttrustees )
	irf=$( echo -e "$temp" | awk ' /Inherited Rights Filter:/ {flag=1;next} /^$/{flag=0} flag { print }' | convertrights )

	[[ "${file: -1:1}" == "/" ]] && file="${file%?}"
	for trustee in $( echo -e "$trustees" ); do  echo -e "rights -f \"$file\" $trustee" | tee -a "$OPT_SCRIPT"; done
	[ "$irf" != "all" ] && [ "$irf" != "srwceafm" ] && echo -e "rights -f \"$file\" $irf irf" | tee -a "$OPT_SCRIPT"
}

start() {
	get_rights "$1"
	if [ "$OPT_RECURSIVE" == "yes" ] && [ -d "$1" ]; then
		for file in $(find "$1" -mindepth 1 -maxdepth 1 ); do
			test $( basename "$file" ) == "._NETWARE" && continue
			test $( basename "$file" ) == "~DFSINFO.8-P" && continue
			test $( basename "$file" ) == "~snapshot" && continue
			test $( basename "$file" ) == "lost+found" && continue
			test $( basename "$file" ) == ".casa" && continue
			start "$file"
		done
	fi
}

usage() {
	[ -n "$2" ] && echo -e "$2\n"
	echo -e "Usage: $( basename $0 ) [options] [path]"
	echo -e "Creates a backup of Novell trustees and inherited rights filters for NSS files"
	echo -e " and directories."
	echo -e "If no path is given, the current path will be used."
	echo -e "options:"
	echo -e "  -a, --all\t\tRun on all mounted NSS Volumes."
	echo -e "  -R, --norecursive\tNo Recursive - Do not look into subdirectories"
	echo -e "\t\t\trecursively."
	echo -e "  -s, --script FILENAME\tRestore script (default: path/trestore.sh)"
	echo -e "  --help\t\tThis help message."
	exit ${1:1}
}
# Defaults for the options variables
OPT_CMD="$0 $@"
OPT_ALL=no
OPT_RECURSIVE=yes
OPT_SCRIPT=""
OPT_FILE=""

oldIFS=`echo $IFS`
export IFS=$'\n'

while [ -n "$1" ]; do
case "$1" in
    -a | --all ) OPT_ALL=yes ;;
    -R | --norecursive ) OPT_RECURSIVE=no ;;
    -s | --script ) shift 1; OPT_SCRIPT="$1" ;;
    -h | --help ) usage 0 ;;
    *)	OPT_FILE="$1" ;;
esac
shift 1
done

[ "$OPT_ALL" == "no" ] && [ -z "$OPT_FILE" ] && OPT_FILE="$( pwd )/"
test -d "$OPT_FILE" && [[ "${OPT_FILE: -1:1}" != "/" ]] && OPT_FILE="$OPT_FILE/"

if [ -z "$OPT_SCRIPT" ]; then
	OPT_SCRIPT="$OPT_FILE"
	[ "$OPT_ALL" == "yes" ] && OPT_SCRIPT=$( nssvolumes | head -n 1 )
	test -d "$OPT_SCRIPT" && [[ "${OPT_SCRIPT: -1:1}" != "/" ]] && OPT_SCRIPT="$OPT_SCRIPT/"
	test -d "$OPT_SCRIPT" || OPT_SCRIPT=$( dirname "$OPT_SCRIPT" )
	OPT_SCRIPT="$OPT_SCRIPT""trestore.sh"
fi

echo -e "#!/bin/bash" > "$OPT_SCRIPT"
echo -e "# Output of command: $OPT_CMD" >> "$OPT_SCRIPT"
echo -e "Running command:  $OPT_CMD\nOutput Script is: $OPT_SCRIPT"
chmod +x "$OPT_SCRIPT"
tmp="Started at: $(date )"
echo -e "# $tmp\n" >> "$OPT_SCRIPT"
echo -e "$tmp\n"

if [ "$OPT_ALL" == "yes" ]; then
	for dir in $( nssvolumes ); do start "$dir"; done
else
	[ -e "$OPT_FILE" ] || usage 1 "The file ($OPT_FILE) does not exist."
	IN_NSS="no"
	for dir in $( nssvolumes ); do 
		isunderdirectory "$dir" "$OPT_FILE" && IN_NSS="yes"
	done
	[ "$IN_NSS" == "yes" ] || usage 1 "The file ($OPT_FILE) must be in an NSS volume."
	start "$OPT_FILE"
fi

tmp="Ended at: $(date )"
echo -e "\n# $tmp" >> "$OPT_SCRIPT"
echo -e "\n$tmp"

#Restore old IFS
export IFS=$oldIFS

