# Package E: native route guidance (port of tomasz-twardzicki MU1427 v1.2.0 to MU1161)

[Polska wersja: README.pl.md](README.pl.md)

Status: **works in the car (MU1161 + AID 791, October 2026): ETA, distance to destination and the manoeuvre arrow (once the car moves).** Author of the solution: tomasz-twardzicki (GPL-3.0-or-later),
decoder after luka-dev; map base: omonob. Sources: `upstream/tomasz` @ `024dd159`.

What it gives on the AID (according to Tomasz, checked in his car on MU1427/791):
- arrows and distance to the manoeuvre in the "arrows" view and on the HUD;
- distance and time to destination on the bar above the map.

## Components

| File | Origin | SHA-256 | Where on the unit |
|---|---|---|---|
| `ipod-drvr-iap2.so` (743,196 B) | Tomasz's patch chain on **our** driver | `76926bde…1b48` | `/mnt/app/armle/lib/dll/` |
| `iap2.cfg` (6,079 B) | **our** factory one + his `[ident]` | `c61407d9…b491` | `/mnt/system/etc/mm/` |
| `rgi-observer` (16,606 B) | his binary (source `release/reader.c`) | `b683cef7…08ac` | `/mnt/app/carplaymaps/rg/` |
| `pmcp-rg.jar` (34,082 B, v2) | his `PatchLive` on **our** NavSD classes + his helpers, then our `patcher/GuardLive.java` (every `LiveBridge` call guarded) | `717fb53c…a754` | `/mnt/app/eso/hmi/lsd/jars/` |

## Evidence of compatibility

1. **Driver:** our factory `ipod-drvr-iap2.so` (`7149a3e7…`), after substituting the usage block from MU1427 (0xae3f0–0xae48f:
   DATE, version `61.1`/`61.4`, TAGID, debuglink CRC), has **exactly** the hash of the factory MU1427 driver (`0ac13f43…`).
   So the code is byte for byte the same.
2. Tomasz's chain (`patch-driver.py` → `patch-publication.py` → `patch-activation.py`, clang ARM + pyelftools 0.31) on this
   file reproduces his released driver `3760797a…` **bit for bit**.
3. Our result = his result with our usage block. Differences from our stock: ELF program header (0x94–0xb1),
   6 hooks (0x63f0, 0x909c, 0x9260, 0xe138, 0x10ba8, 0x133a0), appended code (3,271 B). Checked automatically in `build.sh`.
4. **JAR:** 5 of the 6 MU1161 NavSD classes = MU1427 byte for byte, `LaneGuidance` = MU1427 + one serialization fix (the hook at the method
   entry fits). `PatchLive` passed all its assertions, and his `TestLive` on our classes: **123 assertions OK** (same as for him).
5. **Reader:** imports only `libc.so.3`. All 43 strong imports are in the K4525 libc (`485e2a50…`, taken from `mifs-stage1` K4525).
   The 3 weak ones (`_Jv_RegisterClasses`, `__register_frame_info`, `__deregister_frame_info`) are compiler startup code.
   We do not have the MU1161 libc (backup without stage1). **Only the unit will confirm it.**

## Installation (GEM buttons, stage B)

1. "System RG: wlacz": saves the factory driver and cfg in `carplaymaps/rollback/` (hash), replaces the driver and cfg
   (remount `/mnt/app` and `/mnt/system`), installs the reader, and finally the marker `rg/SYSTEM_ON`.
   Does not touch the HMI; worst case: a problem with CarPlay/iPod, which "System RG: wylacz" or "Przywroc" undoes.
2. "Wlacz: Prowadzenie" (Java package `rg`): the JAR through the Java mechanism with a trial start.
3. The reader starts in the background from our `lsd.sh` block, only when `SYSTEM_ON` is present and the Java set loads
   (with Tomasz's arguments: `start-live /dev/ipod0/rgi-events /ramdisk/carplay-route-guidance`).

## Differences from Tomasz and things to do

- Time format: Tomasz sends the time to destination. Here the cluster shows the arrival time (photo `IMG_1083`).
  To do: respect `timeInfoType` (audit A9).
- His installer accepts only MU1427. Ours is our own (pmcp), with hashes instead of sizes alone.
- The reader works for him on MU1427, for us it is unchecked.

## Native VW lane guidance with U-turn lanes (package `rglu`, v1.3.0)

Port of Tomasz's lane guidance from MU1367 v1.4.0 (`upstream/tomasz` @ `7925a83`, works in his car). The files `rg/lanes/stage.py`,
`LaneData.java` and `TestLanes.java` are copied unchanged and pinned by hash. `apply_lanes.py` runs his `stage.guidance()`
on the same pinned bridge sources as `rg`; the bridge sources at `7925a83` are byte for byte the same as at `024dd159`.

- Data: iAP2 RouteGuidanceLaneGuidanceInformation `0x5204` (already in our `iap2.cfg` and reader). Driver, `iap2.cfg` and
  `rgi-observer` unchanged.
- To the AID through the factory `LaneGuidance.computeFullLaneGuidanceList`: two `getLaneGuidance` calls -> `laneIterator`,
  `getRouteGuidanceState` -> `descriptorRouteState`, `isSetupLaneGuidanceActive` -> `lanesVisible` (the patcher checks 2/1/1;
  our class has the same layout). Factory window of 6 lanes, the "lane guidance" setting in the VW menu keeps working.
- `GuardLive ... lanes`: 6 guarded calls in `LaneGuidance`; on a helper error `laneIterator` and `lanesVisible`
  fall back to the factory `getLaneGuidance()` / `isSetupLaneGuidanceActive()`.
- U-turn lanes: Tomasz's lane table has no U-turn arrow. `rg/lanes/uturn.py` (on the staged copies, his files stay unchanged)
  maps a U-turn lane to the VW lane symbols 114 (left) and 146 (right) and adds the matching cases to `TestLanes`.
  Checked in the car (MU1161 + AID 791, 2026-10-31): the U-turn lane shows with its own arrow.
- Build: `rg/build.sh <lsd.jar> <directory> lanes-uturn` -> `pmcp-rg.jar` `72ab7221…` (38529 B), in the package as
  `jars/pmcp-rglu.jar`. `lanes` without the U-turn step gives the earlier lanes-only build (not shipped); without a mode the
  result is byte for byte the base `717fb53c`. Tests: TestLive and TestLanes (on our guarded classes and the factory lane
  table builder).
- Installation: button 3 on card 1 installs `rglu` (an older install with `rg` gets `rglu` instead). Under advanced,
  `java-on rglu` replaces `rg` in the set (new trial start), `java-on rg` goes back. Lanes show only when the phone app sends
  them and lane guidance is enabled in the VW.
