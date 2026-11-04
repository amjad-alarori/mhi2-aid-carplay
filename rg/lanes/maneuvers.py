# SPDX-License-Identifier: GPL-3.0-or-later
"""Maneuver fallbacks (package rg, build mode lanes-uturn-asf-m) where Tomasz's strict LiveModel.map() shows no arrow
because iOS left a field out. On the staged sources after asf.py.

    maneuvers.py STAGED_LANE_DIR LANES_DIR   -> patches STAGED_LANE_DIR/LiveModel.java, copies TestManeuvers.java

Rule (user decision 2026-11-03): whatever the strict map() already maps stays exactly as it is; only where it returns
no symbol (main 0) the mapping of harman-f/mhi2_altscreen_carplay (Skoda MU1440, same VW BAP NavSD main elements,
GPL-3.0, modules/menu/source/java/de/mibr/hmi/MibrRgiManeuvers.java, git c01bbdc) is used:
  11/16 without an exit angle               -> 13/0   (start of route, ferry exit: straight); 51 stays empty
  1,2,3,13,14,20-23,47-50 without junction  -> 13 + the type's own direction (20/21 refined like the strict map)
  the same at a roundabout (junction 1)     -> roundabout 21 (22 left-hand): exit direction from a known angle that
                                               agrees with the type (16 bins), else from the type (real turns only);
                                               angle against the type, or keep/ramp types without angle -> no arrow;
                                               4/18/26 -> 21/128
  4/18/26 U-turn without angle and side     -> 25/64  (right-hand traffic assumed: the car drives in Poland)
  6 roundabout entry without side           -> 13/192 (right-hand traffic)
  7 roundabout exit, 19 U-turn at roundabout, without junction 1 / side -> 26/192, 21/128 (right-hand traffic)
  8/9 ramps without a signed angle          -> 13 slight to the traffic side (right-hand: 224)
  24/25 destination left/right with odd junction -> 3/64, 3/192
NOT taken (user decision): harman-f's roundabout exits 28-46 without an angle (guess from the exit number); they stay
without an arrow. Unknown types stay 0 (harman-f NO_INFO 1 draws nothing either). Each replacement must match once.
"""
import pathlib
import shutil
import sys

lane_dir, src = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])


def patch(text, old, new, what):
    if text.count(old) != 1:
        sys.exit("maneuvers.py: %s: expected text found %d times" % (what, text.count(old)))
    return text.replace(old, new)


shutil.copy2(src / "TestManeuvers.java", lane_dir / "TestManeuvers.java")
p = lane_dir / "LiveModel.java"
s = p.read_text()
s = patch(s, "    static int[] map(Message m) {\n        if (m==null || !m.has[3]) return symbol(0,0);\n",
          """    // pmcp m: the strict map below is unchanged; fallback() only fills its "no arrow" results (maneuvers.py).
    static int[] map(Message m) {
        int[] strict=mapStrict(m);
        return strict[0]!=0 || m==null || !m.has[3]?strict:fallback(m);
    }
    // Adapted from harman-f/mhi2_altscreen_carplay MibrRgiManeuvers.map (GPL-3.0-or-later), without 28-46 guessing.
    static int[] fallback(Message m) {
        int t=(int)m.v[3], a=(int)m.v[11], side=m.has[8]?(int)m.v[8]:-1;
        boolean known=m.has[11] && a>=-180 && a<=180, signed=known && a!=0, lht=side==1;
        int d=turnDirection(t,known,a);
        // pmcp (user 2026-11-03): a turn type at a roundabout (junction 1) is the roundabout symbol with that exit
        // direction (e.g. left = the exit to the left), not a plain turn. harman-f ignores the junction field.
        if (m.has[9] && m.v[9]==1) {
            int ring=lht?22:21;
            if (t==4 || t==18 || t==26) return symbol(ring,128);
            boolean ramp=t==8 || t==9, keep=t==13 || t==14 || t==22 || t==23;
            if (d>=0 || ramp) {
                if (known) {
                    // A real exit angle wins (16 bins like the strict 28-46), but only when it agrees with the type.
                    boolean agree=ramp?a!=0:d==0?Math.abs(a)<=22:d<128?a<0:a>0;
                    if (!agree) return symbol(0,0);
                    int[] bins={128,112,96,80,64,48,32,16,0,240,224,208,192,176,160,144,128};
                    return symbol(ring,bins[((a+180)*4+45)/90]);
                }
                // Without an angle only real turns become a roundabout exit; keep/ramp inside a roundabout: no arrow.
                return ramp || keep?symbol(0,0):symbol(ring,d);
            }
        }
        if (d>=0) return symbol(13,d);
        switch (t) {
        case 4: case 18: case 26: return symbol(25,signed?(a<0?64:192):(lht?192:64));
        case 6: return symbol(13,lht?64:192);
        case 7: return lht?symbol(27,64):symbol(26,192);
        case 8: case 9: return symbol(13,signed?(a<0?32:224):(lht?32:224));
        case 11: case 16: return symbol(13,known?turn(a):0);   // 51 (highway change) without angle: no arrow (user)
        case 19: return symbol(lht?22:21,128);
        case 24: return symbol(3,64);
        case 25: return symbol(3,192);
        default: return symbol(0,0);
        }
    }
    // Direction of the plain turn types, -1 for the others. 20/21 refined like the strict map (never straight).
    static int turnDirection(int t,boolean known,int a) {
        switch (t) {
        case 1: return 64;
        case 2: return 192;
        case 3: return 0;
        case 13: case 22: case 49: return 32;
        case 14: case 23: case 50: return 224;
        case 47: return 96;
        case 48: return 160;
        case 20: return known && a<0?(Math.abs(a)<=67?32:Math.abs(a)>112?96:64):64;
        case 21: return known && a>0?(Math.abs(a)<=67?224:Math.abs(a)>112?160:192):192;
        default: return -1;
        }
    }
    static int[] mapStrict(Message m) {
        if (m==null || !m.has[3]) return symbol(0,0);
""", "map -> mapStrict + fallback")
p.write_text(s)
print("maneuvers.py: map() fallbacks staged in %s" % lane_dir)
