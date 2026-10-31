#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Native VW lane guidance (tomasz-twardzicki MU1367 v1.4.0, commit 7925a83) on our route guidance sources.
Host tool, used by rg/build.sh.

  python3 -I apply_lanes.py TOMASZ_REPO OUT_DIR

Runs Tomasz's own stage.guidance() unchanged (counted edits: each must match exactly once) over the hash-pinned
MU1427/route-guidance/bridge sources of TOMASZ_REPO, with LaneData.java from this folder. Prints the staged source dir.
"""
import importlib.util
import pathlib
import sys

sys.dont_write_bytecode = True   # -I ignores PYTHONDONTWRITEBYTECODE; never write __pycache__ next to the sources

here = pathlib.Path(__file__).resolve().parent
tomasz, out = pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]).resolve()
spec = importlib.util.spec_from_file_location("tomasz_lane_stage", here / "stage.py")
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)
stage.HERE, stage.REPO = here, tomasz      # his layout: HERE = MU1367/lanes, REPO = repository root
print(stage.guidance(out))
