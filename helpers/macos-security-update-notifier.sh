#!/bin/sh
#
# Notification helper for macOS security updates. Can be used in conjunction with
# https://github.com/ThomasKaiser/Check_MK/blob/master/agents/check_mk_agent.macosx
# or launchd cronjobs or tools like JAMF Pro (execution every 15 minutes is fine).
# If you want to use both check_mk_agent and this script the latter should be saved
# as /usr/local/bin/macos-security-update-notifier (needs to be executable)
#
# (C) 2021 by Thomas Kaiser. Parts of the script borrowed from Installomator therefore
# Apache License 2.0 applies: https://github.com/Installomator/Installomator/blob/dev/LICENSE

RestartNeeded=0
DialogTimeout=5 # value in minutes
NotifyDelay=30 # value in minutes

AdditionalInfoURL="https://web.example.org/update-notifier-addon.txt"

# functions

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

	# check whether additional information should be displayed in the nag dialog based
	# on macOS version. Apple's behaviour trying to push users to most recent macOS is
	# not wanted in most organizations where admins first have to evaluate what will
	# break and what won't function any more prior to rolling out a major macOS update.
	
	# get major macOS number (10 for Catalina, 11 for Big Sur , 12 for Monterey)
	OSVersion="$(sw_vers | awk -F" " '/ProductVersion/ {print $2}' | cut -f1 -d'.')"
	
	# additional info string fetched from the provided URL has to contain macOS version
	# to be ignored as the first 2 characters immediately followed by the string that
	# should be displayed if a version mismatch happend. Might look like this
	# "12Please ignore macOS Monterey and click directly below on more information"
	AdditionalInfo="$(curl -q "${AdditionalInfoURL}" 2>/dev/null)"
	
	if [ "X${AdditionalInfo}" != "X" ]; then
		MostRecentMacOSVersion="$(cut -c-2 <<<"${AdditionalInfo}")"
		if [ "X${OSVersion}" != "X${MostRecentMacOSVersion}" ]; then
			# machine is not on most recent macOS version so display then
			# provided warning to not update immediately:
			AdditionalDisplayText="\n\n$(cut -c3- <<<"${AdditionalInfo}")"
		fi
	fi

	button=$(DisplayDialog "${message}${AdditionalDisplayText}" "${button1}" "${button2}" "${defaultbutton}" "${title}" "${logo}" "${dialogtimeout}")
	if [[ ${button} != "${button2}" ]]; then
		runAsUser open /System/Library/PreferencePanes/SoftwareUpdate.prefPane
	fi
} # NotifyUpdate

AppleLocale="$(runAsUser defaults read -g AppleLocale)"
case ${AppleLocale} in
	de_*)
		LaterButton="Später"
		NowButton="Sofort einspielen"
		LunchText="Mittagspause in Sicht und wichtiges Security-Update steht an. Neustart leider erforderlich."
		EveningText="Feierabend in Sicht und wichtiges Security-Update steht an. Neustart leider erforderlich."
		MinorUpdateText="Kleines Security-Update steht an, das keinen Neustart erfordert, also kurz und schmerzlos direkt eingespielt werden kann."
		DeferText="Wichtiges Security-Update steht seit mehr als 48 Stunden an. Neustart erforderlich."
		;;
	*)
		LaterButton="Later"
		NowButton="Update now"
		LunchText="It is lunch time and an important security update is due. Reboot required."
		EveningText="Quitting time soon and an important security update is due. Reboot required."
		MinorUpdateText="A minor security update needs to be installed. Quick and easy and no reboot needed."
		DeferText="An important security update is due for more than 48 hours. Reboot required."
		;;
esac

# If security updates are available, then display a nag screen to the user sitting in 
# front of the machine.

# check only every ${NotifyDelay} minutes for available software updates
CheckNeeded=$(find /var/run/de.arts-others.softwareupdatecheck -mtime +$(( ${NotifyDelay} - 1 ))m 2>/dev/null)
if [ $? -ne 0 -o "X${CheckNeeded}" = "X/var/run/de.arts-others.softwareupdatecheck" ]; then
	# file doesn't exist or is older than $NotifyDelay-1 minutes -- let's (re)create it
	# First check that older instances of 'softwareupdate -l' are killed:
	ps auxww | grep "softwareupdate -l$" | grep -v grep | awk -F" " '{print $2}' | while read ; do
		kill ${REPLY}
	done
	softwareupdate -l 2>/dev/null | grep -i recommended >/var/run/de.arts-others.softwareupdatecheck
fi
if [ -s /var/run/de.arts-others.softwareupdatecheck ]; then
	# check for needed restarts
	RestartNeeded=$(grep -c -i 'restart' /var/run/de.arts-others.softwareupdatecheck)
fi

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

# If a reboot is needed for more than 2 days then annoy the user every ${NotifyDelay}
# minutes otherwise only prior to lunch break or home time:
if [ ${RestartNeeded} -gt 0 -a "X${CheckNeeded}" = "X/var/run/de.arts-others.softwareupdatecheck" ]; then
	if [ "X${TooOld}" = "X/var/run/de.arts-others.softwareupdatecheck.timestamp" ]; then
		# reboot needed for more than 2 days now. Let's annoy the user with a warn dialog
		# every ${NotifyDelay} minutes
		NotifyUpdate "${DeferText}" "${NowButton}" "${LaterButton}" "${LaterButton}" $(( ${DialogTimeout} * 120 ))
	else
		# if reboot is needed since less than 48 hours only inform users when lunch break or home time is due
		CurrentHour=$(date '+%H')
		case ${CurrentHour} in
			12)
				# annoy users between 12:00 and 12:59
				NotifyUpdate "${LunchText}" "${NowButton}" "${LaterButton}" "${LaterButton}" $(( ${DialogTimeout} * 60 ))
				;;
			13)
				CurrentMinute=$(date '+%M')
				if [ ${CurrentMinute} -le 31 ]; then
					# annoy users only between 13:00 and 13:31
					NotifyUpdate "${LunchText}" "${NowButton}" "${LaterButton}" "${LaterButton}" $(( ${DialogTimeout} * 60 ))
				fi
				;;
			17|18|19|20|21|22|23)
				NotifyUpdate "${EveningText}" "${NowButton}" "${LaterButton}" "${LaterButton}" $(( ${DialogTimeout} * 60 ))
				;;
			*)
				:
				;;
		esac
	fi
elif [ -s /var/run/de.arts-others.softwareupdatecheck -a "X${CheckNeeded}" = "X/var/run/de.arts-others.softwareupdatecheck" ]; then
	NotifyUpdate "${MinorUpdateText}" "${NowButton}" "${LaterButton}" "${NowButton}" $(( ${DialogTimeout} * 60 ))
fi
