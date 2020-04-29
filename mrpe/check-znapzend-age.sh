#!/bin/bash
#
# check-znapzend-age.sh
#
# MRPE check for Nagios, Check_MK and others to monitor the
# age of ZFS snapshots. The script needs to be called with 3
# parameters:
#
# $1 is the dataset in question, e.g. zfs/crypt/fileserver
# $2 is the warning treshold in hours, e.g. 24
# $3 is the critical treshold in hours, e.g. 48
#
# So put something like this in your mrpe.conf:
# Znapzend%20fileserver (interval=600) /usr/lib/check_mk_agent/check-znapzend-age.sh zfs/crypt/fileserver 24 48
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
	TimeNow=$(date "+%s")
	LastSnapshot=$(GetLastSnapshot $1)

	# if no snapshot age can be determined exit with UNKN
	if [ "X${LastSnapshot}" = "X" ]; then
		echo "Not able to get snapshot age for $1"
		exit 3
	fi

	Difference=$(( ${TimeNow} - ${LastSnapshot} ))
	DifferenceInHours=$(( ${Difference} / 3600 ))
	
	# check tresholds
	if [ ${DifferenceInHours} -gt $3 ]; then
		ExitCode=2
	elif [ ${DifferenceInHours} -gt $2 ]; then
		ExitCode=1
	else 
		ExitCode=0
	fi
	
	# format output nicely (report minutes when less than 2 hours)
	if [ ${DifferenceInHours} -lt 2 ] ; then
		echo "Last snapshot happened $(( ${Difference} / 60 )) minutes ago"
	else
		echo "Last snapshot happened ${DifferenceInHours} hours ago"
	fi
	exit ${ExitCode}
} # Main

GetLastSnapshot() {
	zfs list -r -t snapshot -o creation $1 | sort | uniq | grep -v CREATION | while read ; do
		date -d "${REPLY}" "+%s"
	done | sort -n | tail -n1
} # GetLastSnapshot

Main $@