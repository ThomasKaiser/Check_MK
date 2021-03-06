#!/bin/bash
#
# process-powermetrics-output.sh
#
# Simple script to aid in monitoring macOS machines for thermals, performance
# and power efficiency.
#
# It's designed to run on a separate Linux host with RPi-Monitor graphing the data.
#
# The Macs to be monitored collect powermetrics data and send it over netcat to
# the monitoring host this script is running on. This way we can collect clockspeeds
# and consumption numbers and from Intel machines also SMC data (thermals and fan
# speeds).
#
# Since this sort of data (SMC) is not available on Apple Silicon Macs a 2nd
# attempt using iStatistica (https://www.imagetasks.com/istatistica/) is used
# that collects this sensor data in a pull operation using iStatistica's web
# accessible API calls.
#
# To summarize:
# 
# - each Mac to be monitored needs to run powermetrics in conjunction with Netcat
#   to push this data to a separate netcat instance running on the monitoring host
#   writing the constant stream of data into a log file
# - for thermals and fan speeds on Apple Silicon Macs installation of iStatistica
#   and iStatistica Sensors is needed so the tool's API can queried on port 4027
#
# Prerequisits:
#
# RPi-Monitor on this host (most easy on Raspbian, Debian or Ubuntu):
# sudo apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 2C0D3C0F
# wget -O rpimonitor_2.12-r0_all.deb https://github.com/XavierBerger/RPi-Monitor-deb/blob/master/packages/rpimonitor_2.12-r0_all.deb?raw=true
# dpkg -i rpimonitor_2.12-r0_all.deb
#
# on this host (netcat receiver):
# nc -l 9999 >/tmp/powermetrics-mbp16-tk.log
#
# on an Intel mac (netcat sender):
# powermetrics -s smc,cpu_power,gpu_power 2>/dev/null | egrep --line-buffered "^Intel energy model|^System Average fr|^Package 0 C-st|^CPU/GPU Over|^Cores Active|^GPU Active|^Avg Num of|^CPU Thermal l|^GPU Thermal l|^IO Thermal l|^Fan:|^CPU die t|^GPU die t|^CPU Pl|^GPU Pl|^Number of pr" | nc nagios 9999
#
# on an Apple Silicon mac (netcat sender):
# powermetrics -s cpu_power,gpu_power 2>/dev/null | egrep --line-buffered " Power: | frequency: | active residency: " | nc nagios 9999
#
# If you want to monitor more than one machine you need for each Mac a different port,
# a different log file and also an additional line in the while loop below.
#
# The unprocessed powermetrics output will look like this on an Intel machine:
#
# Intel energy model derived package power (CPUs+GT+SA): 1.07W
# System Average frequency as fraction of nominal: 59.63% (1550.27 Mhz)
# Package 0 C-state residency: 76.12% (C2: 8.66% C3: 0.14% C6: 1.89% C7: 12.72% C8: 52.72% C9: 0.00% C10: 0.00% )
# CPU/GPU Overlap: 0.20%
# Cores Active: 21.10%
# GPU Active: 0.44%
# Avg Num of Cores Active: 0.31
# CPU Thermal level: 0
# GPU Thermal level: 0
# IO Thermal level: 0
# Fan: 1823.21 rpm
# CPU die temperature: 36.80 C
# GPU die temperature: 35.00 C
# CPU Plimit: 0.00
# GPU Plimit (Int): 0.00 
# Number of prochots: 0
#
# Unprocessed powermetrics output will look like this on an Apple Silicon machine:
#
# ANE Power: 0 mW
# DRAM Power: 9 mW
# GPU Power: 0 mW
# E-Cluster Power: 16 mW
# P-Cluster Power: 1 mW
# Package Power: 25 mW
# Clusters Total Power: 16 mW
# cpu 0 active residency:   4.83% (600 MHz: .01% 972 MHz: 3.7% 1332 MHz: .65% 1704 MHz: .32% 2064 MHz: .15%)
# cpu 0 frequency: 1103 MHz
# cpu 1 active residency:   5.12% (600 MHz: .00% 972 MHz: 3.8% 1332 MHz: .75% 1704 MHz: .32% 2064 MHz: .22%)
# cpu 1 frequency: 1116 MHz
# cpu 2 active residency:   4.27% (600 MHz: .20% 972 MHz: 2.9% 1332 MHz: .52% 1704 MHz: .31% 2064 MHz: .39%)
# cpu 2 frequency: 1150 MHz
# cpu 3 active residency:   4.05% (600 MHz: .01% 972 MHz: 3.3% 1332 MHz: .36% 1704 MHz: .15% 2064 MHz: .25%)
# cpu 3 frequency: 1099 MHz
# cpu 4 active residency:   0.07% (600 MHz: .04% 828 MHz: .00% 1056 MHz: .00% 1284 MHz:   0% 1500 MHz:   0% 1728 MHz:   0% 1956 MHz: .02% 2184 MHz:   0% 2388 MHz:   0% 2592 MHz:   0% 2772 MHz:   0% 2988 MHz:   0% 3096 MHz:   0% 3144 MHz:   0% 3204 MHz:   0%)
# cpu 4 frequency: 1049 MHz
# cpu 5 active residency:   0.01% (600 MHz: .00% 828 MHz: .00% 1056 MHz: .00% 1284 MHz:   0% 1500 MHz:   0% 1728 MHz:   0% 1956 MHz: .00% 2184 MHz:   0% 2388 MHz:   0% 2592 MHz:   0% 2772 MHz:   0% 2988 MHz:   0% 3096 MHz:   0% 3144 MHz:   0% 3204 MHz:   0%)
# cpu 5 frequency: 1259 MHz
# cpu 6 active residency:   0.00% (600 MHz: .00% 828 MHz:   0% 1056 MHz: .00% 1284 MHz:   0% 1500 MHz:   0% 1728 MHz:   0% 1956 MHz: .00% 2184 MHz:   0% 2388 MHz:   0% 2592 MHz:   0% 2772 MHz:   0% 2988 MHz:   0% 3096 MHz:   0% 3144 MHz:   0% 3204 MHz:   0%)
# cpu 6 frequency: 924 MHz
# cpu 7 active residency:   0.00% (600 MHz: .00% 828 MHz:   0% 1056 MHz:   0% 1284 MHz:   0% 1500 MHz:   0% 1728 MHz:   0% 1956 MHz:   0% 2184 MHz:   0% 2388 MHz:   0% 2592 MHz:   0% 2772 MHz:   0% 2988 MHz:   0% 3096 MHz:   0% 3144 MHz:   0% 3204 MHz:   0%)
# cpu 7 frequency: 600 MHz
# E-Cluster HW active frequency: 992 MHz
# E-Cluster HW active residency:  12.16% (600 MHz: .20% 972 MHz:  97% 1332 MHz: 1.4% 1704 MHz: .92% 2064 MHz: .87%)
# P-Cluster HW active frequency: 609 MHz
# P-Cluster HW active residency:   0.07% (600 MHz:  99% 828 MHz: .06% 1056 MHz: .05% 1284 MHz:   0% 1500 MHz:   0% 1728 MHz:   0% 1956 MHz: .67% 2184 MHz:   0% 2388 MHz:   0% 2592 MHz:   0% 2772 MHz:   0% 2988 MHz:   0% 3096 MHz:   0% 3144 MHz:   0% 3204 MHz:   0%)
# GPU active frequency: 396 MHz
# GPU active residency:   0.33% (396 MHz: .33% 528 MHz:   0% 720 MHz:   0% 924 MHz:   0% 1128 MHz:   0% 1278 MHz:   0%)
# GPU requested frequency: (396 MHz: .33% 528 MHz:   0% 720 MHz:   0% 924 MHz:   0% 1128 MHz:   0% 1278 MHz:   0%)
#
# iStatistica's sensors and fans API queries look like this for example:
#
# root@nagios:~# curl -s "http://${IPAddress}:4027/api/sensors"
# {
#   "PMU tdie4" : "27",
#   "pACC MTR Temp Sensor2" : "22",
#   "PMU2 TR5d" : "24",
#   "PMU tdev7" : "24",
#   "PMU2 TR2l" : "30",
#   "SOC MTR Temp Sensor1" : "22",
#   "gas gauge battery" : "23",
#   "pACC MTR Temp Sensor5" : "22",
#   "PMU2 TR4d" : "23",
#   "PMU2 TR1l" : "30",
#   "PMU tdie5" : "28",
#   "PMU2 TR0Z" : "51",
#   "pACC MTR Temp Sensor8" : "22",
#   "eACC MTR Temp Sensor0" : "19",
#   "ANE MTR Temp Sensor1" : "30",
#   "PMU tdev3" : "24",
#   "PMGR SOC Die Temp Sensor1" : "23",
#   "PMU2 TR2d" : "24",
#   "PMU tdev8" : "23",
#   "PMU tdie1" : "29",
#   "PMU2 TR8b" : "30",
#   "eACC MTR Temp Sensor3" : "20",
#   "pACC MTR Temp Sensor3" : "21",
#   "NAND CH0 temp" : "22",
#   "PMU tdev4" : "24",
#   "SOC MTR Temp Sensor0" : "22",
#   "PMU tdie6" : "27",
#   "PMU2 TR7b" : "30",
#   "ISP MTR Temp Sensor5" : "30",
#   "PMU2 TR6b" : "29",
#   "PMU tdie2" : "25",
#   "PMGR SOC Die Temp Sensor0" : "22",
#   "pACC MTR Temp Sensor9" : "22",
#   "PMU2 TR5b" : "30",
#   "PMU tdev5" : "23",
#   "PMU tdie7" : "26",
#   "GPU MTR Temp Sensor1" : "30",
#   "PMU2 TR4b" : "29",
#   "GPU MTR Temp Sensor4" : "30",
#   "pACC MTR Temp Sensor4" : "24",
#   "PMU2 TR3b" : "29",
#   "SOC MTR Temp Sensor2" : "20",
#   "PMU tcal" : "51",
#   "PMGR SOC Die Temp Sensor2" : "22",
#   "pACC MTR Temp Sensor7" : "20",
#   "PMU tdie8" : "25",
#   "PMU TP3w" : "27"
# 
# root@nagios:~# curl -s "http://${IPAddress}:4027/api/fans"
# {
#   "Fan 1" : "1211"
# }
#
# The script will then run in an infinite loop parsing the logfiles transmitted via
# netcat as well as pulling sensor data via HTTP from iStatistica and will create
# for each sensor available a single file below /tmp/rpimonitor/$mac/ containing the
# sensor value so these files can then be used in RPi-Monitor templates to be graphed:
#
# root@nagios:/tmp/rpimonitor/mbp13-yb# for file in * ; do echo -e "${file}\t$(<${file})"; done
# ane_mtr_1	30
# ane_power	0
# cpu0_freq	1043
# cpu0_resid	16.02
# cpu1_freq	1029
# cpu1_resid	23.43
# cpu2_freq	1037
# cpu2_resid	13.90
# cpu3_freq	1011
# cpu3_resid	10.27
# cpu4_freq	966
# cpu4_resid	0.33
# cpu5_freq	788
# cpu5_resid	0.06
# cpu6_freq	641
# cpu6_resid	0.03
# cpu7_freq	623
# cpu7_resid	0.03
# cpu_power	50
# dram_power	56
# eacc_mtr_0	25
# eacc_mtr_3	20
# e_freq	1018
# e_power	46
# e_resid	45.49
# fan_1	1211
# gas_gauge_bat	24
# gpu_freq	708
# gpu_mtr_1	30
# gpu_mtr_4	30
# gpu_power	121
# gpu_resid	19.13
# isp_mtr_5	30
# nand_ch0_temp	24
# pacc_mtr_2	23
# pacc_mtr_3	25
# pacc_mtr_4	24
# pacc_mtr_5	24
# pacc_mtr_7	23
# pacc_mtr_8	24
# pacc_mtr_9	24
# p_freq	607
# pmgr_soc_die_0	24
# pmgr_soc_die_1	24
# pmgr_soc_die_2	24
# pmu2_tr0z	51
# pmu2_tr1d	26
# pmu2_tr1l	31
# pmu2_tr2d	26
# pmu2_tr2l	32
# pmu2_tr3b	30
# pmu2_tr3d	26
# pmu2_tr4b	31
# pmu2_tr4d	25
# pmu2_tr5b	31
# pmu2_tr5d	24
# pmu2_tr6b	31
# pmu2_tr7b	31
# pmu2_tr8b	31
# pmu_tcal	51
# pmu_tdev1	26
# pmu_tdev2	26
# pmu_tdev3	26
# pmu_tdev6	26
# pmu_tdev7	26
# pmu_tdev8	27
# pmu_tdie1	32
# pmu_tdie2	28
# pmu_tdie4	30
# pmu_tdie5	30
# pmu_tdie6	30
# pmu_tdie7	30
# pmu_tdie8	29
# pmu_tp3w	31
# power	172
# p_power	4
# p_resid	0.35
# soc_avg	23.33
# soc_mtr_0	23
# soc_mtr_1	24
# soc_mtr_2	21
#
# To ease creation of RPi monitor templates the following script can be used to create
# the data input section:
#
# #!/bin/bash
# i=1
# for dir in /tmp/rpimonitor/* ; do
# 	MachineName=$(sed 's/-/_/g' <<<${dir##*/})
# 	for file in ${dir}/* ; do
# 		NodeName=${file##*/}
# 		echo "dynamic.${i}.name=${MachineName}_${NodeName}"
# 		echo "dynamic.${i}.source=${file}"
# 		echo "dynamic.${i}.regexp=(.*)"
# 		echo "dynamic.${i}.postprocess="
# 		echo "dynamic.${i}.rrd=GAUGE"
# 		echo ""
# 		((i++))
# 	done
# done
#
# The end results of this script (graphs drawn by RPi-Monitor) look like this for example:
# https://github.com/ThomasKaiser/Knowledge/blob/master/articles/Exploring_Apple_Silicon_on_MacBookAir10.md

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

TmpFile=$(mktemp /tmp/${0##*/}.XXXXXX)
trap "rm \"${TmpFile}\" ; exit 0" 0 1 2 3 15

CheckMachine() {
	Machine=$1
	MachineDir=/tmp/rpimonitor/${Machine}
	[ -d ${MachineDir} ] || mkdir -p -m2777 ${MachineDir}
	Logfile=/tmp/powermetrics-${Machine}.log
	tail -n 31 ${Logfile} | sort -u >${TmpFile}
	
	grep -q "^Intel energy model" ${TmpFile}
	case $? in
		0)
			# Intel
			grep "^Intel energy model" ${TmpFile} | tail -n1 | cut -f2 -d':' | tr -d -c '[:digit:]' >${MachineDir}/power
			grep "^System Average fr" ${TmpFile} | tail -n1 | awk -F" " '{print $9}' | sed 's/(//' | cut -d'.' -f1 >${MachineDir}/avg_freq
			grep "^Package 0 C-st" ${TmpFile} | tail -n1 | awk -F" " '{print $5}' | sed 's/%//' >${MachineDir}/c_state_resid
			grep "^CPU/GPU Over" ${TmpFile} | tail -n1 | awk -F" " '{print $3}' | sed 's/%//' >${MachineDir}/cpu_gpu_overlap
			grep "^Cores Active" ${TmpFile} | tail -n1 | awk -F" " '{print $3}' | sed 's/%//' >${MachineDir}/cores_active
			grep "^GPU Active" ${TmpFile} | tail -n1 | awk -F" " '{print $3}' | sed 's/%//' >${MachineDir}/gpu_active
			grep "^Avg Num of" ${TmpFile} | tail -n1 | awk -F" " '{print $6}' >${MachineDir}/avg_cores_active
			grep "^CPU Thermal l" ${TmpFile} | tail -n1 | awk -F" " '{print $4}' >${MachineDir}/cpu_therm_level
			grep "^GPU Thermal l" ${TmpFile} | tail -n1 | awk -F" " '{print $4}' >${MachineDir}/gpu_therm_level
			grep "^IO Thermal l" ${TmpFile} | tail -n1 | awk -F" " '{print $4}' >${MachineDir}/io_therm_level
			grep "^Fan:" ${TmpFile} | tail -n1 | awk -F" " '{print $2}' >${MachineDir}/fan_rpm
			grep "^CPU die t" ${TmpFile} | tail -n1 | awk -F" " '{print $4}' >${MachineDir}/cpu_die_temp
			grep "^GPU die t" ${TmpFile} | tail -n1 | awk -F" " '{print $4}' >${MachineDir}/gpu_die_temp
			grep "^CPU Pl" ${TmpFile} | tail -n1 | awk -F" " '{print $3}' >${MachineDir}/cpu_plimit
			grep "^GPU Pl" ${TmpFile} | tail -n1 | awk -F" " '{print $4}' >${MachineDir}/gpu_plimit
			grep "^Number of pr" ${TmpFile} | tail -n1 | awk -F" " '{print $4}' >${MachineDir}/prochots
			;;
		*)
			# Apple Silicon
			awk -F' ' '/ANE Power:/ {print $3}' ${TmpFile} | tail -n1 >${MachineDir}/ane_power
			awk -F' ' '/DRAM Power:/ {print $3}' ${TmpFile} | tail -n1 >${MachineDir}/dram_power
			awk -F' ' '/GPU Power:/ {print $3}' ${TmpFile} | tail -n1 >${MachineDir}/gpu_power
			awk -F' ' '/E-Cluster Power:/ {print $3}' ${TmpFile} | tail -n1 >${MachineDir}/e_power
			awk -F' ' '/P-Cluster Power:/ {print $3}' ${TmpFile} | tail -n1 >${MachineDir}/p_power
			awk -F' ' '/Package Power:/ {print $3}' ${TmpFile} | tail -n1 >${MachineDir}/power
			awk -F' ' '/Clusters Total Power:/ {print $4}' ${TmpFile} | tail -n1 >${MachineDir}/cpu_power

			awk -F' ' '/E-Cluster HW active residency/ {print $5}' ${TmpFile} | sed 's/%//' >${MachineDir}/e_resid
			awk -F' ' '/E-Cluster HW active frequency/ {print $5}' ${TmpFile} >${MachineDir}/e_freq
			awk -F' ' '/P-Cluster HW active residency/ {print $5}' ${TmpFile} | sed 's/%//' >${MachineDir}/p_resid
			awk -F' ' '/P-Cluster HW active frequency/ {print $5}' ${TmpFile} >${MachineDir}/p_freq
			awk -F' ' '/GPU active residency/ {print $4}' ${TmpFile} | sed 's/%//' >${MachineDir}/gpu_resid
			awk -F' ' '/GPU active frequency/ {print $4}' ${TmpFile} >${MachineDir}/gpu_freq
			for i in {0..7} ; do
				awk -F' ' "/cpu ${i} frequency/ {print \$4}" ${TmpFile} >${MachineDir}/cpu${i}_freq
				awk -F' ' "/cpu ${i} active residency/ {print \$5}" ${TmpFile} | sed 's/%//' >${MachineDir}/cpu${i}_resid
			done
			;;
	esac
} # CheckMachine

CheckThermals() {
	# query thermal sensors, machine name and IP address are needed as arguments
	Machine=$1
	MachineDir=/tmp/rpimonitor/${Machine}
	IPAddress=$2
	fping -t 100 ${IPAddress} >/dev/null 2>&1 || return
	curl -s "http://${IPAddress}:4027/api/sensors" 2>/dev/null | awk -F'"' '/:/ {print $2"="$4}' \
		| sed -e 's/Temp//' -e 's/\ /_/g' -e 's/__/_/' -e 's/Sensor//' -e 's/battery/bat/' \
		| tr '[:upper:]' '[:lower:]' | while read ; do
			echo ${REPLY##*=} >${MachineDir}/${REPLY%=*}
	done
	# average SoC temperatures
	echo "$(cat ${MachineDir}/*soc* | awk -F',' '{sum+=$1;} END{print sum;}') / 6" | bc -l | cut -c-5 >${MachineDir}/soc_avg
	
	# check fans if available
	curl -s "http://${IPAddress}:4027/api/fans" 2>/dev/null | awk -F'"' '/:/ {print $2"="$4}' \
		| sed -e 's/\ /_/g' | tr '[:upper:]' '[:lower:]' | while read ; do
			echo ${REPLY##*=} >${MachineDir}/${REPLY%=*}
	done
}

while true ; do
	CheckMachine mbp16-tk
	CheckMachine mbair-tk
	CheckThermals mbair-tk 10.0.64.6
	CheckMachine mbp13-yb
	CheckThermals mbp13-yb 10.0.64.7
	sleep 1
done