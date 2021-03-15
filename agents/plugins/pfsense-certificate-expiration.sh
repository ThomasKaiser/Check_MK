#!/bin/bash
#
# Check pfSense certificate expiration. Requires HTML source of
# system_certmanager.php to be stored at $CERT_HTML
#
# Use it as a plugin on the host where the HTML source is stored 
# or retrieved, for example put it in plugins/86400 for a daily
# check. The output is in MRPE style so you're able to use the
# piggyback mechanism to report the expiring certificates at your
# pfsense host.
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
CERT_HTML=/home/yb/Certificates.html

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

: "${HTML2TEXT:=html2text}"
command -v "${HTML2TEXT}" >/dev/null 2>/dev/null \
	|| error "No command '${HTML2TEXT}' available."

: "${DATE:=date}"
command -v "${DATE}" >/dev/null 2>/dev/null \
	|| error "No command '${DATE}' available."

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
[ -f "${CERT_HTML}" ] || error "Not able to read ${CERT_HTML}"

TIME_NOW=$(${DATE} '+%s')
TMP_DIR="$(mktemp -d /tmp/${0##*/}.XXXXXX || exit 3)"

${HTML2TEXT} "${CERT_HTML}" | awk -F": " '/Valid Until/ {print $2}' | while read ; do
	EXPIRATION_DATE=$(${DATE} --date "${REPLY}" '+%s')
	EXPIRATION_DIFF=$(( ${EXPIRATION_DATE} - ${TIME_NOW} ))

	# interpret the amount of fails
	if [ ${EXPIRATION_DIFF} -lt ${CRIT_DIFF} ]; then
		if [ ${EXPIRATION_DIFF} -gt 0 ]; then
			echo ${EXPIRATION_DIFF} >>/${TMP_DIR}/crit
		fi
	elif [ ${EXPIRATION_DIFF} -lt ${WARN_DIFF} ]; then
		if [ ${EXPIRATION_DIFF} -gt 0 ]; then
			echo ${EXPIRATION_DIFF} >>/${TMP_DIR}/warn
		fi
	fi
done

COUNT_OF_CRITS=$(wc -l ${TMP_DIR}/crit 2>/dev/null | awk -F" " '{print $1}')
COUNT_OF_WARNS=$(wc -l ${TMP_DIR}/warn 2>/dev/null | awk -F" " '{print $1}')
rm -rf "${TMP_DIR}"

if [ ${COUNT_OF_CRITS} -gt 1 ]; then
	state="${STATE_CRITICAL}"
	msg="CRIT - One or more certificates are about to expire in less than ${CRIT_TRESHOLD} days."
elif [ ${COUNT_OF_CRITS} -eq 1 ]; then
	state="${STATE_CRITICAL}"
	msg="CRIT - One certificate is about to expire in less than ${CRIT_TRESHOLD} days."
elif [ ${COUNT_OF_WARNS} -gt 1 ]; then
	state="${STATE_WARNING}"
	msg="WARN - One or more certificates are about to expire in less than ${WARN_TRESHOLD} days."
elif [ ${COUNT_OF_WARNS} -eq 1 ]; then
	state="${STATE_WARNING}"
	msg="WARN - One certificate is about to expire in less than ${WARN_TRESHOLD} days."
else
	state="${STATE_OK}"
	msg="OK - no certificates about to expire soon."
fi

echo -e '<<<<pfsense>>>>\n<<<mrpe>>>'
echo "(${0##*/}) Expiring%20Certificates ${state} ${msg} | expiring_crit=${COUNT_OF_CRITS} expiring_warn=${COUNT_OF_WARNS}" 
echo '<<<<>>>>'