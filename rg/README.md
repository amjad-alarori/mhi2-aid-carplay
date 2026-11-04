# Package E: native route guidance (package `rg`, port of tomasz-twardzicki MU1427 v1.2.0 to MU1161)

[Polska wersja: README.pl.md](README.pl.md)

Status: **works in the car (MU1161 + AID 791, October 2026): ETA, distance to destination and the manoeuvre arrow (once the car moves);
lanes with U-turn lanes since v1.3.0 (2026-10-31); in v1.4 also the arrow at the start of a route, the street name and the
distance bar before the manoeuvre (car test 2026-11-04).** Author of the solution: tomasz-twardzicki (GPL-3.0-or-later),
decoder and iAP2 maneuver type names after luka-dev; maneuver table of the fallbacks: harman-f; map base: omonob.
Sources: `upstream/tomasz` @ `024dd159` (MU1427), `7925a83` (MU1367 v1.4.0 lanes), `1d69473` (MU1367 v1.4.3).

Since v1.4 there is **one** route guidance Java package, `rg`, built with `rg/build.sh <lsd.jar> <dir> lanes-uturn-asf-m`.
It holds everything below: the MU1427 port, his lanes, our U-turn lanes, his distance bar / street name / feed recovery
and the maneuver fallbacks. The v1.3 packages `rg` (no lanes) and `rglu` are gone; `java-update` (button 3) replaces them,
and the experimental branch's `rglua`, `rgluasf`, `rgluasfa`, `rgluasfm`, `rgluasfma`, by this `rg`.

What it gives on the AID:
- arrows and distance to the manoeuvre in the "arrows" view and on the HUD (also at the start of a route and at roundabout
  turns, see the fallbacks below);
- distance and time to destination on the bar above the map;
- native VW lane guidance, including U-turn lanes (when the phone app sends lanes and lane guidance is on in the VW);
- the VW distance bar (countdown bargraph) before a manoeuvre and the current street name.

## Components

| File | Origin | SHA-256 | Where on the unit |
|---|---|---|---|
| `ipod-drvr-iap2.so` (743,272 B) | Tomasz's patch chain on **our** driver (`76926bde…`, 743,196 B, shipped in v1.0-v1.3) + our log gate (`rg/driver/`) | `519ea3c5…` | `/mnt/app/armle/lib/dll/` |
| `iap2.cfg` (6,079 B) | **our** factory one + his `[ident]` | `c61407d9…b491` | `/mnt/system/etc/mm/` |
| `rgi-observer` (13,552 B) | our reader `pmcp-r1` (`rg/reader/reader.c`, derived from his `release/reader.c`), prebuilt in `rg/reader/prebuilt/` | `3166df9b…` | `/mnt/app/carplaymaps/rg/` |
| `pmcp-guidance.jar` (47,817 B) | `pmcp-rg.jar` of `rg/build.sh … lanes-uturn-asf-m`: his `PatchLive` on **our** NavSD classes + his helpers and features, our edits, then our `patcher/GuardLive.java` (every `LiveBridge` call guarded) | `13ca11c4…` | `/mnt/app/eso/hmi/lsd/jars/` |

Up to v1.3 the reader was Tomasz's prebuilt `rgi-observer` (16,606 B, `b683cef7…`) and the JAR was `pmcp-rg.jar`
(`717fb53c…`, no lanes) or `pmcp-rglu.jar` (`72ab7221…`, lanes + U-turn lanes). Without a mode `rg/build.sh` still gives
the base `717fb53c` byte for byte.

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
5. **Reader** (Tomasz's binary, v1.0-v1.3): imports only `libc.so.3`. All 43 strong imports are in the K4525 libc (`485e2a50…`, taken from `mifs-stage1` K4525).
   The 3 weak ones (`_Jv_RegisterClasses`, `__register_frame_info`, `__deregister_frame_info`) are compiler startup code.
   We do not have the MU1161 libc (backup without stage1); it ran on the unit from v1.0 on.

## Installation (GEM buttons)

Button 3 on the main screen does all of this. Single steps in `pmcp_advanced` → `pmcp_packages`:

1. "Route guidance system on (iAP2 driver, iap2.cfg, reader)": saves the factory driver and cfg in `carplaymaps/rollback/`
   (hash), replaces the driver and cfg (remount `/mnt/app` and `/mnt/system`), installs the reader, and finally the marker
   `rg/SYSTEM_ON`. Does not touch the HMI; worst case: a problem with CarPlay/iPod, which "Route guidance system off
   (factory iAP2 driver and iap2.cfg)" or "Remove everything (back to factory files)" undoes.
2. "On rg: route guidance: arrows, lanes, distance bar, street, ETA (needs Route guidance system)": the JAR through the
   Java mechanism with a trial start.
3. Updating from an earlier card: "Route guidance system update (driver and reader of this card, RG stays on)" replaces
   only the v1.0-v1.3 driver `76926bde…` and Tomasz's reader `b683cef7…` (staged and hashed, factory copies kept;
   "Status" shows "Route guidance system: old" before). "Java update: packages of an earlier card -> this card's
   (rglu -> rg)" makes one new set in which `rg`, `rglu` or an experimental variant becomes this `rg` (new JAR file name,
   so the old set stays intact until `HMI_BOOT` switches; one trial start, then "4. Confirm").
4. The reader starts in the background from our `lsd.sh` block, only when `SYSTEM_ON` is present and the Java set loads
   (with Tomasz's arguments: `start-live /dev/ipod0/rgi-events /ramdisk/carplay-route-guidance`).

## Differences from Tomasz and things to do

- Time format: Tomasz sends the time to destination. Here the cluster shows the arrival time (photo `IMG_1083`).
  To do: respect `timeInfoType` (audit A9).
- His installer accepts only MU1427. Ours is our own (pmcp), with hashes instead of sizes alone.
- His reader stops for good when the driver read hangs; ours does not (reader `pmcp-r1` below).
- Speed limit: iAP2 route guidance carries no numeric speed limit (research by
  [maxim-smirnov/mhi2-carplay-cluster](https://github.com/maxim-smirnov/mhi2-carplay-cluster) on iOS 26.6/27), so there
  is nothing to pass to the VW cluster.

## Native VW lane guidance with U-turn lanes (since v1.3.0)

Port of Tomasz's lane guidance from MU1367 v1.4.0 (`upstream/tomasz` @ `7925a83`, works in his car). The files `rg/lanes/stage.py`,
`LaneData.java` and `TestLanes.java` are copied unchanged and pinned by hash. `apply_lanes.py` runs his `stage.guidance()`
on the same pinned bridge sources as the base; the bridge sources at `7925a83` are byte for byte the same as at `024dd159`.

- Data: iAP2 RouteGuidanceLaneGuidanceInformation `0x5204` (already in our `iap2.cfg` and reader).
- To the AID through the factory `LaneGuidance.computeFullLaneGuidanceList`: two `getLaneGuidance` calls -> `laneIterator`,
  `getRouteGuidanceState` -> `descriptorRouteState`, `isSetupLaneGuidanceActive` -> `lanesVisible` (the patcher checks 2/1/1;
  our class has the same layout). Factory window of 6 lanes, the "lane guidance" setting in the VW menu keeps working.
- `GuardLive ... lanes`: 6 guarded calls in `LaneGuidance`; on a helper error `laneIterator` and `lanesVisible`
  fall back to the factory `getLaneGuidance()` / `isSetupLaneGuidanceActive()`.
- U-turn lanes: Tomasz's lane table has no U-turn arrow. `rg/lanes/uturn.py` (on the staged copies, his files stay unchanged)
  maps a U-turn lane to the VW lane symbols 114 (left) and 146 (right) and adds the matching cases to `TestLanes`.
  Checked in the car (MU1161 + AID 791, 2026-10-31): the U-turn lane shows with its own arrow.
- Lanes show only when the phone app sends them and lane guidance is enabled in the VW.

## Distance bar, street name and feed recovery (v1.4)

Three features of tomasz-twardzicki's MU1367 v1.4.3 (`upstream/tomasz` @ `1d69473`, `MU1367/integration/src/guidance`), put
by `rg/lanes/asf.py` as counted edits onto our lanes + U-turn sources:
- **a**: the native VW distance bar (bargraph) before a manoeuvre (`ArrowProgress`): 200 m window, 2000 m for motorway exits
  (iAP2 types 8/22/23), only for the factory `verifiedBapBargraphSetting` mains.
- **s**: the current street in the VW turn-to field (`RoadName`, a 7th patched NavSD class `TurnToInfo`, guarded like the
  others: on an error the factory text).
- **f**: `FeedRecovery`: a mailbox read error no longer stops guidance until the next start; retry after 1 s from a fresh
  baseline, first failure in `failure-first.txt` (max. 768 B).
- Not taken from v1.4.3: placeholder arrow, new lane encoding, LaneEvidence, ownership diagnostics.
- Tests: his TestArrow / TestRoad / TestRecovery (copied unchanged, pinned), besides TestLive and TestLanes.

## Maneuver fallbacks (v1.4)

`rg/lanes/maneuvers.py`. Tomasz's `LiveModel.map()` shows no arrow when iOS leaves out a field (exit angle, junction type,
driving side); the most visible case is the start of a route (type 11 without an angle), where the first arrow appeared
only at the second maneuver. Everything the strict map already maps stays exactly the same; only its "no arrow" results
(main 0) are filled from harman-f/mhi2_altscreen_carplay `MibrRgiManeuvers.java` (git `c01bbdc`, Skoda MU1440, same VW
BAP main elements, GPL-3.0): start of route / ferry exit without angle -> straight, turns without junction type -> the
type's own direction, missing driving side -> right-hand traffic, ramps without angle -> slight to the traffic side
(right-hand traffic assumed when the side is missing: the car drives in Poland). A turn type at a roundabout (junction 1)
becomes the roundabout symbol with that exit direction instead of a plain turn. Highway change (51) and roundabout exits
28-46 without an angle stay empty (no guessing). The distance bar also shows on these fallback arrows. Test:
`TestManeuvers` (every type x junction x side x angle sample: strict results unchanged, only VW mains in use; fallbacks;
end-to-end start of route). Tomasz's `TestLive vectors` harness compares against his strict mapping and is expected to
differ on this JAR. The GEM button "RG last maneuver" shows the strict mapping; where it says main 0 the `rg` package may
still show a fallback arrow.

## iAP2 driver log gate (v1.4, `rg/driver/`)

Tomasz's B2 hook logs every received route guidance message byte by byte to `/dev/shmem/iap2.log`, on the iAP2 receive
thread, always. `rg/driver/log-gate.S` (76 bytes, assembled bytes committed as `rg/driver/log-gate.bin`, pinned) is
appended to the injected segment by `patch-log-gate.py`, which moves one branch: the log now runs only when the file
`/dev/shmem/pmcp-rgi-debug` exists (default off). Every other byte of the driver stays identical (checked). Result
`519ea3c5…` (743,272 B). No Docker or QNX toolchain is needed; `PMCP_GATE_REBUILD=1` reassembles the bytes in Docker
(`rg/driver/build-gate.sh`) and must give the same bytes.

## Reader `pmcp-r1` (v1.4, `rg/reader/`)

Tomasz's prebuilt reader (`b683cef7…`) ended for good 1.5 s after the driver read stopped delivering data, so guidance
stayed dead until the next unit start. `rg/reader/reader.c` (GPL, derived from his `reader.c`; worker, snapshot
validation and the RGM1 mailbox format unchanged) adds a supervisor: when the worker's read hangs it writes one
"invalid" record after 1 s, kills the worker after 10 s and starts a new one with a growing delay, and never exits for
good. A file lock (`reader.lock`) keeps a second reader off the same directory. The binary is committed as
`rg/reader/prebuilt/rgi-observer` (`3166df9b…`, 13,552 B); `rg/reader/build.sh` rebuilds it in Docker (optional).

