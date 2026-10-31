#!/bin/ksh
# SPDX-License-Identifier: GPL-3.0-or-later
# pmcp GEM button (read-only): why does the VW navigation not start? Writes nothing anywhere.
# Written after a failed start-order trial (docs/en/14-fast-start-audit.md), when the navigation seemed to stop at
# "NAVI: Startup SDK in progress".
# navStartup (factory) keeps its start state in /mnt/persist: NAVI_START_DB / NAVI_START_POI (map / POI scan at the next
# start), SWDL_SD1 / SWDL_SD2 / SWDL_OTA (software download from SD card 1 / 2 / OTA), and a start counter
# (RESETCOUTERLIMITREACHED). This shows them, the navigation processes and all navigation lines of the system log.
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin
unset LD_PRELOAD

echo "pmcp navigation diagnostics (read-only), now: `date 2>/dev/null`"
echo "--- /mnt/persist: navigation start markers"
for f in NAVI_START_DB NAVI_START_POI SWDL_SD1 SWDL_SD2 SWDL_OTA; do
    if [ -e "/mnt/persist/$f" ]; then
        echo "$f: present, `ls -l "/mnt/persist/$f" 2>/dev/null`"
        echo "  content: `head -c 64 "/mnt/persist/$f" 2>/dev/null | od -c 2>/dev/null | head -2`"
    else
        echo "$f: -"
    fi
done
echo "--- /mnt/persist (names with nav/swdl/start)"
ls -la /mnt/persist 2>/dev/null | grep -iE 'navi|swdl' 2>/dev/null
echo "--- update marker on RCC"
ls -l /net/rcc/mnt/efs-persist/SWDL/update.txt 2>/dev/null || echo "update.txt: -"
echo "--- navigation processes (cpu seconds: utime stime)"
pidin times 2>/dev/null | grep -iE 'navi|nav_|pnav|drcontrol|iconprovider|mapviewer|navstart|navcore' 2>/dev/null
echo "--- freeze / deadlock info"
ls -l /mnt/app/core 2>/dev/null | head -10
ls -l /navigation/EBNavFreeze* /tmp/NONAVIWD 2>/dev/null
echo "--- system log: navigation lines"
if type sloginfo >/dev/null 2>&1; then
    sloginfo 2>/dev/null | grep -iE 'navi:|navstart|swdl|database|startup counter|freeze|prescon|esocomm' 2>/dev/null | tail -20
else
    echo "sloginfo not found"
fi
echo "--- system log: cluster map (kombi / MOST stream sink / display management)"
if type sloginfo >/dev/null 2>&1; then
    sloginfo 2>/dev/null | grep -iE 'kombi|komo|mapview|streamsink|gfxstream|kombidisplay|displaymanagement|most.?kombi|altscreen' 2>/dev/null | tail -20
fi
echo "--- our CarPlay cluster path (supervisor log, last lines)"
tail -8 /ramdisk/carplay-cluster-supervisor.log 2>/dev/null || echo "no supervisor log this start"
ls -l /ramdisk/carplay-altstream.ready 2>/dev/null
echo "PMCP_NAVDIAG_DONE"
