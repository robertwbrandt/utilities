#!/bin/bash
#
#     Script for finding text within files
#     Bob Brandt <projects@brandt.ie>
#

_version=1.1
_brandt_utils=/opt/brandt/common/brandt.sh
_this_script=/opt/brandt/utilities/bfind.sh
_this_rc=/usr/local/bin/bfind
_options_grep="--color=always" # --with-filename --text
_options_find="-noleaf"

[ ! -r "$_brandt_utils" ] && echo "Unable to find required file: $_brandt_utils" 1>&2 && exit 6
. "$_brandt_utils"

brandt_amiroot && [ -x "$_this_rc" ] || sudo ln -fs "$_this_script" "$_this_rc"

function usage() {
    local _exitcode=${1-0}
    local _output=2
    [ "$_exitcode" == "0" ] && _output=1
    [ "$2" == "" ] || echo -e "$2"
    ( echo -e "Usage: $( basename $0 ) [options] PATTERN [PATH]"
      echo -e "Standard Options:"
      echo -e " -g, --grep             filter by contents (default)" # grep
      echo -e " -n, --name             filter by name"
      echo -e " -i, --ignore-case      ignore case distinctions (default)"
      echo -e " -I, --no-ignore-case   do not ignore case distinctions"
      echo -e " -L                     Follow symbolic links. (default)"
      echo -e " -P                     Never follow symbolic links."      
      echo -e " -d, --date             sort by date"
      echo -e " -s, --size             sort by size"
      echo -e " -r, --reverse          reverse the sort"
      echo -e " -V                     Verbose/Debug output"
      echo -e " -h, --help             display this help and exit"
      echo -e " -v, --version          output version information and exit"
      echo -e "Find Options: (All test are ANDed together)"
      echo -e "     tests (N can be +N or -N or N):"
      echo -e "     --amin  N          file was last accessed N minutes ago"
      echo -e "     --atime N          file was last  accessed N*24 hours ago"
      echo -e "     --cmin  N          file status was last changed N minutes ago"
      echo -e "     --ctime N          file status was last changed N*24 hours ago"
      echo -e "     --mmin  N          files data was last modified N minutes ago"
      echo -e "     --mtime N          files data was last modified N*24 hours ago"
      echo -e "     --type  C          file is of type C: (default is f)" #  (xtype)
      echo -e "                         b      block (buffered) special"
      echo -e "                         c      character (unbuffered) special"
      echo -e "                         d      directory"
      echo -e "                         p      named pipe (FIFO)"
      echo -e "                         f      regular file"
      echo -e "                         l      symbolic link"
      echo -e "                         s      socket"
      echo -e "     --maxdepth L       Descend at most levels (non-negative) levels"
      echo -e "                         of directories below the command line arguments."
      echo -e "     --mindepth L       Do not apply any tests or actions at levels less"
      echo -e "                         than levels (non-negative  integer)."
      echo -e "     --xdev             Dont descend directories on other filesystems."
      echo -e "Name Filter Options:"
      echo -e "     --basename         base of file name (the path with the leading" #name
      echo -e "                        directories removed) matches PATTERN (default)"
      echo -e "     --wholename        file name matches PATTERN"
      echo -e "     --regexname        file name matches regular expression PATTERN" #regex
      echo -e "Contents Filter Options:"
      echo -e "     --basic-regexp     PATTERN is a basic regular expression (default)"
      echo -e "     --regexp           PATTERN as a regular expression"
      echo -e "     --extended-regexp  PATTERN is an extended regular expression"
      echo -e "     --fixed-strings    PATTERN is a set of newline-separated strings"
      echo -e "     --perl-regexp      PATTERN is a Perl regular expression"
      echo -e "     --word-regexp      force PATTERN to match only whole words"
      echo -e "     --line-regexp      force PATTERN to match only whole lines"
      echo -e "     --only-matching    show only the part of a line matching PATTERN" ) >&$_output
    exit $_exitcode
}

_mode="grep" # grep or name
_case="i"   # i (ignore case) or blank
_symbolic="-L" # -F or -L
_sort="none"  # none or date or size
_sort_reverse="none" # none or reverse
_amin=""
_atime=""
_cmin=""
_ctime=""
_mmin=""
_mtime=""
_type="f"  # f | b | c | d | p  | l | s
_maxdepth=""
_mindepth=""
_xdev=""
_filter_name="name"   # basename or wholename or regexname
_filter_grep="--basic-regexp" # basic-regexp or regexp or extended-regexp or fixed-strings or perl-regexp
_filter_regexp=""  # or word-regexp or line-regexp
_verbose=""

# Execute getopt
ARGS=$(getopt -o gniILPdsrhvV -l "grep,name,ignore-case,no-ignore-case,date,size,reverse,help,version,amin:,atime:,cmin:,ctime:,mmin:,mtime:,type:,maxdepth:,mindepth:,xdev,basename,wholename,regexname,regexp,extended-regexp,fixed-strings,basic-regexp,perl-regexp,word-regexp,line-regexp" -n "$0" -- "$@") || usage 1

#Bad arguments
[ $? -ne 0 ] && usage 1 "${BOLD_RED}$( basename $0 ): No arguments supplied!${NORMAL}"

eval set -- "$ARGS";

while /bin/true; do
  case "$1" in

    "-g" | "--grep"            )    _mode="grep" ;;
    "-n" | "--name"            )    _mode="name" ;;
    "-i" | "--ignore-case"     )    _case="i" ;;
    "-I" | "--no-ignore-case"  )    _case="" ;;
    "-L"                       )    _symbolic="-L" ;;
    "-P"                       )    _symbolic="-P" ;;
    "-d" | "--date"            )    _sort="date" ;;
    "-s" | "--size"            )    _sort="size" ;;
    "-r" | "--reverse"         )    _sort_reverse="reverse" ;;
           "--amin"            )    _amin="$2" ; shift ;;
           "--atime"           )    _atime="$2" ; shift ;;
           "--cmin"            )    _cmin="$2" ; shift ;;
           "--ctime"           )    _ctime="$2" ; shift ;;
           "--mmin"            )    _mmin="$2" ; shift ;;
           "--mtime"           )    _mtime="$2" ; shift ;;
           "--type"            )    _type="$2" ; shift ;;
           "--maxdepth"        )    _maxdepth="$2" ; shift ;;
           "--mindepth"        )    _mindepth="$2" ; shift ;;
           "--xdev"            )    _xdev="-xdev" ;;
           "--basename"        )    _filter_name="name" ;;
           "--wholename"       )    _filter_name="wholename" ;;
           "--regexname"       )    _filter_name="regex" ;;
           "--basic-regexp"    )    _filter_grep="--basic-regexp" ;;
           "--regexp"          )    _filter_grep="--regexp" ;;
           "--extended-regexp" )    _filter_grep="--extended-regexp" ;;
           "--fixed-strings"   )    _filter_grep="--fixed-strings" ;;
           "--perl-regexp"     )    _filter_grep="--perl-regexp" ;;
           "--word-regexp"     )    _filter_regexp="--word-regexp" ;;
           "--line-regexp"     )    _filter_regexp="--line-regexp" ;;
    "-V"                       )     _verbose="true" ;;
    "-h" | "--help"            )     usage 0 ;;
    "-v" | "--version"         )     brandt_version $_version ;;
    --                         )     shift; break ;;
    *                          )     usage 1 "${BOLD_RED}$( basename $0 ): Invalid argument!${NORMAL}" ;;
  esac
  shift
done
_pattern="$1"
_path="${2:-$(pwd)}"

[ -z "$_pattern" ] && usage 2 "${BOLD_RED}$( basename $0 ): Invalid Search Pattern!${NORMAL}"
[ -z "$_path" ]    && usage 3 "${BOLD_RED}$( basename $0 ): Invalid Search Path!${NORMAL}"


# Check for valid option parameters


# Build find command
_find_cmd="find \"${_path}\" ${_options_find} ${_xdev}"
[ -n "$_maxdepth" ] && _find_cmd="${_find_cmd} -maxdepth ${_maxdepth}"
[ -n "$_mindepth" ] && _find_cmd="${_find_cmd} -mindepth ${_mindepth}"

_find_test="-xtype ${_type}"
[ -n "$_amin" ] &&        _find_test="${_find_test} -amin ${_amin}"
[ -n "$_atime" ] &&       _find_test="${_find_test} -atime ${_atime}"
[ -n "$_cmin" ] &&        _find_test="${_find_test} -cmin ${_cmin}"
[ -n "$_ctime" ] &&       _find_test="${_find_test} -ctime ${_ctime}"
[ -n "$_mmin" ] &&        _find_test="${_find_test} -mmin ${_mmin}"
[ -n "$_mtime" ] &&       _find_test="${_find_test} -mtime ${_mtime}"
[ "$_mode" == "name" ] && _find_test="${_find_test} -${_case}${_filter_name} \"${_pattern}\""
_find_cmd="${_find_cmd} ${_find_test} -print"

# echo $_pattern
# echo $_path
# echo $_find_cmd

_sort_cmd=

#eval $_find_cmd


exit 0


findcmd="find \"$_path\""
[ -n "$name" ] && findcmd="$findcmd -regextype \"posix-extended\" -iregex \"$name\""

if [ -n "$grep" ]; then
	[ $date -eq 1 ] || [ $size -eq 1 ] || [ $reverse -eq 1 ] && usage 1 "$0: Sorting is not valid during grep searches!\n"
	eval "$findcmd -exec grep -iH \"$grep\" {} 2>/dev/null \;"
	exit $?
fi

statcmd=""
cutcmd="cat"
sortcmd="sort"
[ $reverse -eq 1 ] && sortcmd="$sortcmd -r"
[ $date -eq 1 ] && statcmd="-exec stat -c \"%Y %n\" {} 2>/dev/null \;"
[ $size -eq 1 ] && statcmd="-exec stat -c \"%s %n\" {} 2>/dev/null \;"
[ $date -eq 1 ] || [ $size -eq 1 ] && cutcmd="cut -d \" \" -f 2-" && sortcmd="$sortcmd -n"

eval "$findcmd $statcmd | $sortcmd | $cutcmd"
exit $?
