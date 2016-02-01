#!/bin/sh
#
#     Utility to update Brandt procedures
#     Bob Brandt <projects@brandt.ie>
#          
#

_version=1.2
_brandt_utils=/opt/brandt/common/brandt.sh
_this_conf=/etc/brandt/update-brandt.conf
_this_script=/opt/brandt/utilities/oes/update-brandt
_this_rc=/usr/local/bin/update-brandt
_bssh_conf=/etc/brandt/bssh.conf
_bssh_user_conf=$HOME/.ssh/bssh.conf

[ ! -r "$_brandt_utils" ] && echo "Unable to find required file: $_brandt_utils" 1>&2 && exit 6
. "$_brandt_utils"

if [ ! -r "$_this_conf" ]; then
    ( echo -e '#     Configuration file for the Update Brandt script'
      echo -e '#     Bob Brandt <projects@brandt.ie>\n#'
      echo -e 'LDAP_SERVER="ldap.opw.ie\n"' ) > "$_this_conf"
fi
. "$_this_conf"
[ -r "$_bssh_conf" ] && . "$_bssh_conf"
[ -r "$_bssh_user_conf" ] && . "$_bssh_user_conf"

function bssh_rsync() {
	local _syncpath="$1"
	if [ -d "$_syncpath" ]; then
		rsync -az --ignore-errors --progress --del -e "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i $_ssh_keygen_keyfile" --exclude=*~ "$_syncpath/" "root@$_dstServer:$_syncpath"
	elif [ -f "$_syncpath" ]; then
		rsync -az --ignore-errors --progress --del -e "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i $_ssh_keygen_keyfile" "$_syncpath" "root@$_dstServer:$_syncpath"
	fi
	return $?
}

function usage() {
	local _exitcode=${1-0}
	local _output=2
	[ "$_exitcode" == "0" ] && _output=1
	[ "$2" == "" ] || echo -e "$2"
	( echo -e "Usage: $0 [options] DestinationServer"
	  echo -e " -c, --copy=option  Specify which files to copy (default=brandt)"
	  echo -e "                    valid options are: (all|brandt|mcafee|netapp|sys|iprint|salt)"
	  echo -e " -v, --verbose      run verbose"
	  echo -e " -h, --help         display this help and exit"
	  echo -e " -V, --version      output version information and exit" ) >&$_output
	exit $_exitcode
}

# Execute getopt
if ! _args=$( getopt -o c:vVh -l ",copy:,verbose,help,version" -n "$0" -- "$@" 2>/dev/null ); then
	_err=$( getopt -o c:vVh -l ",copy:,verbose,help,version" -n "$0" -- "$@" 2>&1 >/dev/null )
	usage 1 "${BOLD_RED}$_err${NORMAL}"
fi

#Bad arguments
#[ $? -ne 0 ] && usage 1 "$0: No arguments supplied!\n"

eval set -- "$_args";
_copyBrandt=1
_copyNetApp=
_copyMcAfee=
_copySYS=
_copyIPrint=
_copySalt=
while /bin/true ; do
    case "$1" in
	    -c | --copy )		case "$2" in
							    all )       _copyBrandt=1
											_copyNetApp=1
											_copyMcAfee=1
											_copySYS=
											_copyIPrint=1
											_copySalt=1
											;;
							    mcafee )    _copyBrandt=
											_copyMcAfee=1
											;;
							    netapp )    _copyBrandt=
											_copyNetApp=1
											;;
							    sys )       _copyBrandt=
											_copySYS=1
											;;
							    iprint )    _copyBrandt=
											_copyIPrint=1
											;;
							    salt )      _copyBrandt=
											_copySalt=1
											;;
							    * )         _copyBrandt=1 ;;
							esac
							shift ;;
        -h | --help )       usage 0 ;;
        -v | --version )    brandt_version $_version ;;
        -- )                shift ; break ;;
        * )                 usage 1 "${BOLD_RED}$0: Invalid argument!${NORMAL}" ;;
    esac
    shift
done

_dstServer=$( lower "$1" )

brandt_amiroot || { echo "${BOLD_RED}This program must be run as root!${NORMAL}" >&2 ; exit 2; }
[ -z "$_dstServer" ] && { echo -e "${BOLD_RED}You must enter a Destination Server!${NORMAL}" >&2 ; exit 3; }

test -x "$_this_rc" || ln -s "$_this_script" "$_this_rc"

echo -e "\n\nYou are about to copy the Brandt Configuration Files from ${BOLD}$( hostname ) (This Server)${NORMAL} to ${BOLD}$1${NORMAL}."
echo -e "\t${BOLD}$( hostname ) (This Server)${NORMAL}\t-->\t${BOLD}$1${NORMAL}\n"
read -p "Are you sure you want to continue? (y/N): " ANSWER
ANSWER=$( lower "${ANSWER:=NO}" )
if [ "${ANSWER:0:1}" == "y" ]; then
    HOST="$_dstServer"
    isIP "$HOST" && HOST=$( IP2FQDN "$HOST" )
	HOST=$( echo "$HOST" | cut -d "." -f 1 )
	[ -z "$HOST" ] && HOST="$_dstServer"

	if ping -c 1 "$HOST" > /dev/null 2>&1
	then
	  	tmp=$( cut -d " " -f 1 "$_ssh_keygen_knownhostsfile"  | sed -ne "s|^$HOST$|&|p" -e "s|^$HOST\W|&|p" -e "s|\W$HOST\W|&|p" -e "s|\W$HOST$|&|p" | sort -u )
	  	[ -z "$tmp" ] && bssh -l "root" --terminal --type linux --copy "$HOST"

		# #test "$_copyBrandt" && bssh_rsync "/etc/brandt"
		test "$_copyBrandt" && bssh_rsync "/opt/brandt"
		test "$_copyNetApp" && bssh_rsync "/opt/netapp"
		test "$_copyMcAfee" && bssh_rsync "/opt/McAfee/install.sh"
		test "$_copySYS"    && bssh_rsync "/srv/sys"
		test "$_copyIPrint" && bssh_rsync "/var/opt/novell/iprint/htdocs"
		test "$_copyIPrint" && bssh_rsync "/var/opt/novell/iprint/resdir"
		test "$_copySalt"   && bssh_rsync "/opt/salt"
	else
		echo -e "${BOLD_RED}Unable to ping $HOST${NORMAL}" >&2
		exit 1
	fi
	echo -e "\n"
fi
exit 0
