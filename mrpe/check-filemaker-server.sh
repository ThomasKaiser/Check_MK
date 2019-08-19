#!/bin/bash
#
# checkmk MRPE check for Filemaker server
#
# This check has to be run on the server itself and tries to query the
# database server via the fmsadmin tool (tested on macOS successfully)
#
# Logon credentials have to be provided in /etc/filemaker-credentials
# in the form $user:$password. The file should only be readable by root.

#
# In mrpe.cfg define like this for example:
# Filemaker%20Server (interval=3600) /usr/lib/check_mk_agent/check-filemaker-server.sh
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

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

credentialPermissions="$(ls -la /etc/filemaker-credentials | awk -F" " '{print $1}')"
case ${credentialPermissions} in
	*------)
		read FilemakerCredentials </etc/filemaker-credentials
		fmuser="$(cut -f1 -d: <<<"${FilemakerCredentials}")"
		fmpassword="$(cut -f2 -d: <<<"${FilemakerCredentials}")"
		;;
	*)
		echo '/etc/filemaker-credentials must only be readable by root. Aborting.' >&2
		exit 1
		;;
esac

TmpFile="$(mktemp /tmp/${0##*/}.XXXXXX)"
fmsadmin -u ${fmuser} -p ${fmpassword} LIST FILES >"${TmpFile}"
case $? in
	0)
		OpenDatabases=$(wc -l <"${TmpFile}" | tr -d '[:space:]')
		rm "${TmpFile}"
		if [ ${OpenDatabases} -eq 0 ]; then
			echo "WARN - No databases are currently open | open_filemaker_databases=0"
			exit 1
		else
			echo "OK - ${OpenDatabases} databases open | open_filemaker_databases=${OpenDatabases}"
			exit 0
		fi
		;;
	*)
		echo "CRIT - Filemaker server can not be accessed by fmsadmin"
		exit 2
		;;
esac