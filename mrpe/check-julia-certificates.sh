#!/bin/bash
#
# Nagios compatible Check_MK MRPE plugin that checks S/MIME certificate
# expiration dates.
# 
# Arguments as follows:
# -w  warning threshold in days
# -c  critical threshold in days
# -d  directory to check for expiring certificates
# -o  obfuscate email addresses, replace the user part with xxx
#
# The -o option is important to not expose email addresses as part
# of monitoring notifications (GDPR compliance). If you don't provide
# the -o option the email addresses associated with expiring certs
# will be part of the check's status output.
#
# In mrpe.cfg define like this for example:
# Our%20Certificates (interval=10800) /usr/lib/check_mk_agent/check-julia-certificates.sh -w 10 -c 2 -d /opt/julia/etc/SWISSSIGN/certs
# Public%20Certificates (interval=10800) /usr/lib/check_mk_agent/check-julia-certificates.sh -w 10 -c 2 -d /opt/julia/etc/public -o
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

# defaults, not active since check for at least 3 arguments is in place
CERT_DIR=/opt/julia/etc/certs
WARN_LIMIT=10
CRIT_LIMIT=2
OBFUSCATE=TRUE

ShowUsage()
{
	echo -e "usage: ${0##*/} [ -w value -c value -d \$CERT_DIR -h ]"
	echo "  -w  warning threshold in days"
	echo "  -c  critical threshold in days"
	echo "  -d  directory to check for expiring certificates"
	echo "  -o  obfuscate email addresses, replace the user part with xxx"
	echo "  -h  print this help"
    exit 3
}

ParseCertificates() {
	# generate a tab separated list of certificates only containing the
	# email address and expiration date in days
	for file in "${CERT_DIR}"/* ; do
		ExpirationDate="$(openssl x509 -enddate -noout -in ${file} 2>/dev/null | awk -F"=" '/notAfter/ {print $2}')"
		ExpirationDateInSeconds=$(date "+%s" -d "${ExpirationDate}")
		eMailAddress="$(openssl x509 -subject -noout -in ${file} 2>/dev/null | awk -F"emailAddress = " '/subject/ {print $2}' | cut -f1 -d',')"
		if [ "X${eMailAddress}" != "X" ]; then
			echo -e "${eMailAddress}\t${ExpirationDateInSeconds}" >>"${TmpFile}"
		fi
	done
} # ParseCertificates

CheckCertificates() {
	# parse tab separated list created before, first we filter for 
	# email addresses only (1st column)
	cut -f1 <"${TmpFile}" | sort | uniq | while read eMailAddress ; do
		# search for address in list, filter for 2nd row and extract highest
		# number (latest expiration date in case more than one cert exists)
		ExpirationDate=$(grep "^${eMailAddress}" "${TmpFile}" | cut -f2 | sort -n | tail -n1)
		ExpirationDiff=$(( $(( ${ExpirationDate} - ${TimeNow} )) / 86400 ))

		# if $OBFUSCATE=TRUE then obfuscate email address
		if [ "X${OBFUSCATE}" = "XTRUE" ]; then
			Domain="$(cut -f2 -d'@' <<<"${eMailAddress}")"
			eMailAddress="xxx@${Domain}"
		fi

		# format expiration string nicely
		if [ ${ExpirationDiff} -eq 1 ]; then
			TimeUnit="day"
		else
			TimeUnit="days"
		fi
		if [ ${ExpirationDiff} -le ${CRIT_LIMIT} ]; then
			echo -e "${eMailAddress} ${ExpirationDiff} ${TimeUnit}, \c"
			echo -e "ExitCode\t2" >>"${TmpFile}"
		elif [ ${ExpirationDiff} -le ${WARN_LIMIT} ]; then
			echo -e "${eMailAddress} ${ExpirationDiff} ${TimeUnit}, \c"
			echo -e "ExitCode\t1" >>"${TmpFile}"
		else
			echo -e "ExitCode\t0" >>"${TmpFile}"
		fi
	done
	return ${ExitCode}
} # CheckCertificates

# get arguments, we don't rely on defaults but force valid parameters
if [ $# -lt 3 ]; then
	ShowUsage
fi

while getopts 'w:c:d:h:o' OPT; do
	case ${OPT} in
		w)	WARN_LIMIT=${OPTARG}
			;;
		c)  CRIT_LIMIT=${OPTARG}
			;;
		d)  CERT_DIR=${OPTARG}
			;;
		h)	ShowUsage
			;;
		o)  OBFUSCATE=TRUE
			;;
		*)  echo "Unknown option"
			ShowUsage
			;;
	esac
done

# define environment, determine timestamp and create temp file
export PATH=/usr/bin:/bin
TimeNow=$(date "+%s")
TmpFile="$(mktemp /tmp/${0##*/}.XXXXXX || exit 1)"

# process certificates
ParseCertificates
# CountOfCerts=$(wc -l <"${TmpFile}")
Summary="$(CheckCertificates | sed -e 's/,\ $//')"
CountOfExpiringCerts=$(tr ',' '\n' <<< "${Summary}" | wc -l)
ExitCode=$(grep "^ExitCode" "${TmpFile}" | cut -f2 | sort -n | tail -n1)

case ${ExitCode} in
	0)
		echo "OK - no certificates to expire soon | expiring_certificates=0"
		;;
	1)
		echo "WARN - ${Summary} | expiring_certificates=${CountOfExpiringCerts}"
		;;
	2)
		echo "CRIT - ${Summary} | expiring_certificates=${CountOfExpiringCerts}"
		;;
esac

rm "${TmpFile}"

exit ${ExitCode}
