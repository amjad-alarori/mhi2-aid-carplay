#!/bin/ksh
# SPDX-License-Identifier: GPL-3.0-or-later
# pmcp GEM button (read-only): what the iPhone sent last for route guidance, and which VW arrow it gives.
# Reads the rgi-observer mailbox (/ramdisk/carplay-route-guidance/latest.bin: RGM1 header + RGI1 snapshot with up to
# 16 iAP2 messages 0x5201 route / 0x5202 maneuver / 0x5204 lane). Writes nothing anywhere.
#
# Per maneuver: type, driving side, junction, exit angle, and the arrow Tomasz's LiveModel.map() makes of it
# (main 0 = no arrow; package rg then tries its maneuver fallbacks, rg/lanes/maneuvers.py). Per lane: position, status, angles and the direction byte LaneData.direction() sends.
# Last: the day/night values dio_manager sent to the phone (system log). Press it while the maneuver is coming up.
# gawk needs LC_ALL=C-TRADITIONAL on QNX: its "C" locale is multibyte and bytes >= 128 get lost (audit A44).
export PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/usr/bin
unset LD_PRELOAD
AWK=/mnt/app/armle/usr/bin/gawk
[ -x "$AWK" ] || AWK=awk
RGM=${PMCP_RG_MAILBOX:-/ramdisk/carplay-route-guidance}

echo "pmcp route guidance: last messages from the iPhone (read-only)"
if [ -r "$RGM/status.txt" ]; then cat "$RGM/status.txt"; else echo "no $RGM/status.txt (RG system off or reader not running)"; fi
if [ ! -r "$RGM/latest.bin" ]; then
    echo "no $RGM/latest.bin"
    echo "PMCP_RGLAST_DONE"
    exit 0
fi
SIZE=`ls -l "$RGM/latest.bin" 2>/dev/null | $AWK '{print $5}'`
# first locale in which one byte >= 128 is one character (C-TRADITIONAL on the unit, C on a host)
LOC=C
for l in C-TRADITIONAL C; do
    LC_ALL=$l LANG=$l $AWK 'BEGIN { exit length(sprintf("%c", 200)) != 1 }' 2>/dev/null && { LOC=$l; break; }
done
LC_ALL=$LOC LANG=$LOC $AWK -v size="$SIZE" '
    function u16(p) { return B[p] + B[p+1] * 256 }
    function u32(p) { return u16(p) + u16(p+2) * 65536 }
    function be(p, n,   v, i) { v = 0; for (i = 0; i < n; i++) v = v * 256 + B[p+i]; return v }
    function txt(p, n,   s, i) { s = ""; for (i = 0; i < n && i < 40; i++) if (B[p+i] >= 32) s = s sprintf("%c", B[p+i]); return s }
    function sang(p,   v) { v = be(p, 2); return v >= 32768 ? v - 65536 : v }
    # LaneData.direction() (tomasz): degrees -> direction byte, 255 = invalid
    function ldir(d,   a, sec) { if (d < -180 || d > 180) return 255; a = d < 0 ? -d : d; sec = int((a * 16 + 180) / 360); return d < 0 ? (sec * 16) % 256 : (256 - sec * 16) % 256 }
    # lanes (rg, rg/lanes/uturn.py): U-turn lanes as the VW bytes 114 (left) / 146 (right)
    function ldir2(d) { if (d <= -170 || d == 180) return 114; if (d >= 170 && d < 180) return 146; return ldir(d) }
    # 0x5204 lane list: key 2 = one nested TLV per lane (0 position, 1 status, 2 angle (repeat), 3 highlight angle)
    function lanes(q, end,   tl, key, at, sz, r, lt, lk, la, out) {
        out = ""
        while (q + 4 <= end) {
            tl = be(q, 2); key = be(q + 2, 2); if (tl < 4 || q + tl > end) break
            if (key == 2) {
                r = q + 4; out = out " ["
                while (r + 4 <= q + tl) {
                    lt = be(r, 2); lk = be(r + 2, 2); if (lt < 4 || r + lt > q + tl) break
                    if (lk == 0 && lt == 6) out = out "pos=" be(r + 4, 2)
                    if (lk == 1 && lt == 5) out = out " st=" B[r + 4]
                    if (lk == 2 && lt == 6) { la = sang(r + 4); out = out " a=" la "/" ldir(la) "|" ldir2(la) }
                    if (lk == 3 && lt == 6) { la = sang(r + 4); out = out " hl=" la "/" ldir(la) "|" ldir2(la) }
                    r += lt
                }
                out = out "]"
            } else if (key == 1 && tl == 6) out = out " idx=" be(q + 4, 2)
            q += tl
        }
        return out
    }
    # LiveModel.map() (tomasz 024dd159), main element and direction; main 0 = no arrow
    function arrow(   t, a, j, side, ang, sk, d) {
        if (!(3 in V)) return "0 0 (no type)"
        t = V[3]; a = (11 in V) ? V[11] : 0; j = (9 in V) ? V[9] : -1; side = (8 in V) ? V[8] : -1
        ang = (11 in V) && a >= -180 && a <= 180; sk = side == 0 || side == 1
        if (t == 0 || t == 5 || t == 15 || t == 17) return "11 0 (follow)"
        if (t == 10 || t == 12 || t == 27) return "3 0 (arrived)"
        if (t == 52 || t == 53) return "12 change lane"
        if (t == 11 || t == 16 || t == 51) return ang ? "13 turn by angle" : "0 0 (turn without angle)"
        if (j != 0 && j != 1) return "0 0 (junction missing/unknown)"
        if (t == 6) return sk ? "13 roundabout entry" : "0 0 (side unknown)"
        if (t == 7 || t == 19 || (t >= 28 && t <= 46)) {
            if (j != 1 || !sk) return "0 0 (roundabout needs junction=1 and side)"
            if (t == 19) return (side == 1 ? 22 : 21) " 128 (U-turn at roundabout)"
            return ang || t == 7 ? "21/22/26/27 roundabout" : "0 0 (roundabout exit without angle)"
        }
        if (j != 0) return "0 0 (junction=1 for a non-roundabout type)"
        if (t == 24 || t == 25) return "3 arrived side"
        if (t == 1 || t == 2 || t == 3 || t == 13 || t == 14 || t == 20 || t == 21 || t == 22 || t == 23 || (t >= 47 && t <= 50)) return "13 turn"
        if (t == 4 || t == 18 || t == 26) {
            if (ang && a != 0) return "25 " (a < 0 ? 64 : 192) " (U-turn by angle)"
            return sk ? "25 " (side == 1 ? 192 : 64) " (U-turn by side)" : "0 0 (U-turn, side unknown)"
        }
        if ((t == 8 || t == 9) && ang && a != 0) return "13 ramp"
        return "0 0 (type not handled)"
    }
    BEGIN { RS = "\n"; for (i = 0; i < 256; i++) ORD[sprintf("%c", i)] = i; n = 0
            if (length(sprintf("%c", 200)) != 1 || length(ORD) != 256) { print "gawk byte table broken (locale)"; bad = 1; exit } }
    { s = $0 RT; m = length(s); for (i = 1; i <= m; i++) B[n++] = ORD[substr(s, i, 1)] }
    END {
        if (bad) exit
        if (n < 96 || txt(0, 4) != "RGM1" || txt(32, 4) != "RGI1") { print "mailbox: unknown format (read " n " of " size " bytes)"; exit }
        printf "mailbox: %d bytes, record %d kind %d (1=snapshot 2=invalidated 3=stale)\n", n, u32(12), u32(16)
        if (u32(16) != 1) exit
        count = u32(32 + 24); p = 96
        printf "snapshot: session %d, sequence %d, %d messages (oldest first)\n", u32(32 + 16), u32(32 + 20), count
        for (k = 0; k < count && p + 16 <= n; k++) {
            seq = u32(p); id = u16(p + 4); len = u16(p + 6); q = p + 16; end = q + len; p = end
            split("", V); road = ""; extra = ""
            while (q + 4 <= end) {
                tl = be(q, 2); key = be(q + 2, 2); if (tl < 4 || q + tl > end) break
                at = q + 4; sz = tl - 4
                if (id == 20994) {                       # 0x5202 maneuver
                    if (key == 1 || key == 3 || key == 7 || key == 8 || key == 9 || key == 12 || key == 5) V[key] = be(at, sz)
                    if (key == 11 && sz == 2) { V[11] = be(at, 2); if (V[11] >= 32768) V[11] -= 65536 }
                    if (key == 2) extra = txt(at, sz)
                    if (key == 4 || key == 6) road = road (road == "" ? "" : "/") txt(at, sz)
                } else if (id == 20993) {                # 0x5201 route: state 1, order list 13
                    if (key == 1) V[1] = be(at, sz)
                    if (key == 13 && sz >= 2) V[13] = be(at, 2)
                }
                q += tl
            }
            if (id == 20994)
                printf "#%d maneuver idx=%s type=%s side=%s junction=%s angle=%s -> arrow %s  [%s] %s\n", seq,
                    (1 in V) ? V[1] : "-", (3 in V) ? V[3] : "-", (8 in V) ? V[8] : "-", (9 in V) ? V[9] : "-",
                    (11 in V) ? V[11] : "-", arrow(), road, extra
            else if (id == 20993)
                printf "#%d route state=%s next maneuver idx=%s\n", seq, (1 in V) ? V[1] : "-", (13 in V) ? V[13] : "-"
            else
                printf "#%d lanes%s\n", seq, lanes(p - len, p)
        }
    }' "$RGM/latest.bin"
echo "lanes: a=angle/VW lane byte without|with U-turn lanes (rg: VW U-turn 114 left, 146 right), hl = highlighted, st = status (1-2 recommended)"
echo "--- day/night sent to the phone (dio_manager, system log, last 8)"
if type sloginfo >/dev/null 2>&1; then
    sloginfo 2>/dev/null | grep -i 'night' 2>/dev/null | tail -8
fi
echo "arrow = strict mapping; where it is main 0 the rg package may still show a fallback arrow (start, roundabout turns)"
echo "types: 4/18/26 U-turn, 19 U-turn at roundabout, 1/2 left/right, 6/7 roundabout, 28-46 roundabout exit N"
echo "PMCP_RGLAST_DONE"
