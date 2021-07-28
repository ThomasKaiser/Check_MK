#!/bin/sh
#
# Notification helper for macOS security updates. Can be used in conjunction with
# https://github.com/ThomasKaiser/Check_MK/blob/master/agents/check_mk_agent.macosx
# If you want to use both check_mk_agent and this script the latter should be saved
# as /usr/local/bin/macos-security-update-notifier (needs to be executable)

RestartNeeded=0

# check only every 30 minutes for available software updates
CheckNeeded=$(find /var/run/de.arts-others.softwareupdatecheck -mtime +29m 2>/dev/null)
if [ $? -ne 0 -o "X${CheckNeeded}" = "X/var/run/de.arts-others.softwareupdatecheck" ]; then
	# file doesn't exist or is older than 29 minutes -- let's (re)create it
	cp -p /var/run/de.arts-others.softwareupdatecheck /var/run/de.arts-others.softwareupdatecheck.old 2>/dev/null
	(softwareupdate -l 2>/dev/null | grep -i recommended >/var/run/de.arts-others.softwareupdatecheck) &
fi
if [ -s /var/run/de.arts-others.softwareupdatecheck.old ]; then
	# check for needed restarts
	RestartNeeded=$(grep -c -i 'restart' /var/run/de.arts-others.softwareupdatecheck.old)
else
	echo "No updates pending for installation"
fi

# If security updates are available, then display a nag screen to the user sitting in 
# front of the machine.

runAsUser() {
	currentUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ { print $3 }')
	if [[ ${currentUser} != "loginwindow" ]]; then
		uid=$(id -u "${currentUser}")
		launchctl asuser $uid sudo -u ${currentUser} "$@"
	fi
} # runAsUser

DisplayDialog() {
	runAsUser osascript -e "button returned of (display dialog \"${1}\" with  title \"${5}\" buttons {\"${2}\", \"${3}\"} default button \"${4}\" with icon POSIX file \"${6}\" giving up after ${7})"
} # DisplayDialog

NotifyUpdate() {
	message=${1}
	button1=${2}
	button2=${3}
	defaultbutton=${4}
	dialogtimeout=${5}
	title="A&O Softwareupdate"
	logo="/System/Applications/App Store.app/Contents/Resources/AppIcon.icns"

	button=$(DisplayDialog "${message}" "${button1}" "${button2}" "${defaultbutton}" "${title}" "${logo}" "${dialogtimeout}")
	if [[ ${button} != "${button2}" ]]; then
		runAsUser open /System/Library/PreferencePanes/SoftwareUpdate.prefPane
	fi
} # NotifyUpdate

# Check if reboot is needed since more than 47 hours
if [ ${RestartNeeded} -gt 0 ]; then
	if [ -f /var/run/de.arts-others.softwareupdatecheck.timestamp ]; then
		TooOld=$(find /var/run/de.arts-others.softwareupdatecheck.timestamp -mtime +47h 2>/dev/null)
	else
		date > /var/run/de.arts-others.softwareupdatecheck.timestamp
	fi
else
	rm /var/run/de.arts-others.softwareupdatecheck.timestamp 2>/dev/null
fi

# Notify user about pending software updates only every 30 minutes. If a reboot is needed
# for more than 2 days then annoy the user every 30 minutes otherwise only prior to lunch
# break or home time:
if [ ${RestartNeeded} -gt 0 -a "X${CheckNeeded}" = "X/var/run/de.arts-others.softwareupdatecheck" ]; then
	if [ "X${TooOld}" = "X/var/run/de.arts-others.softwareupdatecheck.timestamp" ]; then
		# reboot needed for more than 2 days now. Let's annoy the user with a warn dialog
		# that times out only after 10 minutes (600 seconds)
		NotifyUpdate "Wichtiges Security-Update steht seit mehr als 48 Stunden an. Neustart erforderlich." "Sofort einspielen" "Später" "Später" 600
	else
		# if reboot is needed since less than 48 hours only inform users when lunch break or home time is due
		CurrentHour=$(date '+%H')
		case ${CurrentHour} in
			12)
				NotifyUpdate "Mittagspause in Sicht und wichtiges Security-Update steht an. Neustart leider erforderlich." "Sofort einspielen" "Später" "Später" 300
				;;
			17|18|19|20|21|22|23)
				NotifyUpdate "Feierabend in Sicht und wichtiges Security-Update steht an. Neustart leider erforderlich." "Sofort einspielen" "Später" "Später" 300
				;;
			*)
				:
				;;
		esac
	fi
elif [ -s /var/run/de.arts-others.softwareupdatecheck.old -a "X${CheckNeeded}" = "X/var/run/de.arts-others.softwareupdatecheck" ]; then
	NotifyUpdate "Kleines Security-Update steht an, das keinen Neustart erfordert, also kurz und schmerzlos direkt eingespielt werden kann." "Los geht's" "Später" "Los geht's" 300
fi