# Some Check_MK tweaks

## macOS support

Currently just a slightly tweaked macosx agent (filters out temporarely appearing filesystems, reports compressed memory as swap, reports some thermal sensors) plus LaunchDaemon. Needs

    launchctl load -w /Library/LaunchDaemons/de.mathias-kettner.check_mk.plist

for activation.

For CPU temperature working you need [osx-cpu-temp](https://github.com/lavoiesl/osx-cpu-temp) in `/usr/local/bin` (tested successfully on 2 Mac Mini). For more thermal sensors you need [Marcel Bresink's HardwareMonitor](https://www.bresink.com/osx/HardwareMonitor.html). Then it looks like this with an old MacPro:

![](screenshots/thermal-sensors-macpro.png)
