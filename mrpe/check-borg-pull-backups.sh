#!/bin/bash
#
# (c) 2021-2026 Thomas Kaiser
#
# CheckMK sensor to monitor Borg backup execution. Has to run on same host
# that performs the pull backups.
#
# /etc/borg-backup.cfg has to contain $BORG_STATUS to read the state
# files the pull backup script creates after performing backups.
# The backup status will be reported to the servers in question using
# Check_MK's piggyback mechanism. The servername will be prefixed with
# 'online' due to internal conventions.
#
# The defaults for age checks are as follows: warn='26 hours ago' and
# crit='3 days ago'. In case you want to change this simply use any 
# date format GNU date is able to understand.
#
# Some code courtesy https://github.com/bebehei/nagios-plugin-check_borg
# and therefore this script licensed under the terms of the GPLv3.

set -o nounset

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

crit='3 days ago'
warn='26 hours ago'

# convert values to seconds to enable comparison
sec_warn="$(date --date="${warn}" '+%s')"
sec_crit="$(date --date="${crit}" '+%s')"

# check warning and critical values
if [ ${sec_crit} -gt ${sec_warn} ] ; then
	echo "(${0##*/}) Borg%20Backup 3 UNKN - Warning value has to be a more recent timepoint than critical."
fi

# read in config:
. /etc/borg-backup.cfg

for ComputerName in "${BORG_STATUS}"/* ; do
	read last <"${ComputerName}"

	if [ -z "${last}" ]; then
		:
	else	
		sec_last="$(date --date="${last}" '+%s')"

		# determine backup duration
		HostName="${ComputerName##*/}"
		BorgLog="/var/log/borg-backup/${HostName}.log"
		if [ -f "${BorgLog}" ]; then
			LastLogEntries="$(tail -n 250 "${BorgLog}")"
			FinishTime="$(awk -F": " '/^Time \(end\)/ {print $2}' <<<"${LastLogEntries}" | tail -n1)"
			FinishSeconds=$(date --date="${FinishTime}" '+%s')
			Duration="$(( ${FinishSeconds} - ${sec_last} ))"
			DurationInMin="$(awk '{printf ("%0.1f",$1/60); }' <<<"${Duration}")"
			DisplayTime=" ($(tr '.' ',' <<<"${DurationInMin}") Min.) | duration=${DurationInMin}"
		fi

		EndTime="$(tail -n5 "${BorgLog}" | awk -F" " '/ beendet: / {print $6". "$5" "$7}')"
		StartTime="$(date --date="${last}" '+%e. %b. %H:%M:%S')"

		echo -e "<<<<online-${ComputerName##*/}>>>>\n<<<mrpe>>>"
		
		# interpret the amount of fails
		if [ "${sec_crit}" -gt "${sec_last}" ]; then
			Status="2 CRIT"
		elif [ "${sec_warn}" -gt "${sec_last}" ]; then
			Status="1 WARN"
		else
			Status="0 OK"
		fi

		# check for running backup
		df | awk -F":" '/\/tmp\/borg-backups.sh/ {print $1}' | grep -q "${HostName}"
		case $? in
			0)
				BackupPrefix="Backup läuft gerade, l"
				Status="0 OK"
				;;
			*)
				BackupPrefix="L"
				;;
		esac

		echo -e "(${0##*/}) Borg%20Backup ${Status} - ${BackupPrefix}etztes Pull-Backup erstellt: ${StartTime} - ${EndTime}${DisplayTime}\n<<<<>>>>"
	fi
done