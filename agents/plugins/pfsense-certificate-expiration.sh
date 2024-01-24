#!/bin/bash
#
# Check pfSense certificate expiration. Requires HTTPS access from
# the host executing this check to pfSense's admin interface.
#
# Use it as a plugin on a host where the pfsense's admin interface
# is accessible, for example put it in plugins/86400 for a daily
# check. The output is in MRPE style so you're able to use the
# piggyback mechanism to report the expiring certificates at your
# pfsense host.
#
# You need to define the URL of the pfSense's certificates page below 
# as $PFSENSE_URI
# 
# Logon credentials have to be provided in /etc/pfsense-credentials in
# the form $user:$password. The file should only be readable by root.
#
# If you want the output to be associated with another host in Check_MK
# (for example the real pfSense device) then provide $PIGGYBACK_HOST
# named exactly as your firewall's hostname in Check_MK.
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

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

WARN_TRESHOLD=30 # time in days
CRIT_TRESHOLD=7 # time in days
PFSENSE_URI="https://pfsense.a-o.intern/system_certmanager.php"
PIGGYBACK_HOST="pfsense"

error(){   echo "UNKN - $*"; exit "${STATE_UNKNOWN}"; }

usage(){
	cat >&2 <<-EOF
	usage: ${0##*/} [-w DAYS] [-c DAYS] [ -h ]

	DAYS: how many days prior to certificate expiration.
	      default for -w: "${WARN_TRESHOLD}"
	      default for -c: "${CRIT_TRESHOLD}"
	EOF
	exit "${STATE_UNKNOWN}"
}

credentialPermissions="$(ls -la /etc/pfsense-credentials | awk -F" " '{print $1}')"
case ${credentialPermissions} in
	*------)
		read PFSENSE_CREDENTIALS </etc/pfsense-credentials
		PFSENSE_NAME="$(cut -f1 -d: <<<"${PFSENSE_CREDENTIALS}")"
		PFSENSE_PASSWORD="$(cut -f2 -d: <<<"${PFSENSE_CREDENTIALS}")"
		;;
	*)
		error '/etc/pfsense-credentials must only be readable by root.'
		;;
esac

: "${HTML2TEXT:=html2text}"
command -v "${HTML2TEXT}" >/dev/null 2>/dev/null \
	|| error "No command '${HTML2TEXT}' available."

: "${DATE:=date}"
command -v "${DATE}" >/dev/null 2>/dev/null \
	|| error "No command '${DATE}' available."

: "${WGET:=wget}"
command -v "${WGET}" >/dev/null 2>/dev/null \
	|| error "No command '${WGET}' available."

while getopts "hc:w:" opt; do
	case "${opt}" in
		h)
			usage
			;;
		c)
			CRIT_TRESHOLD="${OPTARG}"
			;;
		w)
			WARN_TRESHOLD="${OPTARG}"
			;;
	esac
done

CRIT_DIFF=$(( ${CRIT_TRESHOLD} * 86400 ))
[ ${CRIT_DIFF} -gt 0 ] || error "CRIT treshold can not be determined. Check parameters please."
WARN_DIFF=$(( ${WARN_TRESHOLD} * 86400 ))
[ ${WARN_DIFF} -gt 0 ] || error "WARN treshold can not be determined. Check parameters please."
[ ${CRIT_DIFF} -gt ${WARN_DIFF} ] && error "Warning value has to be higher than critical."

TIME_NOW=$(${DATE} '+%s')
TMP_DIR="$(mktemp -d /tmp/${0##*/}.XXXXXX || error "Not able to create temp dir")"
cd "${TMP_DIR}" || error "Not able to change into ${TMP_DIR}"

# try to fetch output from system_certmanager.php
${WGET} -O- --keep-session-cookies --no-check-certificate --save-cookies cookies.txt "${PFSENSE_URI}" \
	| grep "name='__csrf_magic'" | sed 's/.*value="\(.*\)".*/\1/' >csrf.txt 2>/dev/null
${WGET} -O- --keep-session-cookies --no-check-certificate --load-cookies cookies.txt \
	--save-cookies cookies.txt --post-data \
	"login=Login&usernamefld=${PFSENSE_NAME}&passwordfld=${PFSENSE_PASSWORD}&__csrf_magic=$(cat csrf.txt)" \
	"${PFSENSE_URI}" | grep "name='__csrf_magic'" | sed 's/.*value="\(.*\)".*/\1/' >csrf2.txt 2>/dev/null
${WGET} -O system_certmanager.html --keep-session-cookies --no-check-certificate --load-cookies \
	cookies.txt "${PFSENSE_URI}" 2>/dev/null

# check whether actual certificates are listed
grep -q "Certificate" system_certmanager.html || error "Not able to retrieve list of certificates"

# parse results
${HTML2TEXT} -width 1000 system_certmanager.html >system_certmanager.txt
awk -F": " '/Valid Until/ {print $2}' system_certmanager.txt | while read ; do
	EXPIRATION_DATE=$(${DATE} --date "${REPLY}" '+%s')
	case $? in
		0)
			# date parsing worked
			EXPIRATION_DIFF=$(( ${EXPIRATION_DATE} - ${TIME_NOW} ))

			# collect soon to expire certificates with account names
			if [ ${EXPIRATION_DIFF} -lt ${CRIT_DIFF} ]; then
				if [ ${EXPIRATION_DIFF} -gt 0 ]; then
					grep -B7 "${REPLY}" "${TMP_DIR}/system_certmanager.txt" | head -n1 | cut -c1-28 | sed 's/  */ /g' >>"${TMP_DIR}/crit-names"
					echo ${EXPIRATION_DIFF} >>"${TMP_DIR}/crit"
				fi
			elif [ ${EXPIRATION_DIFF} -lt ${WARN_DIFF} ]; then
				if [ ${EXPIRATION_DIFF} -gt 0 ]; then
					grep -B7 "${REPLY}" "${TMP_DIR}/system_certmanager.txt" | head -n1 | cut -c1-28 | sed 's/  */ /g' >>"${TMP_DIR}/warn-names"
					echo ${EXPIRATION_DIFF} >>"${TMP_DIR}/warn"
				fi
			fi
			;;
		1)
			# date parsing failed
			echo "${REPLY}" >>"${TMP_DIR}/failed"
			;;
	esac
done

COUNT_OF_CRITS=$(wc -l "${TMP_DIR}/crit" 2>/dev/null | awk -F" " '{print $1}')
COUNT_OF_WARNS=$(wc -l "${TMP_DIR}/warn" 2>/dev/null | awk -F" " '{print $1}')
COUNT_OF_FAILURES=$(wc -l "${TMP_DIR}/failed" 2>/dev/null | awk -F" " '{print $1}')
ACCOUNT_NAMES=$(cat "${TMP_DIR}/crit-names" "${TMP_DIR}/warn-names" 2>/dev/null | tr "\n" "," | sed -e 's/\ ,$//' -e 's/\ ,/, /g' )
rm -rf "${TMP_DIR}"

if [ ${COUNT_OF_FAILURES:=0} -gt 1 ]; then
	state="${STATE_CRITICAL}"
	msg="CRIT - ${COUNT_OF_FAILURES} certificate expiration dates could not be parsed."
elif [ ${COUNT_OF_CRITS:=0} -gt 1 ]; then
	state="${STATE_CRITICAL}"
	msg="CRIT - One or more certificates are about to expire in less than ${CRIT_TRESHOLD} days (${ACCOUNT_NAMES})."
elif [ ${COUNT_OF_CRITS:=0} -eq 1 ]; then
	state="${STATE_CRITICAL}"
	msg="CRIT - One certificate is about to expire in less than ${CRIT_TRESHOLD} days (${ACCOUNT_NAMES})."
elif [ ${COUNT_OF_WARNS:=0} -gt 1 ]; then
	state="${STATE_WARNING}"
	msg="WARN - One or more certificates are about to expire in less than ${WARN_TRESHOLD} days (${ACCOUNT_NAMES})."
elif [ ${COUNT_OF_WARNS:=0} -eq 1 ]; then
	state="${STATE_WARNING}"
	msg="WARN - One certificate is about to expire in less than ${WARN_TRESHOLD} days (${ACCOUNT_NAMES})."
else
	state="${STATE_OK}"
	msg="OK - no certificates about to expire soon."
fi

[ -n ${PIGGYBACK_HOST} ] && echo "<<<<${PIGGYBACK_HOST}>>>>"
echo -e "<<<mrpe>>>"
echo "(${0##*/}) Expiring%20Certificates ${state} ${msg} | expiring_crit=${COUNT_OF_CRITS:-0} expiring_warn=${COUNT_OF_WARNS:-0}" 
[ -n ${PIGGYBACK_HOST} ] && echo "<<<<>>>>"

