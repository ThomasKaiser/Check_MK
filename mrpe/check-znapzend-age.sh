#!/bin/bash
#
# check-znapzend-age.sh
#
# MRPE check for Check_MK to monitor the age of ZFS snapshots
# on a specific dataset. Works locally as well as on the target
# storage of Znapzend, zrep, sanoid, etc. syncs.
#
# The script needs to be called with 3 parameters:
#
# $1 is the dataset in question, e.g. zfs/crypt/fileserver
# $2 is the warning treshold in hours, e.g. 2
# $3 is the critical treshold in hours, e.g. 24
#
# So put something like this in your mrpe.conf:
# Znapzend%20Fileserver /usr/lib/check_mk_agent/check-znapzend-age.sh zfs/crypt/fileserver 2 24
#
# The check provides also graph data as $snapshot_age. If the WARN
# treshold is less than 24 hours then $snapshot_age will be submitted
# as minutes, otherwise as hours.
#
# This bash script has been written as a q&d replacement of
# https://github.com/asciiphil/check_znapzend since I ran too
# often in python dependency hell. In case you want to switch
# from the former be aware that you need to adjust order of
# arguments and time formats.
#
# This file is part of Check_MK.
# The official homepage is at http://mathias-kettner.de/check_mk.
#
# check_mk is free software;  you can redistribute it and/or modify it
# under the  terms of the  GNU General Public License  as published by
# the Free Software Foundation in version 2.  check_mk is  distributed
# in the hope that it will be useful, but WITHOUT ANY WARRANTY;  with-
# out even the implied warranty of  MERCHANTABILITY  or  FITNESS FOR A
# PARTICULAR PURPOSE. See the  GNU General Public License for more de-
# tails. You should have  received  a copy of the  GNU  General Public
# License along with GNU Make; see the file  COPYING.  If  not,  write
# to the Free Software Foundation, Inc., 51 Franklin St,  Fifth Floor,
# Boston, MA 02110-1301 USA.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

Main() {
	if [ $# -ne 3 ]; then
		echo "UNKN - the check needs to be called with 3 arguments, check the script header for details"
		exit 3
	fi

	TimeNow=$(date "+%s")
	LastSnapshot=$(GetLastSnapshot $1)

	# if no snapshot age can be determined exit with UNKN
	if [ "X${LastSnapshot}" = "X" ]; then
		echo "Not able to get snapshot age for $1"
		exit 3
	fi

	Difference=$(( ${TimeNow} - ${LastSnapshot} ))
	DifferenceInHours=$(( ${Difference} / 3600 ))
	DifferenceInMinutes=$(( ${Difference} / 60 ))
	if [ $2 -lt 24 ]; then
		SnapshotAge=${DifferenceInMinutes}
	else
		SnapshotAge=${DifferenceInHours}
	fi
	
	# check tresholds
	if [ ${DifferenceInHours} -ge $3 ]; then
		ExitCode=2
	elif [ ${DifferenceInHours} -ge $2 ]; then
		ExitCode=1
	else 
		ExitCode=0
	fi
	
	# format output nicely (report minutes when less than 2 hours)
	if [ ${DifferenceInHours} -lt 2 ] ; then
		echo "Last snapshot happened ${DifferenceInMinutes} minutes ago | snapshot_age=${SnapshotAge}"
	else
		echo "Last snapshot happened ${DifferenceInHours} hours ago | snapshot_age=${SnapshotAge}"
	fi
	exit ${ExitCode}
} # Main

GetLastSnapshot() {
	zfs list -r -t snapshot -o creation $1 | sort | uniq | grep -v CREATION | while read ; do
		date -d "${REPLY}" "+%s"
	done | sort -n | tail -n1
} # GetLastSnapshot

Main $@