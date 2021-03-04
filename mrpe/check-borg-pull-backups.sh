#!/bin/bash
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
		
		echo -e "<<<<online-${ComputerName##*/}>>>>\n<<<mrpe>>>"
		
		# interpret the amount of fails
		if [ "${sec_crit}" -gt "${sec_last}" ]; then
			echo "(${0##*/}) Borg%20Backup 2 CRIT - last pull backup made on ${last}"
		elif [ "${sec_warn}" -gt "${sec_last}" ]; then
			echo "(${0##*/}) Borg%20Backup 1 WARN - last pull backup made on ${last}"
		else
			echo "(${0##*/}) Borg%20Backup 0 OK - last pull backup made on ${last}"
		fi
	
		echo "<<<<>>>>"
	fi
done