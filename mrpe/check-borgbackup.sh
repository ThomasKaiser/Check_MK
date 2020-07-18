#!/bin/bash
#
# Check when last backup ran successfully. Requires borgbackup 1.1
# or higher.
#
# Meant to be an MRPE check so put this for example in your mrpe.cfg
# Borg%20Backup (interval=3600) /usr/lib/check_mk_agent/check-borgbackup.sh -C /etc/borg-backup.cfg
#
# /etc/borg-backup.cfg has to contain $BORG_REPO and in case you use
# encryption also $BORG_PASSPHRASE so take care about permissions of
# this file. Without a config file you have to provide the repo url
# via the -R switch.
#
# The defaults for age checks are as follows: warn='3 hours ago' and
# crit='2 days ago'. In case you want to change this use the -w and
# -c switches with any date format GNU date is able to understand.
#
# The plugin requires the borg binary in $PATH (otherwise $BORG has to
# be exported in the environment) and the same goes for GNU date
# (otherwise define $DATE accordingly).
#
# Most code courtesy https://github.com/bebehei/nagios-plugin-check_borg
# and therefore this script licensed under the terms of GPLv3.

set -o nounset

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

debug(){   ([ "${verbose}" -gt 1 ] && echo "$*") || return 0; }
verbose(){ ([ "${verbose}" -gt 0 ] && echo "$*") || return 0; }
error(){   echo "UNKN - $*"; exit "${STATE_UNKNOWN}"; }

crit='2 days ago'
warn='3 hours ago'
verbose=0

usage(){
	cat >&2 <<-FIN
	usage: ${0##*/} [-C CONF] [-R REPO] [-w DATE] [-c DATE] [ -h -v ]

	REPO: borg repo-url
	DATE: Any valid date for the date-command.
	      default for -w: "${warn}"
	      default for -c: "${crit}"
	CONF: A configuration file, which will get sourced. You
	      can use this to set the necessary env variables.

	You have to specify in the environment:
	  - BORG_REPO if you haven't passed the -R flag and did not
	    provide the repo url via -C switch in the config file
	  - BORG_PASSPHRASE if your repo is encrypted
	FIN
	exit "${STATE_UNKNOWN}"
}

: "${BORG:=borg}"
command -v "${BORG}" >/dev/null 2>/dev/null \
	|| error "No command '${BORG}' available."

: "${DATE:=date}"
command -v "${DATE}" >/dev/null 2>/dev/null \
	|| error "No command '${DATE}' available."

while getopts ":vhR:C:c:w:" opt; do
	case "${opt}" in
		v)
			verbose=$((verbose + 1))
			;;
		h)
			usage
			;;
		R)
			export "BORG_REPO=${OPTARG}"
			;;
		C)
			[ -e "${OPTARG}" ] || error "Configuration file '${OPTARG}' does not exist."
			[ -r "${OPTARG}" ] || error "Could not read configuration file '${OPTARG}'."
			. "${OPTARG}"      || error "Could not source configuration file '${OPTARG}'."
			;;
		c)
			crit="${OPTARG}"
			;;
		w)
			warn="${OPTARG}"
			;;
		\?)
			error "Invalid option: -${OPTARG}"
			usage
			;;
		:)
			error "Option -${OPTARG} requires an argument."
			usage
			;;
	esac
done

if [ -z "${BORG_REPO:-""}" ]; then
	error "No repository specified!"
fi
verbose "repo ${BORG_REPO}"

# convert values to seconds to enable comparison
sec_warn="$(${DATE} --date="${warn}" '+%s')"
sec_crit="$(${DATE} --date="${crit}" '+%s')"

# check warning and critical values
if [ ${sec_crit} -gt ${sec_warn} ] ; then
	error "Warning value has to be a more recent timepoint than critical."
fi

# get unixtime of last backup
export BORG_PASSPHRASE BORG_REPO
last="$(${BORG} list --sort timestamp --last 1 --format '{time}')"
[ "$?" = 0 ] || error "Cannot list repository archives. Repo Locked?"

if [ -z "${last}" ]; then
	echo "CRITICAL - no archive in repository"
	exit "${STATE_CRITICAL}"
fi

sec_last="$(${DATE} --date="${last}" '+%s')"

# interpret the amount of fails
if [ "${sec_crit}" -gt "${sec_last}" ]; then
	state="${STATE_CRITICAL}"
	msg="CRIT - last backup made on ${last}"
elif [ "${sec_warn}" -gt "${sec_last}" ]; then
	state="${STATE_WARNING}"
	msg="WARN - last backup made on ${last}"
else
	state="${STATE_OK}"
	msg="OK - last backup made on ${last}"
fi

echo "${msg}"
exit "${state}"