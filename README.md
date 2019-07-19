# Some Check_MK tweaks

## macOS support

Currently just a slightly tweaked macosx agent (filter out temporarely appearing filesystems, report compressed memory as swap, report CPU temperature) plus LaunchDaemon. Needs

    launchctl load -w /Library/LaunchDaemons/de.mathias-kettner.check_mk.plist

for activation. For CPU temperature working you need [osx-cpu-temp](https://github.com/lavoiesl/osx-cpu-temp) in `/usr/local/bin` (tested only on 2 Mac Mini).
