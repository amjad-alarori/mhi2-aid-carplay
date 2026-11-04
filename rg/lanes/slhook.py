# SPDX-License-Identifier: GPL-3.0-or-later
"""Optional native speed-limit prefix in rg's TurnToInfo text (after asf.py; build modes *-asf*).

    slhook.py STAGED_LANE_DIR LANES_DIR

rg replaces TurnToInfo.setTurnToInfoStatusData (asf.py), so the sl package (speedlimit/) no longer patches that class.
Instead rg's text passes through SpeedLimitText, which asks sl by name: without sl or with its mode off the text is
unchanged. rg's refresh loop compares the decorated text, so a new limit is sent like a new street name.
"""
import pathlib
import shutil
import sys

lane_dir, src = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])


def patch(text, old, new, what, count=1):
    if text.count(old) != count:
        sys.exit("slhook.py: %s: expected text found %d times, want %d" % (what, text.count(old), count))
    return text.replace(old, new)


for name in ("SpeedLimitText", "TestSpeedLimitText"):
    shutil.copy2(src / (name + ".java"), lane_dir / (name + ".java"))
p = lane_dir / "LiveBridge.java"
s = p.read_text()
s = patch(s, "            String road=RoadName.current(frame,time);\n",
          "            String road=SpeedLimitText.preview(RoadName.current(frame,time));\n", "refresh road")
s = patch(s, "        out.reset();out.turnToInfo.setContent(RoadName.current(f,now()));\n",
          "        out.reset();out.turnToInfo.setContent(SpeedLimitText.apply(RoadName.current(f,now())));\n", "turnTo text")
p.write_text(s)
print("slhook.py: speed-limit prefix hook staged in %s" % lane_dir)
