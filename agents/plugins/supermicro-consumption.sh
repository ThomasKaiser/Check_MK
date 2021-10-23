#!/bin/bash
#
# (C) 2021 Thomas Kaiser, t.kaiser@arts-others.de
#
# Script that returns server consumption on systems that expose this
# via ACPI as /sys/devices/LNXSYSTM:00/LNXSYBUS:00/ACPI000D:00/power1_average 
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


SysFSNode="$(ls /sys/devices/LNXSYSTM\:00/LNXSYBUS\:0?/ACPI000D\:00/power1_average)"
# 'find /sys/devices/LNXSYSTM\:00 -name power1_average' is ~20 times less efficient

if [ -f "${SysFSNode}" ]; then
	# set averaging interval to 30 seconds
	read AverageInterval <"${SysFSNode%/*}/power1_average_interval"
	if [ ${AverageInterval} -ne 30000 ]; then
		echo 30000 >"${SysFSNode%/*}/power1_average_interval" 2>/dev/null
	fi
	# read raw consumption
	read RawConsumption <"${SysFSNode}"
	if [ ${RawConsumption} -gt 0 ]; then
		# report consumption in W
		Consumption=$(( ${RawConsumption} / 1000000 ))
		# if power1_oem_info contains something report it in brackets
		read OEMInfo <"${SysFSNode%/*}/power1_oem_info"
		echo "<<<mrpe>>>"
		if [ "X${OEMInfo}" = "X" ]; then
			echo "(${0##*/}) Power%20Consumption 0 OK - ${Consumption}W | consumption=${Consumption:-0}"
		else
			echo "(${0##*/}) Power%20Consumption 0 OK - ${Consumption}W (${OEMInfo}) | consumption=${Consumption:-0}"
		fi
	fi
fi
