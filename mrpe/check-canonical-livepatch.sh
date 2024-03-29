#!/bin/bash
#
# checkmk MRPE check for Canonical Livepatch status
#
# If your servers are equipped with Canonical's Livepatch Service
# -- see https://ubuntu.com/livepatch -- then you clearly want the
# status in your monitoring system.
#
# - if checkState is not 'checked' this is WARN
# - if running is not true this is CRIT
# - if patchState is neither 'nothing-to-apply' nor 'applied' this is CRIT
#
# In mrpe.cfg define like this for example:
# Canonical%20Live%20Patch (interval=3600) /usr/lib/check_mk_agent/check-canonical-livepatch.sh
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

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin

if type canonical-livepatch >/dev/null 2>&1 ; then
	LivePatchStatus="$(canonical-livepatch status)"
else
	# no kernel live patching active. Exiting
	exit 0
fi

checkState="$(awk -F": " '/checkState/ {print $2}' <<<"${LivePatchStatus}")"
patchState="$(awk -F": " '/patchState/ {print $2}' <<<"${LivePatchStatus}")"
kernelVersion="$(awk -F": " '/kernel/ {print $2}' <<<"${LivePatchStatus}")"
patchVersion="$(awk -F": " '/ version:/ {print $2}' <<<"${LivePatchStatus}" | tr -d '[="=]')"
tier="$(awk -F"(" '/^tier:/ {print $2}' <<<"${LivePatchStatus}" | tr -d ')')"
isRunning="$(awk -F": " '/ running/ {print $2}' <<<"${LivePatchStatus}")"

Result="OK"
ExitCode=0

if [ "X${checkState}" != "Xchecked" ]; then
	Result="WARNING"
	ExitCode=1
fi

case ${isRunning} in
	true)
		DaemonState="running"
		;;
	*)
		DaemonState="not running"
		Result="CRITICAL"
		ExitCode=2
		;;
esac

if [ "X${patchState}" = "Xnothing-to-apply" -o "X${patchState}" = "Xapplied" ]; then
	:
else
	Result="CRITICAL"
	ExitCode=2
fi

if [[ ${tier} == *"beta test"* ]]; then
	AdditionalInfo=", ${tier}"
	if [ ${ExitCode} -eq 0 ]; then
		Result="WARNING"
		ExitCode=1
	fi
fi

echo "${Result} - kernel ${kernelVersion} (${patchVersion}), ${DaemonState}, ${checkState}, patch state: ${patchState}${AdditionalInfo}"
exit ${ExitCode}
