#!/bin/bash
#
# Check if Ubuntu hosts want a reboot and why. On systems where 
# the Canonical Livepatching service is active and the relevant
# check-canonical-livepatch.sh MRPE check is present this will
# deny the need for a reboot even if /var/run/reboot-required
# tells a different story (since livepatching makes the reboot
# optional).
#
# Otherwise in case /var/run/reboot-required exists the status
# will change to WARN or even CRIT after one day.
#
# In mrpe.cfg define like this for example:
# Reboot%20needed (interval=10800) /usr/lib/check_mk_agent/check-for-reboot.sh
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

if [ -f /var/run/reboot-required ]; then
	# reboot needed?
	if [ -f ${0##*/}/check-canonical-livepatch.sh ]; then
		# Canonical Live Patching deployed
		LivePatchStatus="$(${0##*/}/check-canonical-livepatch.sh)"
		case ${LivePatchStatus} in
			OK*)
				# Live Patching works
				ExitCode=0
				Summary="kernel live patching enabled"
				;;
			WARNING*)
				# Live Patching works but last check failed (e.g. due to
				# Canonical servers not reachable or something like this)
				ExitCode=0
				Summary="kernel live patching enabled, last check failed"
				;;
			*)
				# Live Patching failed
				ExitCode=2
				Summary="kernel live patching failed. Reboot required"
				;;
		esac
	else
		Packages="$(tr '\n' ',' </var/run/reboot-required.pkgs | sed -e 's/,/, /g' -e 's/,\ $//')"
		OlderThanOneDay=$(find /var/run/reboot-required -mtime +1)
		if [ "X${OlderThanOneDay}" = "X" ]; then
			ExitCode=1
			Summary="some packages require a reboot (${Packages})"
		else
			ExitCode=2
			Summary="some packages require a reboot since more than 1 day (${Packages})"
		fi
	fi
else
	ExitCode=0
	Summary="no reboot required"
fi

case ${ExitCode} in
	0)
		echo "OK - ${Summary}"
		;;
	1)
		echo "WARN - ${Summary}"
		;;
	2)
		echo "CRIT - ${Summary}"
		;;
esac
exit ${ExitCode}
