#!/bin/bash
#
# Monitoring plugin to query different server types via IPMI for power consumption
# and fan speeds. Creates two sensors 'Consumption' and 'Fan Summary' per server via
# the piggyback mechanism as such servers should be named exactly as they're defined
# in Check_MK
#
# Needs IPMI logon credentials in a file /etc/ipmi-credentials containing colon
# delimited three strings per server:
#
# * server name
# * IPMI user account
# * respective password
#
# For example:
#
# dell-1:checkmk:secret
# dell-2:checkmk:supersecret
#
# The 'ipmitool dcmi power reading' output from a queried server might look like
#
#    Instantaneous power reading:                   144 Watts
#    Minimum during sampling period:                 66 Watts
#    Maximum during sampling period:                206 Watts
#    Average power reading over sample period:      148 Watts
#    IPMI timestamp:                           Sat Oct 23 08:25:52 2021
#    Sampling period:                          01987338 Seconds.
#    Power reading state is:                   activated
#
# Please be aware that when using SuperMicro's SMCIPMITool full logon credentials are
# exposed in process listings. The usual way to hide the passwort by calling the IPMI
# tool in question with -E and exporting IPMITOOL_PASSWORD prior to this doesn't work.

credentialFile=/etc/ipmi-credentials
credentialPermissions="$(ls -la "${credentialFile}" | awk -F" " '{print $1}')"
case ${credentialPermissions} in
	*------)
		IPMICredentials="$(cat "${credentialFile}")"
		;;
	*)
		echo '${credentialFile} must only be readable by root. Aborting.' >&2
		exit 1
		;;
esac

# functions

ParseCacheforPower() {
	for sensor in CPU_Power Memory_Power "PSU1 Power Out" "PSU2 Power Out" ; do
		Value="$(awk -F'|' "/^${sensor} / {print \$2}" <"${IPMICache}" | sed 's/ na /0/' | tr -d '[:space:]' | cut -f1 -d'.')"
		SensorName="$(tr ' ' '_' <<<"${sensor}")"
		echo -e "${SensorName}=${Value:-0} \c"
	done
} # ParseCacheforPower

ParseCacheforFans() {
	grep -E "^FRNT_FAN|^FAN" <"${IPMICache}" | grep -v '| na ' | while read ; do
		Value="$(awk -F" " '{print $3}' <<<"${REPLY}" | sed 's/ na /0/' | cut -f1 -d'.')"
		SensorName="$(sed 's/FRNT_//' <<<"${REPLY}" | awk -F" " '{print $1}')"
		echo -e "${SensorName}=${Value:-0} \c"
	done
} # ParseCacheforFans

# query SuperMicro servers
for server in "supermicro-1:192.168.n.n" "supermicro-2:192.168.n.n" ; do
	PiggybackName="$(cut -f1 -d: <<<"${server}")"
	IPv4Address="$(cut -f2 -d: <<<"${server}")"
	IPMICredentials=($(awk -F":" "/^${PiggybackName}:/ {print \$2\" \"\$3}" <"${credentialFile}"))
	export IPMITOOL_PASSWORD=${IPMICredentials[1]}
	PowerInfo="$(ipmitool -H ${IPv4Address} -U ${IPMICredentials[0]} -E dcmi power reading)"
	
	PowerReadingState=$(awk -F" " '/Power reading state is/ {print $5}' <<<"${PowerInfo}")
	if [ "X${PowerReadingState}" = "Xactivated" ]; then
		CurrentConsumption=$(awk -F" " '/Instantaneous power reading/ {print $4}' <<<"${PowerInfo}")
		IPMIMinConsumption=$(awk -F" " '/Minimum during sampling period/ {print $5}' <<<"${PowerInfo}")
		IPMIMaxConsumption=$(awk -F" " '/Maximum during sampling period/ {print $5}' <<<"${PowerInfo}")
		IPMIAverageConsumption=$(awk -F" " '/Average power reading over sample period/ {print $7}' <<<"${PowerInfo}")
		SamplingPeriod=$(awk -F" " '/Sampling period/ {print $3}' <<<"${PowerInfo}")
		SamplingDays=$(bc <<<"${SamplingPeriod} / 86400")
		if [ ${CurrentConsumption} -gt 0 ]; then
			# create a file consisting of 1439 entries with last consumption readouts so we
			# can generate a 24 hour average
			touch /root/.consumption-${PiggybackName}
			PriorValues="$(tail -n1439 /root/.consumption-${PiggybackName})"
			echo -e "${PriorValues}\n${CurrentConsumption}" | sed '/^[[:space:]]*$/d' >/root/.consumption-${PiggybackName}
			CountOfEntries="$(wc -l </root/.consumption-${PiggybackName})"
			SumOfEntries=$(awk '{s+=$1} END {printf "%.0f", s}' </root/.consumption-${PiggybackName})
			AverageConsumption=$(( ${SumOfEntries} / ${CountOfEntries} ))
			MinConsumption=$(sort /root/.consumption-${PiggybackName} | head -n1)
			MaxConsumption=$(sort /root/.consumption-${PiggybackName} | tail -n1)

			# query IPMI sensors separately
			IPMICache=/root/.ipmi-cache-${PiggybackName}
			/usr/bin/ipmitool -H ${IPv4Address} -U ${IPMICredentials[0]} -E sensor >"${IPMICache}"
			PowerSummary="$(ParseCacheforPower)"
			FanSummary="$(ParseCacheforFans)"

			echo -e "<<<<${PiggybackName}>>>>\n<<<mrpe>>>"
			echo "(${0##*/}) Consumption 0 OK right now: ${CurrentConsumption}W, last 24 hours: ${AverageConsumption}W (${SamplingDays} days IPMI: ${IPMIMinConsumption}W / ${IPMIAverageConsumption}W / ${IPMIMaxConsumption}W) | consumption=${CurrentConsumption:-0} avg_consumption=${AverageConsumption:-0} min_consumption=${MinConsumption:-0} max_consumption=${MaxConsumption:-0}"
			echo -e "<<<mrpe>>>\n(${0##*/}) Fan%20Summary 0 OK - All fans OK | ${FanSummary}"
			echo "<<<<>>>>"
		fi
	fi
done

# query Dell servers, they need -I lanplus for a newer protocol revision and also report
# Sampling period: 00000001 Seconds which we translate into 7 days for now (comparison with
# iDrac's powermonitor.html output let me believe it's weekly averaged values).
for server in "dell-1:192.168.n.n" "dell-2:192.168.n.n" ; do
	PiggybackName="$(cut -f1 -d: <<<"${server}")"
	IPv4Address="$(cut -f2 -d: <<<"${server}")"
	IPMICredentials=($(awk -F":" "/^${PiggybackName}:/ {print \$2\" \"\$3}" <"${credentialFile}"))
	export IPMITOOL_PASSWORD=${IPMICredentials[1]}
	PowerInfo="$(ipmitool -H ${IPv4Address} -U ${IPMICredentials[0]} -E -I lanplus dcmi power reading)"
	
	PowerReadingState=$(awk -F" " '/Power reading state is/ {print $5}' <<<"${PowerInfo}")
	if [ "X${PowerReadingState}" = "Xactivated" ]; then
		CurrentConsumption=$(awk -F" " '/Instantaneous power reading/ {print $4}' <<<"${PowerInfo}")
		IPMIMinConsumption=$(awk -F" " '/Minimum during sampling period/ {print $5}' <<<"${PowerInfo}")
		IPMIMaxConsumption=$(awk -F" " '/Maximum during sampling period/ {print $5}' <<<"${PowerInfo}")
		IPMIAverageConsumption=$(awk -F" " '/Average power reading over sample period/ {print $7}' <<<"${PowerInfo}")
		if [ ${CurrentConsumption} -gt 0 ]; then
			# create a file consisting of 1439 entries with last consumption readouts so we
			# can generate a 24 hour average
			touch /root/.consumption-${PiggybackName}
			PriorValues="$(tail -n1439 /root/.consumption-${PiggybackName})"
			echo -e "${PriorValues}\n${CurrentConsumption}" | sed '/^[[:space:]]*$/d' >/root/.consumption-${PiggybackName}
			CountOfEntries="$(wc -l </root/.consumption-${PiggybackName})"
			SumOfEntries=$(awk '{s+=$1} END {printf "%.0f", s}' </root/.consumption-${PiggybackName})
			AverageConsumption=$(( ${SumOfEntries} / ${CountOfEntries} ))
			MinConsumption=$(sort /root/.consumption-${PiggybackName} | head -n1)
			MaxConsumption=$(sort /root/.consumption-${PiggybackName} | tail -n1)
			echo -e "<<<<${PiggybackName}>>>>\n<<<mrpe>>>"
			echo "(${0##*/}) Consumption 0 OK right now: ${CurrentConsumption}W, last 24 hours: ${AverageConsumption}W (7 days IPMI: ${IPMIMinConsumption}W / ${IPMIAverageConsumption}W / ${IPMIMaxConsumption}W) | consumption=${CurrentConsumption:-0} avg_consumption=${AverageConsumption:-0} min_consumption=${MinConsumption:-0} max_consumption=${MaxConsumption:-0}"
			echo "<<<<>>>>"
		fi
	fi
done

# query SuperMicro JBODs, they do not answer to ipmitool so we need SuperMicro's SMCIPMITool
# and do the averaging stuff for ourselves
for server in "supermicro-jbod-1:192.168.n.n" "supermicro-jbod-2:192.168.n.n" ; do
	PiggybackName="$(cut -f1 -d: <<<"${server}")"
	IPv4Address="$(cut -f2 -d: <<<"${server}")"
	IPMICredentials=($(awk -F":" "/^${PiggybackName}:/ {print \$2\" \"\$3}" <"${credentialFile}"))
	export IPMITOOL_PASSWORD=${IPMICredentials[1]}
	if [ -x /usr/local/SMCIPMITool_2.25.0_build.210326_bundleJRE_Linux_x64/SMCIPMITool ]; then
		PowerInfo="$(/usr/local/SMCIPMITool_2.25.0_build.210326_bundleJRE_Linux_x64/SMCIPMITool ${IPv4Address} ${IPMICredentials[0]} "${IPMITOOL_PASSWORD}" pminfo)"
		CurrentConsumption=$(awk -F" " '/^ Input Power/ {s+=$4} END {printf "%.0f", s}' <<<"${PowerInfo}")
		if [ ${CurrentConsumption} -gt 0 ]; then
			# create a file consisting of 1439 entries with last consumption readouts so we
			# can generate a 24 hour average
			touch /root/.consumption-${PiggybackName}
			PriorValues="$(tail -n1439 /root/.consumption-${PiggybackName})"
			echo -e "${PriorValues}\n${CurrentConsumption}" | sed '/^[[:space:]]*$/d' >/root/.consumption-${PiggybackName}
			CountOfEntries="$(wc -l </root/.consumption-${PiggybackName})"
			SumOfEntries=$(awk '{s+=$1} END {printf "%.0f", s}' </root/.consumption-${PiggybackName})
			AverageConsumption=$(( ${SumOfEntries} / ${CountOfEntries} ))
			MinConsumption=$(sort /root/.consumption-${PiggybackName} | head -n1)
			MaxConsumption=$(sort /root/.consumption-${PiggybackName} | tail -n1)
			echo -e "<<<<${PiggybackName}>>>>\n<<<mrpe>>>"
			echo "(${0##*/}) Consumption 0 OK right now: ${CurrentConsumption}W, last 24 hours: ${AverageConsumption}W (${MinConsumption}W min, ${MaxConsumption}W max) | consumption=${CurrentConsumption:-0} avg_consumption=${AverageConsumption:-0} min_consumption=${MinConsumption:-0} max_consumption=${MaxConsumption:-0}"
			echo "<<<<>>>>"
		fi
	else
		echo -e "<<<<${PiggybackName}>>>>\n<<<mrpe>>>"
		echo "(${0##*/}) Consumption 3 UNKN - /usr/local/SMCIPMITool_2.25.0_build.210326_bundleJRE_Linux_x64/SMCIPMITool is missing on $(hostname)"
		echo "<<<<>>>>"	
	fi
done

# query Asus servers
for server in "asus-1:192.168.n.n" "asus-2:192.168.n.n" ; do
	PiggybackName="$(cut -f1 -d: <<<"${server}")"
	IPv4Address="$(cut -f2 -d: <<<"${server}")"
	IPMICredentials=($(awk -F":" "/^${PiggybackName}:/ {print \$2\" \"\$3}" <"${credentialFile}"))
	export IPMITOOL_PASSWORD=${IPMICredentials[1]}
	PowerInfo="$(ipmitool -H ${IPv4Address} -U ${IPMICredentials[0]} -E dcmi power reading 2>/dev/null)"

	PowerReadingState=$(awk -F" " '/Power reading state is/ {print $5}' <<<"${PowerInfo}")
	if [ "X${PowerReadingState}" = "Xactivated" ]; then
		CurrentConsumption=$(awk -F" " '/Instantaneous power reading/ {print $4}' <<<"${PowerInfo}")
		IPMIMinConsumption=$(awk -F" " '/Minimum during sampling period/ {print $5}' <<<"${PowerInfo}")
		IPMIMaxConsumption=$(awk -F" " '/Maximum during sampling period/ {print $5}' <<<"${PowerInfo}")
		IPMIAverageConsumption=$(awk -F" " '/Average power reading over sample period/ {print $7}' <<<"${PowerInfo}")
		SamplingPeriod=$(awk -F" " '/Sampling period/ {print $3}' <<<"${PowerInfo}")
		SamplingDays=$(bc <<<"${SamplingPeriod} / 86400")
		if [ ${CurrentConsumption} -gt 0 ]; then
			# create a file consisting of 1439 entries with last consumption readouts so we
			# can generate a 24 hour average
			touch /root/.consumption-${PiggybackName}
			PriorValues="$(tail -n1439 /root/.consumption-${PiggybackName})"
			echo -e "${PriorValues}\n${CurrentConsumption}" | sed '/^[[:space:]]*$/d' >/root/.consumption-${PiggybackName}
			CountOfEntries="$(wc -l </root/.consumption-${PiggybackName})"
			SumOfEntries=$(awk '{s+=$1} END {printf "%.0f", s}' </root/.consumption-${PiggybackName})
			AverageConsumption=$(( ${SumOfEntries} / ${CountOfEntries} ))
			MinConsumption=$(sort -n /root/.consumption-${PiggybackName} | head -n1)
			MaxConsumption=$(sort -n /root/.consumption-${PiggybackName} | tail -n1)
			NumberofSamples=$(wc -l </root/.consumption-${PiggybackName})
			# Only look at last 30 samples to make graphs compatible with our Netio monitoring
			[ ${NumberofSamples} -gt 30 ] && NumberofSamples=30
			WattSum=$(tail -n${NumberofSamples} /root/.consumption-${PiggybackName} | awk '{s+=$1} END {printf "%.0f", s}')
			WattAverage=$(awk '{printf ("%0.2f",$1/$2); }' <<<"${WattSum} ${NumberofSamples}")

			# query IPMI sensors separately
			IPMICache=/root/.ipmi-cache-${PiggybackName}
			/usr/bin/ipmitool -H ${IPv4Address} -U ${IPMICredentials[0]} -E sensor >"${IPMICache}"
			PowerSummary="$(ParseCacheforPower)"
			FanSummary="$(ParseCacheforFans)"

			echo -e "<<<<${PiggybackName}>>>>\n<<<mrpe>>>"
			echo "(${0##*/}) Consumption 0 OK right now: Wall=${CurrentConsumption}W, $(sed -e 's/_Power//g' -e 's/_Out//g' -e 's/\ /W, /g' <<<"${PowerSummary}")Wall average last 2 hours: ${WattAverage}W / 24 hours: ${MinConsumption}W min, ${AverageConsumption}W avg, ${MaxConsumption}W max | consumption=${CurrentConsumption:-0} avg_consumption=${WattAverage:-0} ${PowerSummary}"
			echo -e "<<<mrpe>>>\n(${0##*/}) Fan%20Summary 0 OK - $(sed -e 's/\ /\, /g' -e 's/=/: /g' -e 's/FAN/Fan /g' -e 's/, $//' <<<"${FanSummary}") | ${FanSummary}"
			echo "<<<<>>>>"
		fi
	fi
done
