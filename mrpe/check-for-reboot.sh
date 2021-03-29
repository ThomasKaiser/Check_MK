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

export PATH=/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/sbin:/usr/local/bin

if [ -f /var/run/reboot-required ]; then
	# reboot needed?
	if [ -f ${0%/*}/check-canonical-livepatch.sh -a -x /snap/bin/canonical-livepatch ]; then
		# Canonical Live Patching deployed
		LivePatchStatus="$(${0%/*}/check-canonical-livepatch.sh)"
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
		ExitCode=0
	fi
	# check whether there are other than kernel packages that require a reboot
	OutstandingPackages="$(egrep -v "linux-base|linux-image" /var/run/reboot-required.pkgs 2>/dev/null)"
	PackageCheckExitCode=$?
	if [ "X${OutstandingPackages}" != "X" ]; then
		if [ ${ExitCode} -eq 2 ]; then
			# kernel live patching already failed, we need to reboot anyway
			Packages="$(sort </var/run/reboot-required.pkgs | uniq | tr '\n' ',' | sed -e 's/,/, /g' -e 's/,\ $//')"
			Summary="kernel live patching failed and some packages require a reboot (${Packages})"
		else
			# No kernel update involved, just regular packages like e.g. dbus require a reboot
			Packages="$(egrep -v "linux-base|linux-image" /var/run/reboot-required.pkgs | sort | uniq | tr '\n' ',' | sed -e 's/,/, /g' -e 's/,\ $//')"
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
else
	ExitCode=0
	Summary="no reboot required"
fi

# Univention Corporate server
type ucr >/dev/null 2>&1
if [ $? -eq 0 ]; then
	UCSRebootStatus="$(ucr get update/reboot/required)"
	if [ "X${UCSRebootStatus}" = "Xtrue" ]; then
		ExitCode=2
		Summary="some UCS packages require a reboot"
	fi
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
