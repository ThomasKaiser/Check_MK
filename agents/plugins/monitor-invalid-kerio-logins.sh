#!/bin/bash
#
# Checkmk plugin to monitor invalid Kerio logins. Below than 5 per
# month is "OK", 6 to 100 is "WARN" and above is critical.
#
# by Thomas Kaiser <t.kaiser@arts-others.de> 
#
# I used the MRPE report variant since I like spaces in service names.
#
# Adjust paths to your Kerio data store and security log and put it
# inside your plugins/3600 folder for example (parsing the security.log
# more often is possible too but of course also more 'expensive')
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

# START CONFIG SECTION
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin

Store=/mnt/zfs-store/kerio-backup

# create directory if necessary
if [ ! -d "${Store}" ]; then
	mkdir -m 2750 "${Store}"
fi

if [ ! -f "${Store}/employees.txt" ]; then
	touch "${Store}/employees.txt"
	chmod 644 "${Store}/employees.txt"
fi

chmod 644 "${Store}/invalid-logins-this-month.txt" 2>/dev/null

CheckAddress() {
	CountOfIssues=0
	Details=""
	grep -q " ${1}$" "${Store}/invalid-logins-this-month.txt"
	if [ $? -ne 0 ]; then
		echo "(${0##*/}) ${MTAName}%20User%20${1} 0 No invalid logins this month | invalid_logins=0"
	else
		while read line ; do
			set ${line}
			Details="${Details}, $2 $1"
			CountOfIssues=$(( ${CountOfIssues} + $1 ))
		done <<< $(grep " ${1}$" "${Store}/invalid-logins-this-month.txt")
		if [ ${CountOfIssues} -ge 100 ]; then
			echo "(${0##*/}) ${MTAName}%20User%20${3} 2 ${CountOfIssues} invalid logins${Details} | invalid_logins=${CountOfIssues}"
		elif [ ${CountOfIssues} -ge 50 ]; then
			echo "(${0##*/}) ${MTAName}%20User%20${3} 1 ${CountOfIssues} invalid logins${Details} | invalid_logins=${CountOfIssues}"
		else
			echo "(${0##*/}) ${MTAName}%20User%20${3} 0 ${CountOfIssues} invalid logins${Details} | invalid_logins=${CountOfIssues}"
		fi
	fi
} # CheckAddress

MTAName="Kerio"
TimePeriod="$(date +"%d/%b/%Y")" # this month
grep "^\[${TimePeriod} " /mnt/zfs-store/logs/security.log | grep 'Invalid password' | awk -F" " '{print $3" "$8}' \
	| sort | uniq -c | sed 's/\.$//' >"${Store}/invalid-logins-this-month.txt"

# Check_MK Reporting
echo '<<<mrpe>>>'

# process new occurences
TmpFile="$(mktemp /tmp/${0##*/}.XXXXXX || exit 1)"
trap "rm \"${TmpFile}\" ; exit 0" 0 1 2 3 15
( awk -F" " '{print $3}' <"${Store}/invalid-logins-this-month.txt" 2>/dev/null ; cat "${Store}/employees.txt" ) \
	| sort | uniq >"${TmpFile}"
cat "${TmpFile}" >"${Store}/employees.txt"

# Parse employees.txt and check whether there are invaliv logins this month:
cat "${Store}/employees.txt" | while read ; do
	CheckAddress "${REPLY}"
done