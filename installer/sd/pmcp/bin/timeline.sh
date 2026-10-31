#!/bin/ksh
# SPDX-License-Identifier: GPL-3.0-or-later
# pmcp GEM button (read-only): when did the parts of the CarPlay map start after the unit started?
# Runs on MMX (where GEM runs its scripts, the HMI, dio_manager, gal and the navigation live). Writes nothing anywhere.
#
# Press it once the CarPlay map is on the AID. Each line: seconds after procnto (the unit start) + process / marker.
#   pidin times    process start times (format checked first: if it has no seconds, the raw lines are shown instead)
#   ls -l          /ramdisk markers of our CarPlay path (minute precision only, shown for order)
#   sloginfo       system log lines about navigation, cluster and CarPlay (they carry their own times)
# The unit clock starts at Jan 01 00:00 1970 on power-on (no time yet from the car), so "Jan 01 00:MM:SS" in the
# system log is the time since the unit started.
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin
unset LD_PRELOAD
AWK=/mnt/app/armle/usr/bin/gawk
[ -x "$AWK" ] || AWK=awk
WANT='procnto|smartphone_integ|dio_manager|carplay|altscreen|gal|j9|navi|nav_|displaymanager|kombi|mapviewer|mmi3g|vdm'

echo "pmcp start timeline (read-only), now: `date 2>/dev/null`"
if ! type pidin >/dev/null 2>&1; then
    echo "pidin not found on this unit"
else
    pidin info 2>/dev/null | while read l; do case "$l" in *[Bb]oot*) echo "$l" ;; esac; done
    # seconds of each start time relative to procnto's; works with "Mon DD HH:MM:SS" or "HH:MM:SS" in the line
    pidin times 2>/dev/null | LC_ALL=C $AWK -v want="$WANT" '
        function secs(line,   m) {
            if (match(line, /[0-9][0-9]?:[0-9][0-9]:[0-9][0-9]/)) {
                split(substr(line, RSTART, RLENGTH), m, ":"); return m[1] * 3600 + m[2] * 60 + m[3]
            }
            return -1
        }
        NR == 1 { head = $0; next }
        {
            s = secs($0); low = tolower($0)
            if (base == "" && low ~ /procnto/ && s >= 0) base = s
            if (low ~ want) { n++; line[n] = $0; t[n] = s }
        }
        END {
            if (base == "") {
                print "pidin times: no start time with seconds; raw lines:"; print head
                for (i = 1; i <= n && i <= 25; i++) print line[i]
                exit
            }
            print "+sec  process (pidin times, procnto = unit start)"
            for (i = 1; i <= n && i <= 25; i++) {
                d = t[i] - base; if (d < 0) d += 86400
                split(line[i], f, " "); printf "%5d  %s %s\n", d, f[1], f[2]
            }
        }'
fi
echo "--- /ramdisk markers (minute only)"
for f in /ramdisk/carplay-dio-manager.pid /ramdisk/carplay-altstream.ready /ramdisk/carplay-bridge.ready; do
    [ -e "$f" ] && ls -l "$f" 2>/dev/null
done
echo "--- system log: navigation / cluster / MOST / CarPlay (Jan 01 00:MM:SS = time since unit start)"
if type sloginfo >/dev/null 2>&1; then
    sloginfo 2>/dev/null | grep -iE 'navi|kombi|cluster|map.?ready|mapview|most|bap|altscreen|displaymanager|first connect|CONNECTED' 2>/dev/null \
        | grep -viE 'AirPlay\]|HTTPServer|BENCH_Startup 2 2[56]' 2>/dev/null | head -30
else
    echo "sloginfo not found"
fi
# CarPlay cluster path (read-only): the supervisor's own event log (t_us = microseconds, monotonic clock since the unit
# started) shows when the alt stream was ready, when it took MOST over (oem-most-release), retries and fallbacks.
echo "--- CarPlay cluster path: supervisor events (s since unit start)"
RD=${PMCP_RAMDISK:-/ramdisk}
for f in $RD/carplay-cluster-supervisor.log $RD/carplaymaps-diagnostics/last-supervisor.log; do
    [ -r "$f" ] || continue
    echo "[$f]"
    LC_ALL=C $AWK '{
        if (match($0, /t_us=[0-9]+/)) { us = substr($0, RSTART + 5, RLENGTH - 5); sub(/t_us=[0-9]+ */, ""); printf "%7.1f  %s\n", us / 1000000, $0 }
        else print
    }' "$f" 2>/dev/null | head -25
    break
done
for f in $RD/carplaymaps-launcher.log $RD/carplay_altscreen_handshake/handshake.log; do
    [ -r "$f" ] && { echo "[$f]"; head -12 "$f"; }
done
echo "PMCP_TIMELINE_DONE"
