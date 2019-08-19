#!/bin/bash
#
# checkmk agent plugin to check Canonical Livepatch status
# e.g. /usr/local/sbin/check-canonical-livepatch.sh

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin

TmpFile="$(mktemp /tmp/${0##*/}.XXXXXX || exit 1)"
canonical-livepatch status >"${TmpFile}"

checkState="$(awk -F": " '/checkState/ {print $2}' <"${TmpFile}")"
patchState="$(awk -F": " '/patchState/ {print $2}' <"${TmpFile}")"
kernelVersion="$(awk -F": " '/kernel/ {print $2}' <"${TmpFile}")"
patchVersion="$(awk -F": " '/ version/ {print $2}' <"${TmpFile}" | tr -d '[="=]')"
isRunning="$(awk -F": " '/ running/ {print $2}' <"${TmpFile}")"

Result="OK"
ExitCode=0

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

if [ "X${checkState}" != "Xchecked" ]; then
	Result="WARNING"
	ExitCode=1
fi

if [ "X${patchState}" = "Xnothing-to-apply" -o "X${patchState}" = "Xapplied" ]; then
	:
else
	Result="CRITICAL"
	ExitCode=2
fi

echo "${Result} - kernel ${kernelVersion} (${patchVersion}), ${DaemonState}, ${checkState}, patch state: ${patchState}"
rm "${TmpFile}"
exit ${ExitCode}
