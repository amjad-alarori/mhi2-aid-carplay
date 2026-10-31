# SPDX-License-Identifier: GPL-3.0-or-later
"""U-turn lanes on the VW cluster (package rglu, after apply_lanes.py, on the staged copies only).

Tomasz's LaneData.direction() turns +/-180 degrees into 128. The MU1161 HMI has no 128 U-turn: the stock navigation
uses exact direction bytes NAV_UTURN_LEFT_DIRECTION = 114 and NAV_UTURN_RIGHT_DIRECTION = 146
(de.vw.mib.asl.internal.navigation.guidance[.laneguidance].HsmTargetLaneGuidance, lsd.jar MU1161), and the BAP lane
function passes direction bytes through unchanged. In the car: the U-turn lane had no arrow.

    uturn.py STAGED_LANE_DIR ORIGINAL_TestLanes.java   -> patches STAGED_LANE_DIR/LaneData.java, writes TestLanes.java there

Mapping: -180..-170 -> 114 (left U-turn), 170..179 -> 146 (right U-turn), exactly 180 -> 114 (sign unknown; right-hand
traffic turns left). Everything else as before. Each replacement must match exactly once.
"""
import pathlib
import sys

lane_dir, test_src = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])


def patch(text, old, new, what):
    if text.count(old) != 1:
        sys.exit("uturn.py: %s: expected text found %d times" % (what, text.count(old)))
    return text.replace(old, new)


ld = lane_dir / "LaneData.java"
src = ld.read_text()
src = patch(src, """        if(degrees < -180 || degrees > 180)return 255;
        int sector=(Math.abs(degrees)*16+180)/360;""", """        if(degrees < -180 || degrees > 180)return 255;
        // pmcp: VW U-turn lane bytes (NAV_UTURN_LEFT/RIGHT_DIRECTION), 180 = right-hand traffic -> left
        if(degrees <= -170 || degrees == 180)return 114;
        if(degrees >= 170)return 146;
        int sector=(Math.abs(degrees)*16+180)/360;""", "LaneData.direction")
ld.write_text(src)

t = test_src.read_text()
t = patch(t, """  for(int a=-180;a<=180;a++){int d=LaneData.direction(a);check(d>=0&&d<=240&&d%16==0,"direction sector");check((d+LaneData.direction(-a))%256==0,"mirrored direction");}
  check(LaneData.direction(-90)==64&&LaneData.direction(90)==192&&LaneData.direction(180)==128,"factory geometry");""",
          """  for(int a=-169;a<=169;a++){int d=LaneData.direction(a);check(d>=0&&d<=240&&d%16==0,"direction sector");check((d+LaneData.direction(-a))%256==0,"mirrored direction");}
  check(LaneData.direction(-90)==64&&LaneData.direction(90)==192,"factory geometry");
  check(LaneData.direction(-180)==114&&LaneData.direction(-170)==114&&LaneData.direction(180)==114,"pmcp: left U-turn lane 114");
  check(LaneData.direction(170)==146&&LaneData.direction(179)==146,"pmcp: right U-turn lane 146");""", "TestLanes")
(lane_dir / "TestLanes.java").write_text(t)
print("uturn.py: LaneData.direction and TestLanes patched in %s" % lane_dir)
