# Changelog

All releases are for one combination only: VW Passat B8 (MY2018), Discover Pro MHI2 **MU1161**, train
`MHI2_ER_VWG13_P4512`, AID part 791. Installer versions are `pmcp-<x.y.z>-mu1161-791-<build id>`.

## v1.4.0 "rg-main" (2026-11)

One route guidance package with everything that works in the car, a more robust route guidance reader and iAP2
driver, and the whole installer in English. Updating from v1.0–v1.3 needs only button 3 and one Confirm.

### Route guidance

- **One Java package `rg`** replaces `rg` and `rglu`. It carries:
  - the native VW arrow, distance to the manoeuvre, distance and time to destination (tomasz-twardzicki's MU1427 v1.2.0
    port);
  - native VW lane guidance (Tomasz's MU1367 v1.4.0) with VW U-turn lane symbols 114/146 (`rg/lanes/uturn.py`);
  - the native **distance bar** before the manoeuvre, the **current street name**, and faster recovery of the feed after
    a read error (Tomasz's MU1367 v1.4.3, `rg/lanes/asf.py`);
  - **maneuver fallbacks** (`rg/lanes/maneuvers.py`). They apply only where Tomasz's strict mapping gives no arrow
    because iOS left a field out:
    - an arrow right at the **start of the route**;
    - **roundabout turns** (the roundabout symbol with the exit direction);
    - U-turns, ramps and destination left/right without an angle.

    The table comes from harman-f's MibrRgiManeuvers (Skoda MU1440, same VW BAP elements). Exits 28–46 without an angle
    get no arrow; the exit number is not guessed. The full rule table is at the top of
    [`rg/lanes/maneuvers.py`](rg/lanes/maneuvers.py); host test `TestManeuvers` (48,826 checks; every arrow it
    gives is one the strict mapping can also give).
  - Car-tested 2026-11-04: start arrow, street name and distance bar.
- **Reader `rgi-observer` pmcp-r1** (`rg/reader/reader.c`, derived from Tomasz's `release/reader.c`). The old reader ended
  for good when the iAP2 driver did not answer for 1.5 s, and the arrows were then gone until the next unit start. Now:
  - after 1 s without data the supervisor writes one "invalid" record, so no stale arrow stays on screen;
  - after 10 s it kills the stuck worker and starts a new one with a growing delay;
  - it never ends by itself;
  - a file lock keeps a second reader out;
  - `status.txt` counts restarts, timeouts and kills.

  A prebuilt binary is in the repository (`rg/reader/prebuilt/`, sha256 `3166df9b…`), so `install.sh` still needs no
  Docker; `rg/reader/build.sh` rebuilds it with the QNX 6.5 toolchain. Host test: `rg/reader/test_reader.py`.
- **iAP2 driver with a log gate** (`rg/driver/`, sha256 `519ea3c5…`). Tomasz's driver patch logs every route guidance
  message byte by byte into `/dev/shmem/iap2.log`. That log now runs only while `/dev/shmem/pmcp-rgi-debug` exists; it
  is off by default. The 76 bytes of the gate are in the repository (`rg/driver/log-gate.bin`, built from
  `log-gate.S`). The patch checks every word it changes. Emulation test: `rg/driver/test_log_gate.py`.

### Installer

- **Everything in English:**
  - GEM labels and screen names: `pmcp_advanced`, `pmcp_other_layouts`, `pmcp_switch_layout`, `pmcp_packages`;
  - the package buttons start with the package name (`On rg: …`);
  - status messages and the rescue card.
- **Button 3 updates earlier installs.** It runs, in order:
  1. `rg-update`: the v1.0–v1.3 driver and reader are replaced in place, the factory copies are kept;
  2. `java-update`: `rg`/`rglu` of v1.2–v1.3 and the experimental `rglua`, `rgluasf`, `rgluasfa`, `rgluasfm`,
     `rgluasfma` become `rg`;
  3. the main map;
  4. the route guidance system;
  5. every package.

  It gives one new Java set, one trial start and one Confirm. Earlier files are recognised by SHA-256 and size only;
  anything else stays `PARTIAL` or `UNKNOWN` and is not touched. The new `rg` JAR has a file name no earlier card used,
  so an interrupted update never leaves an unconfirmed JAR under a confirmed set.
- New status values:
  - `Route guidance system: old`: an earlier card's driver or reader;
  - `packages of an earlier card: …`.
- **Android Auto from the experimental branch is not part of this release, but this card can always take it off**
  (`aa-remove`: "Remove experimental Android Auto", also the first step of button 3 and of "Remove everything"):
  - it writes only on a pmcp install and only from a factory `gal` copy with the factory hash;
  - running it again finishes an interrupted run.

  Until it is off, every other action reports `UNKNOWN` and changes nothing.
- **Rescue card in English:**
  - renamed files: `pmcp-rescue/pmcp-rescue.sh`, `PMCP_RESCUE_README.txt`, `PMCP_RESCUE_LOG.txt`;
  - log results `RESULT=OK` / `RESULT=UNSURE`;
  - it restores both driver sizes, 743196 (v1.0–v1.3) and 743272 (v1.4);
  - a rescue card made before v1.4 does not restore the v1.4 driver, so make a new one.

  The copy helpers read both log names.
- `RG last maneuver` notes that it shows the strict mapping; the `rg` package may still draw a fallback arrow there.
- Tests:
  - `run_tests.sh`: the real v1.3.0 card and the last experimental card run against the simulated unit (v1.3.0 → v1.4
    with button 3, rgluasfm → rg, experimental Android Auto taken off by aa-remove / button 3 / restore, a bad factory
    `gal` copy refused, a modified old JAR not trusted, an interrupted `java-update` finished by running it again, exact
    factory tree after every restore);
  - `fault_inject.sh`: the power-loss chain starts from a v1.3.0 install and goes through `rg-update`, `java-update`,
    and `aa-remove` and `restore` on a unit with experimental Android Auto; Android Auto is never left without a
    factory `gal`.
- JAR files of ours that the boot list does not name (left by an interrupted update) are never loaded. Status lists
  them, and `java-update` and `restore` remove them.

### Not in this release

- Speed limit from the phone as a number: the iAP2 route guidance messages carry none, according to maxim-smirnov's
  research on iOS 26.6 and 27. `showSpeedLimit=yes` (variant `url-map-hybrid`) only asks the phone to draw a sign in the
  video, and none was seen on this unit.
- Android Auto, AID fast start and cluster day/night experiments stay on branch `experimental`.

### Credits for this release

- **tomasz-twardzicki** (MHI2-Carplay-Maps, GPL-3.0), for:
  - the route guidance this package is built on: the MU1427 port and its strict iAP2 → VW maneuver mapping
    (`LiveModel.map`);
  - lane guidance (MU1367 v1.4.0);
  - the distance bar, street name and feed recovery (MU1367 v1.4.3);
  - the reader that pmcp-r1 is derived from;
  - the iAP2 driver patch.

  His v1.4.2 took our U-turn lane symbols back upstream.
- **harman-f** (mhi2_altscreen_carplay, GPL-3.0, `MibrRgiManeuvers.java` @ `c01bbdc`): the maneuver table behind the
  fallbacks.
- **luka-dev**: iAP2 route guidance decoding and maneuver type names.
- **maxim-smirnov** (mhi2-carplay-cluster): speed-limit research.

## v1.3.0 (2026-10-31)

- Route guidance with native VW lane guidance and U-turn lanes (package `rglu`: Tomasz's MU1367 lanes plus VW lane symbols
  114/146), confirmed in the car.
- Main map `map-square-fps40` (map-square at 40 fps, as mathsls).
- Button 3 "Install all features or update" brings an earlier install to the card's set with one trial start and one
  Confirm.
- Read-only buttons: start timeline, RG last maneuver, navigation diagnostics.
- Docs: AID fast start audit (nothing of it shipped).

## v1.2.0 (2026-10-27)

- One visit to the car: 1. Check → 2. Install map → restart → 3. Install all features → restart (trial) → 4. Confirm.
- Features are no longer locked behind the rescue card; the trial start and the rescue card remain.
- Copy helper option 3 re-arms the rescue card and shows the result of its last run.

## v1.1.0 (2026-10-27)

- Simplified main GEM screen; single packages and map layouts under `pmcp_advanced`.
- "Install all features": every package in one set, one trial start, one Confirm.

## v1.0.0 (2026-10-27)

- Ready-made SD cards (install card and rescue card), copy helpers for Windows and macOS, `make_release.py`.
- `install.sh` builds both cards from your own M.I.B. backup.
- `map-square` as the default layout.

## Initial version (2026-10-24)

- Installer, `core.so` layout variants, NavActiveIgnore, native route guidance port, now playing, steering-wheel zoom
  and day/night for MU1161 + AID 791. Builds on omonob, M.I.B., tomasz-twardzicki and mathsls (see README).
