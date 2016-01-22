#!/bin/ash

usage() {
	echo -e 'Usage: $0 [options]\nOptions:'
	echo -e '  -a, --action\t\tFinal action to be executed after shutting down VMs'
	echo -e '\t\t\t[shutdown|reboot|vmonly]'
	echo -e '  -w, --waittimeout\tTime to wait between shutting down VMs and final action'
	echo -e '\t\t\t(default = 60)'
	echo -e '  -l, --looptimeout\tTime to wait between checking that VMs are powered down'
	echo -e '\t\t\t(default = 5)'
	exit ${1:-1}
}

while [ -n "$1" ]; do
	case $1 in
	    -h | --help ) usage 0 ;;
	    -a | --action) shift 1 ; ACTION=$1 ;;
	    -w | --waittimeout) shift 1 ; WAITTIMEOUT=$1 ;;
	    -l | --looptimeout) shift 1 ; LOOPTIMEOUT=$1 ;;
	esac
	shift 1
done

ACTION=${ACTION:='shutdown'}
WAITTIMEOUT=${WAITTIMEOUT:=60}
LOOPTIMEOUT=${LOOPTIMEOUT:=5}
LOOPCOUNT=$(( WAITTIMEOUT/LOOPTIMEOUT ))

test `uname` != 'VMkernel' && logger -s -t 'UPS Shutdown' 'This script will only run on a VMware ESXi host!' && exit 1
test -n '$LOOPCOUNT' || usage 1
test $LOOPCOUNT -gt 0 || usage 1

VMIDs=$( vim-cmd vmsvc/getallvms | grep -E '^[0-9]' | awk '{print $1}' )

logger -s -t 'UPS Shutdown' 'Attempting graceful shutdown of Virtual Machines on the host'
for vmid in $VMIDs; do
	if vim-cmd vmsvc/power.getstate "$vmid" | grep -i 'powered on' > /dev/null 2>&1 ; then 
		if vim-cmd vmsvc/get.guest "$vmid" | grep -i 'toolsstatus' | grep -iE 'toolsok|toolsold' > /dev/null 2>&1 ; then
			vim-cmd vmsvc/power.shutdown "$vmid" &
		else
			vim-cmd vmsvc/power.off "$vmid" &
		fi
	fi
done

logger -s -t 'UPS Shutdown' 'Check to see if the VMs are all powered off'
while [ $LOOPCOUNT -ne 0 ]; do
	LOOPCOUNT=$(( $LOOPCOUNT-1 ))
	VMCOUNT=0

	for vmid in $VMIDs; do
		vim-cmd vmsvc/power.getstate $vmid | grep -i 'powered on' > /dev/null 2>&1 && VMCOUNT=$(( $VMCOUNT+1 ))
	done

	test $VMCOUNT -eq 0 && break
	sleep $LOOPTIMEOUT
done

case $ACTION in
    reboot )
	logger -s -t 'UPS Shutdown' 'Rebooting VMware host'
	reboot ;;
    vmonly )
	logger -s -t 'UPS Shutdown' 'VM Only was selected. NOT powering off VMware host.' ;;
    * )
	logger -s -t 'UPS Shutdown' 'Powering off VMware host'
	poweroff ;;
esac

exit 0

logger -s -t 'UPS Shutdown' 'Powering off VMware Host'
poweroff

exit 0
