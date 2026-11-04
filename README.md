# mhi2-aid-carplay

CarPlay map and native route guidance on the Active Info Display (AID, virtual cockpit) of a **VW Passat B8 (MY2018)**
with a **Discover Pro MHI2** head unit: **MU1161**, train `MHI2_ER_VWG13_P4512`, AID part 791.

[Polska wersja: README.pl.md](README.pl.md)

![CarPlay map with native VW guidance on the AID](docs/img/aid-carplay-2026-10/IMG_1127.jpg)

This repository holds only what is specific to this head unit. It builds on the work of the projects listed under
[Credits](#credits). The general MHI2 CarPlay-on-cluster work lives there.

> **Warning.** This modifies the infotainment of a car. It has been run on exactly one car: MU1161 + AID 791, firmware
> P4512. Every installer step checks file hashes and stops on any mismatch, but you use this at your own risk. Never
> cross-flash firmware to make it fit. Not affiliated with Volkswagen, Harman or Apple.

## What works (tested in the car, October 2026)

| Feature | Status |
|---|---|
| CarPlay map video on the AID (Apple Maps, Google Maps), big and small dial layouts | works |
| NavActiveIgnore: the head unit no longer stops or blocks phone navigation | works |
| Native VW guidance from the iPhone: distance and time to destination on the VW bar and in the left dial | works |
| Native turn arrow and distance to the manoeuvre (appears once the car moves) | works |
| Native VW lane guidance, including U-turn lanes (when the phone app sends lanes) | works |
| Map zoom with the steering-wheel arrows | works |
| CarPlay track title and artist on the AID | works |
| Day/night switching of the cluster map | works |
| Speed limit from the phone (`showSpeedLimit=yes`) | shows nothing on this unit |
| Optional native VW map speed limit in navigation text during CarPlay guidance | 50 → 70 km/h update confirmed on an e-Golf AID 795A. [Details](docs/en/16-native-speed-limits.md) |

![Map without active navigation](docs/img/aid-carplay-2026-10/IMG_1102.jpg)

More photos and an interactive model of the AID frame (where the video lands on the panel for each variant):
[`docs/aid-frame-map.html`](docs/aid-frame-map.html), photos in [`docs/img/`](docs/img/).

## Components

| Directory | What it builds | Lands on the unit |
|---|---|---|
| [`patches/mu1161/`](patches/mu1161/) | `core.so` variants of the CarPlay cluster stream (safe area, URL, frame rate, key frames, physical size) from one hash-pinned base | `core.so` |
| [`navactiveignore/`](navactiveignore/) | NavActiveIgnore built from the unit's own HMI classes | Java (HMI) |
| [`rg/`](rg/) | Native route guidance: port of tomasz-twardzicki's MU1427 solution to MU1161 (iAP2 RouteGuidance → BAP) | Java, iAP2 driver, `iap2.cfg`, reader |
| [`nowplaying/`](nowplaying/) | CarPlay track title and artist on the cluster | Java (HMI) |
| [`hmiextras/`](hmiextras/) | Steering-wheel zoom and day/night resend for the cluster map | Java (HMI) |
| [`speedlimit/`](speedlimit/) | Optional native VW map speed limit in the cluster's navigation text | Java (HMI), saved opt-in setting |
| [`installer/`](installer/) | SD-card installer run from the M.I.B. GEM menu, the rescue card, host tests | nothing by itself |
| [`buildtools/`](buildtools/) | Host checks: try/catch guard around every hook call, J9 CDC API check | nothing |
| [`scripts/`](scripts/) | Read-only firmware readers (QNX6, IFS, LZOZ, JXE → JAR), SD-card tester | nothing |
| [`firmware/`](firmware/) | Hashes and notes for the official K4525 update (the only allowed firmware) | nothing |

### Map layout variants (GEM → `pmcp_zmien_wariant`)

The stream is 800×480 and lies 1:1 on the AID panel. Safe area values are x / y / width / height.

| Variant | URL | Safe area | Notes |
|---|---|---|---|
| `map-clean` | `maps:/car/instrumentcluster/map` | 200 / 108 / 400 / 296 | map only, VW shows guidance natively |
| `card-clean` | `maps:/car/instrumentcluster` | 200 / 108 / 400 / 296 | with the iPhone's manoeuvre card |
| `url-map-hybrid` | `…/map?showSpeedLimit=yes` | 200 / 108 / 400 / 296 | speed-limit parameter (no effect seen) |
| `map-clean-l40` | `maps:/car/instrumentcluster/map` | 160 / 108 / 400 / 296 | 40 columns to the left |
| `map-square` | `maps:/car/instrumentcluster/map` | 240 / 60 / 320 / 340 | mathsls's MU1161 layout, closer to square; best after a longer drive; 30 fps |
| `map-square-fps40` (default) | `maps:/car/instrumentcluster/map` | 240 / 60 / 320 / 340 | `map-square` at 40 fps (as mathsls); no more lag than 30 fps in a test drive |

All variants declare a physical size of 240×144 mm. Switching a variant swaps one file (`core.so`) and needs a restart.

## Download and install

**[Download the latest release](https://github.com/chrzanowy/mhi2-aid-carplay/releases/latest)**: the file
`mhi2-aid-carplay-cards-<build id>.zip`. It holds both SD cards ready to use. No programs to install, Windows or Mac.

1. Unpack the zip and open `README-FIRST.txt`. It walks you through everything in plain English.
2. Double-click `Copy-to-SD-Windows.bat` (Windows) or `Copy-to-SD-macOS.command` (Mac). It copies a card onto an
   **empty** FAT32 SD card, checks every file and ejects the card. It never formats a card or deletes anything.
   Make card 1 (install) and card 2 (rescue, for emergencies).
3. In the car, one visit, card 1 only (part 2 of `README-FIRST.txt`, details: [in-car guide](docs/en/09-in-car-guide.md)):
   **1. Check → 2. Install map → restart → map OK? → 3. Install all features → restart (trial start) → test →
   4. Confirm → restart.** It works like this from then on.
   Card 2 is only for an emergency after Confirm. After use it disarms itself; the copy helper's option 3 re-arms it.

Before you start you need [M.I.B. installed on the unit and a backup](docs/en/01-mib-install-backup.md). The installer
on the card checks every file of your head unit first. On any other firmware it stops and changes nothing.

Check the download against `SHA256SUMS.txt` from the same release if you want to be sure it is complete.

## Enable or disable native speed-limit text in the Green Menu

Choose **Path 1** for a fresh installation of this project's CarPlay package. Choose **Path 2** to update an existing
installation, including one that already has the speed-limit reader.

Both paths require M.I.B. installed, a backup and an install card containing this feature's `sl` package and menu entries.
Park, leave the ignition on and use **SD1**. Wait for each action's result before selecting **Back** or removing the card.
The optional speed-limit reader is installed separately for both first-time users and updaters.

**MENU** opens the Green Menu when held for about 10 seconds. A reboot means holding the **volume knob for about
10 seconds** until the head unit restarts. In results such as `This boot: set=... use=trial`, the set ID represented by
`...` varies with the installed packages.

### Path 1 — First-time installation

This path covers a fresh CarPlay installation followed by installation and activation of the speed-limit reader.

#### Install the CarPlay map and guidance

1. Insert the new install card in **SD1**. Hold **MENU for about 10 seconds**.
2. Select `=>M.I.B.<=`, then select `pmcp_CarPlay_AID`.
3. Select **1. Check card and unit (read-only)**. Expect `PMCP_VERIFY_OK state=STOCK`.
   A fresh installation starts from `STOCK`. For `VIDEO` or `JAVA`, use **Path 2**.
   For `PARTIAL` or `UNKNOWN`, pause here and retain the result for troubleshooting.
4. Select **Back** to return to `pmcp_CarPlay_AID`. Select **2. Install the CarPlay map on the AID**.
   Wait for `PMCP_INSTALL_OK stage=A variant=map-square-fps40` followed by the build version.
5. Hold the **volume knob for about 10 seconds** to reboot. Connect the iPhone through CarPlay, start navigation
   and select the AID's navigation/map view. Check that the CarPlay map appears on the cluster.
6. Hold **MENU for about 10 seconds**. Select `=>M.I.B.<=`, then `pmcp_CarPlay_AID`.
   Select **3. Install all features or update: main map, arrows, lanes, ETA, zoom, song title**.
   Wait until the final result is `PMCP_ALL_ON_OK` and the screen asks for a restart.
7. Hold the **volume knob for about 10 seconds** to reboot into the Java trial.
   Check the head unit menus, audio, CarPlay connection, cluster map and navigation guidance.
8. During this same boot, hold **MENU for about 10 seconds**. Select `=>M.I.B.<=`, then `pmcp_CarPlay_AID`.
   Select **Status (read-only)**. Expect `Unit state: JAVA`, `This boot: set=... use=trial` and `PMCP_STATUS_OK`.
9. Select **Back** to return to `pmcp_CarPlay_AID`.
   Select **4. Confirm: everything works (only in the first start after 3)**. Wait for `PMCP_JAVA_CONFIRM_OK`.
10. Hold the **volume knob for about 10 seconds** to reboot again.
    Hold **MENU for about 10 seconds**, select `=>M.I.B.<=`, then `pmcp_CarPlay_AID`, then **Status (read-only)**.
    Expect `Unit state: JAVA`, `This boot: set=... use=yes` and `PMCP_STATUS_OK`.

#### Install and enable the speed-limit reader

1. Select **Back** to return to `pmcp_CarPlay_AID`. Select `pmcp_advanced`, then `pmcp_etap_B_java`.
2. Select **Wlacz: Native VW map speed limit in road text (optional, output initially off)**.
   Wait for `PMCP_JAVA_ON_OK package=sl` followed by the new set ID.
3. Hold the **volume knob for about 10 seconds** to reboot into the reader's Java trial.
   Check the menus, audio, CarPlay map and guidance again.
4. During this same boot, hold **MENU for about 10 seconds**. Select `=>M.I.B.<=`, then `pmcp_CarPlay_AID`.
   Select **Status (read-only)**. Expect `Unit state: JAVA`, `This boot: set=... use=trial` and `PMCP_STATUS_OK`.
5. Select **Back** to return to `pmcp_CarPlay_AID`. Select `pmcp_advanced`.
   Select **Native speed limit: saved mode and reader snapshot (read-only)**.
   Expect `Saved native speed-limit mode: off (default)`, a reader snapshot containing
   `schema=pmcp-native-speedlimit-v1`, and `PMCP_SPEEDLIMIT_STATUS_OK`.
6. Select **Back** until the `pmcp_CarPlay_AID` menu is shown.
   Select **4. Confirm: everything works (only in the first start after 3)** during this same trial boot.
   Wait for `PMCP_JAVA_CONFIRM_OK`. This button also confirms the manually added reader.
7. Select **Back** to return to `pmcp_CarPlay_AID`. Select `pmcp_advanced`.
   Select **Native speed limit: enable next-road text after installing and confirming sl**.
   Wait for `PMCP_SPEEDLIMIT_MODE_OK mode=turnto`.
8. Select **Back** to return to `pmcp_advanced`.
   Select **Native speed limit: saved mode and reader snapshot (read-only)**.
   Expect `Saved native speed-limit mode: turnto` and `PMCP_SPEEDLIMIT_STATUS_OK`.
   After the reader's next refresh, its snapshot also shows `output_mode=turnto` and `turnto_enabled=1`.
9. Exit the Green Menu using **Back**, connect CarPlay and start Google Maps guidance.
   Select the AID's navigation/map view. Once VW supplies a valid native limit, expect text such as **Limit 50 km/h**.
10. Hold the **volume knob for about 10 seconds** to reboot and check the saved activation.
    Hold **MENU for about 10 seconds**, select `=>M.I.B.<=`, then `pmcp_CarPlay_AID`, then `pmcp_advanced`.
    Select **Native speed limit: saved mode and reader snapshot (read-only)**.
    Expect `Saved native speed-limit mode: turnto` and `PMCP_SPEEDLIMIT_STATUS_OK`.
    Reconnect CarPlay, start Google Maps guidance and check the cluster text again after a valid native update.

### Path 2 — Update an existing installation

Use this path for an existing installation of this project's CarPlay package. An installed speed-limit reader needs
its original matching card for removal before installing a newer reader. The installer checks exact reader hashes,
so the matching old card is part of the update procedure.

#### Prepare an installed speed-limit reader for update

For a CarPlay installation that has never had the speed-limit reader, begin with **Install the update and reader** below.
For an installed `sl` reader, complete these steps with its matching old card.

1. Insert the old install card in **SD1**. Hold **MENU for about 10 seconds**.
2. Select `=>M.I.B.<=`, then `pmcp_CarPlay_AID`, then `pmcp_advanced`.
3. Select **Native speed limit: disable road text**. Wait for `PMCP_SPEEDLIMIT_MODE_OK mode=off`.
4. Select **Back** to return to `pmcp_advanced`. Select `pmcp_etap_B_java`.
5. Select **Wylacz: Native VW map speed limit in road text (optional, output initially off)**.
   Wait for `PMCP_JAVA_OFF_OK package=sl`.
6. Hold the **volume knob for about 10 seconds** to reboot. Check that the head unit and the existing CarPlay features work.
7. Hold **MENU for about 10 seconds**. Select `=>M.I.B.<=`, then `pmcp_CarPlay_AID`, then **Status (read-only)**.
   Expect `PMCP_STATUS_OK` and read `Unit state: JAVA` or `Unit state: VIDEO`.
   `VIDEO` means removal returned the unit to its map-only installation, ready for the new card.
   For `JAVA`, also read `This boot: set=... use=...`.

   - For `use=yes`, the remaining Java set is already confirmed.
   - For `use=trial`, check normal operation, select **Back**, select
     **4. Confirm: everything works (only in the first start after 3)** and wait for `PMCP_JAVA_CONFIRM_OK`.
     Reboot with the volume knob, reopen **MENU** → `=>M.I.B.<=` → `pmcp_CarPlay_AID` → **Status (read-only)**
     and expect `This boot: set=... use=yes`.
8. Exit the Green Menu using **Back** and replace the old card with the new install card in **SD1**.

For the earlier **R3 trial card**, its controls are under `=>M.I.B.<=` → `pmcp_native_speedlimit`.
Select **7. Disable both limit text tests / restore roads** and wait for `PMCP_SL_TEXT_OFF_OK`.
Then select **8. Remove reader / restore previous Java set** and wait for `PMCP_SL_REMOVE_OK`.
Reboot using the volume knob, check the restored CarPlay installation, then insert the new install card in **SD1**.

#### Install the update and reader

1. Insert the new install card in **SD1**. Hold **MENU for about 10 seconds**.
2. Select `=>M.I.B.<=`, then `pmcp_CarPlay_AID`, then **1. Check card and unit (read-only)**.
   Expect `PMCP_VERIFY_OK state=JAVA` for an existing Java installation or `PMCP_VERIFY_OK state=VIDEO`
   for a map-only installation. For `STOCK`, follow **Path 1**. For `PARTIAL` or `UNKNOWN`, pause here and resolve
   that state with the matching previous card or the recovery procedure before continuing.
3. Select **Back** to return to `pmcp_CarPlay_AID`.
   Select **3. Install all features or update: main map, arrows, lanes, ETA, zoom, song title**.
   Expect either `PMCP_ALL_ON_OK` with a restart instruction, or
   `PMCP_ALL_ON_OK (everything was already on, nothing changed)`.
4. Follow the result shown by **3. Install all features or update**.

   - If the screen shows `PMCP_ALL_ON_OK` and asks for a restart, hold the **volume knob for about 10 seconds**
     to reboot. Check the menus, audio, CarPlay map and guidance. Hold **MENU for about 10 seconds**, select
     `=>M.I.B.<=`, then `pmcp_CarPlay_AID`, then **Status (read-only)**.
   - If the screen shows `PMCP_ALL_ON_OK (everything was already on, nothing changed)`, keep the current boot.
     Select **Back** to return to `pmcp_CarPlay_AID`, then select **Status (read-only)**.
5. On the Status screen, expect `Unit state: JAVA` and `PMCP_STATUS_OK`, then read `This boot: set=... use=...`.

   - For `use=trial`, select **Back**, select **4. Confirm: everything works (only in the first start after 3)**
     during this same boot and wait for `PMCP_JAVA_CONFIRM_OK`.
   - For `use=yes`, the set is already confirmed and ready for the reader installation.
6. Select **Back** until `pmcp_CarPlay_AID` is shown. Select `pmcp_advanced`, then `pmcp_etap_B_java`.
7. Select **Wlacz: Native VW map speed limit in road text (optional, output initially off)**.
   Wait for `PMCP_JAVA_ON_OK package=sl` followed by the set ID.
8. Hold the **volume knob for about 10 seconds** to reboot. Check the menus, audio, CarPlay map and guidance.
9. Hold **MENU for about 10 seconds**. Select `=>M.I.B.<=`, then `pmcp_CarPlay_AID`, then **Status (read-only)**.
   Expect `Unit state: JAVA` and `PMCP_STATUS_OK`, then read `This boot: set=... use=...`.

   - For `use=trial`, select **Back**, select **4. Confirm: everything works (only in the first start after 3)**
     during this same boot and wait for `PMCP_JAVA_CONFIRM_OK`.
   - For `use=yes`, this exact set was confirmed previously and is ready to enable.
10. Select **Back** until `pmcp_CarPlay_AID` is shown. Select `pmcp_advanced`.
    Select **Native speed limit: saved mode and reader snapshot (read-only)**.
    Expect `Saved native speed-limit mode: off (default)`, a reader snapshot containing
    `schema=pmcp-native-speedlimit-v1`, and `PMCP_SPEEDLIMIT_STATUS_OK`.
11. Select **Back** to return to `pmcp_advanced`.
    Select **Native speed limit: enable next-road text after installing and confirming sl**.
    Wait for `PMCP_SPEEDLIMIT_MODE_OK mode=turnto`.
12. Select **Back** to return to `pmcp_advanced`.
    Select **Native speed limit: saved mode and reader snapshot (read-only)**.
    Expect `Saved native speed-limit mode: turnto` and `PMCP_SPEEDLIMIT_STATUS_OK`.
    After the reader's next refresh, its snapshot also shows `output_mode=turnto` and `turnto_enabled=1`.
13. Exit the Green Menu using **Back**, connect CarPlay and start Google Maps guidance.
    Select the AID's navigation/map view. After a valid native update, expect text such as **Limit 50 km/h**.
14. Hold the **volume knob for about 10 seconds** to reboot and check the saved activation.
    Hold **MENU for about 10 seconds**, select `=>M.I.B.<=`, then `pmcp_CarPlay_AID`, then `pmcp_advanced`.
    Select **Native speed limit: saved mode and reader snapshot (read-only)**.
    Expect `Saved native speed-limit mode: turnto` and `PMCP_SPEEDLIMIT_STATUS_OK`.
    Reconnect CarPlay, start Google Maps guidance and check the cluster text after a valid native update.

#### Confirmation and retry results

`This boot: set=... use=trial` requires confirmation during that boot after the operation checks pass.
`This boot: set=... use=yes` means the exact set is already confirmed. Pressing Confirm for that set reports
`PMCP_FAIL=SET_ALREADY_CONFIRMED_...`; the set remains confirmed and can proceed to activation.

For a missed confirmation followed by `This boot: set=... use=no`, use this sequence.

1. Hold **MENU for about 10 seconds**. Select `=>M.I.B.<=`, then `pmcp_CarPlay_AID`.
2. Select **5. Try again: the next start is a new trial**. Wait for `PMCP_JAVA_RETRY_OK`.
3. Hold the **volume knob for about 10 seconds** to reboot. Check the menus, audio, CarPlay map and guidance.
4. Hold **MENU for about 10 seconds**. Select `=>M.I.B.<=`, then `pmcp_CarPlay_AID`, then **Status (read-only)**.
   Expect `This boot: set=... use=trial` and `PMCP_STATUS_OK`.
5. Select **Back** and select **4. Confirm: everything works (only in the first start after 3)** during this same boot.
   Wait for `PMCP_JAVA_CONFIRM_OK`.

Resume the installation phase that required this confirmation. A base CarPlay set proceeds to reader installation.
An installed and confirmed `sl` reader can use the complete **Enable it again after disabling** procedure below.

### Disable the speed-limit text

1. Hold **MENU for about 10 seconds**, then open `=>M.I.B.<=` → `pmcp_CarPlay_AID` → `pmcp_advanced`.
2. Select **Native speed limit: disable road text**. Wait for `PMCP_SPEEDLIMIT_MODE_OK mode=off`.
3. Select **Back** to return to `pmcp_advanced`.
   Select **Native speed limit: saved mode and reader snapshot (read-only)**.
   Expect `Saved native speed-limit mode: off` and `PMCP_SPEEDLIMIT_STATUS_OK`.
4. Exit the Green Menu using **Back**. The reader restores the original street text on its next refresh,
   normally within about one second. The off selection is saved across reboots.

### Enable it again after disabling

1. Insert the current matching install card in **SD1**. Hold **MENU for about 10 seconds**.
   Select `=>M.I.B.<=`, then `pmcp_CarPlay_AID`, then `pmcp_advanced`.
2. Select **Native speed limit: enable next-road text after installing and confirming sl** and wait for
   `PMCP_SPEEDLIMIT_MODE_OK mode=turnto`.
3. Select **Back** to return to `pmcp_advanced`.
   Select **Native speed limit: saved mode and reader snapshot (read-only)**.
   Expect `Saved native speed-limit mode: turnto` and `PMCP_SPEEDLIMIT_STATUS_OK`.
4. Exit the Green Menu using **Back**, connect CarPlay, start Google Maps guidance and select the AID navigation/map view.
   The reader applies the saved selection on its next refresh and shows the limit after a valid native update.

The native limit source, display behavior and package removal procedure are described in the
[native speed-limit guide](docs/en/16-native-speed-limits.md).

## Build the cards yourself (advanced)

Instead of the ready-made cards, you can build them from your own unit's M.I.B. backup (macOS; Linux works for
building). The result is byte-identical to the release.

```sh
mkdir ~/mhi2-workspace && cd ~/mhi2-workspace
git clone https://github.com/chrzanowy/mhi2-aid-carplay.git
cd mhi2-aid-carplay
./install.sh                # or double-click Install-macOS.command in Finder
```

`install.sh` goes through 11 numbered steps. Each one says what it does and why, and shows every command it runs:
it checks your computer and your backup (train `MHI2_ER_VWG13_P4512` / MU1161, every file by SHA-256), downloads the
pinned sources, builds and tests everything (including power loss at every write step), builds the two card folders
and can write them to SD cards. On any mismatch it stops and says what to do. The full log is in
`logs/install-<date>.log`. `python3 -I release/make_release.py build dist` then packs the release zip.

## Installer

The installer runs from the GEM (engineering) menu of [M.I.B.](https://github.com/Mr-MIBonk/M.I.B._More-Incredible-Bash)
on an SD card. Design rules:

- **Fail-closed.** Every file on the unit and on the card is checked by exact hash and size before anything is
  written. Unknown state means no change.
- Files are staged, verified and swapped in, and the stock files are backed up first. "Restore factory files" is
  always available.
- **Java packages use a trial boot.** After "Wlacz" (enable) and a restart, the change must be confirmed ("Potwierdz")
  in the same boot. Otherwise the next boot is stock again.
- A separate **rescue card** (`installer/build_rescue.py`) autostarts in update mode and restores the stock HMI
  without needing GEM.
- Host tests (`installer/test/run_tests.sh`, `fault_inject.sh`) run the installer against a copy of the unit's file
  tree under `mksh` and `ksh`. They include power loss at every write step.

Step-by-step guide for the car: [`docs/en/09-in-car-guide.md`](docs/en/09-in-car-guide.md).
Installer design: [`docs/en/07-installer.md`](docs/en/07-installer.md).

## Building

This repository (the source) ships **no binaries** and nothing from Volkswagen firmware. Every build reads its inputs from a
workspace next to this repository and checks each input by SHA-256:

```
workspace/
  mhi2-aid-carplay/        this repository
  upstream/                clones of the projects below, at the pinned commits
  backup/MU1161/           M.I.B. backup of your unit (or set PMCP_BACKUP)
  archives/                M.I.B. 3.6.0 GEM menu, converted lsd.jar of your unit
```

| Input | Source | Pinned |
|---|---|---|
| base `core.so` (MU1102/791 profile, sha256 `00b48a8f…`) | omonob payload as shipped in M.I.B. | commit `3a2526a3` |
| route guidance, patch sites | tomasz-twardzicki/MHI2-Carplay-Maps | commit `024dd159` |
| MU1161/791 reference payload | mathsls/MHI2-Carplay-Maps | commit `cdd576b0` |
| JXE → JAR converter | luka-dev/jxe2jar | commit `9eeb45bb` |
| GEM menu (`Launcher-sda0.esd`) | M.I.B. 3.6.0 release zip | sha256 `4bfc6e72…` |
| HMI classes, iAP2 driver | your own unit (M.I.B. backup) | sha256 per file |
| host tools | ASM 9.7 (Java builds), pyelftools 0.31 in `upstream/tools/venv-elftools` (`rg/`), gawk 3.1.5 in `upstream/tools/` (tests) | ASM jars by sha256 |

Build order: `navactiveignore/`, `nowplaying/`, `hmiextras/`, `rg/` (`build.sh` in each; needs JDK 11+ and ASM 9.7 in
`$ASM_DIR`), then `patches/mu1161/build_core.py`, `installer/build_sd.py`, `installer/build_card_install.py` and
`installer/build_rescue.py`. Run Python with `python3 -I`. If any input differs from the pinned hash, the build stops.

## Documentation

English in [`docs/en/`](docs/en/), Polish in [`docs/pl/`](docs/pl/):

| Topic | English | Polish |
|---|---|---|
| Installing M.I.B. and backing up the unit (do this first) | [01-mib-install-backup](docs/en/01-mib-install-backup.md) | [01-mib-instalacja-backup](docs/pl/01-mib-instalacja-backup.md) |
| HMI analysis: map stream, AID size detection, CarPlay and guidance classes | [04-lsd-jxe-decompilation](docs/en/04-lsd-jxe-decompilation.md) | [04-lsd-jxe-dekompilacja](docs/pl/04-lsd-jxe-dekompilacja.md) |
| Installer design | [07-installer](docs/en/07-installer.md) | [07-instalator](docs/pl/07-instalator.md) |
| Audit: AID fast start (tried, failed, why the AID needed a bus sleep) | [14-fast-start-audit](docs/en/14-fast-start-audit.md) | [14-audyt-szybki-start](docs/pl/14-audyt-szybki-start.md) |
| Step-by-step guide in the car | [09-in-car-guide](docs/en/09-in-car-guide.md) | [09-tutorial-w-aucie](docs/pl/09-tutorial-w-aucie.md) |
| Interactive AID frame model | [aid-frame-map.html](docs/aid-frame-map.html) | [aid-frame-map.pl.html](docs/aid-frame-map.pl.html) |

The component directories have an English `README.md` and a Polish `README.pl.md`.

## Credits

This project would not exist without:

- **[omonob/MHI2-Carplay-Maps](https://github.com/omonob/MHI2-Carplay-Maps)**: the original CarPlay map on the MHI2
  virtual cockpit. Its `core.so` (MU1102/791 profile) is the base that every variant here patches.
- **[Mr-MIBonk/M.I.B.](https://github.com/Mr-MIBonk/M.I.B._More-Incredible-Bash)**: the GEM toolbox the installer runs
  from, the unit backup, and the distribution of the omonob payload.
- **[tomasz-twardzicki/MHI2-Carplay-Maps](https://github.com/tomasz-twardzicki/MHI2-Carplay-Maps)**: the `core.so` patch
  sites (frame rate, key frames, URL, safe area), NavActiveIgnore classes, and the native route guidance solution
  (driver patch chain, HMI bridge, RGI reader) that `rg/` ports to MU1161.
- **[mathsls/MHI2-Carplay-Maps](https://github.com/mathsls/MHI2-Carplay-Maps)**: the first MU1161 + AID 791 build. The
  physical-size sites and the layout used by `map-square` come from it.
- **[ZzYunOvO/MHI2-Carplay-Maps](https://github.com/ZzYunOvO/MHI2-Carplay-Maps)**: the toolbox that the mathsls and
  tomasz-twardzicki forks build on.
- **diasdio** and **ramasauskas**: key-frame and safe-area height fixes, the AUSAFE queue fix in the MOST bridge.
- **harman-f**: cluster URL query parameters (`showETA`, `maneuverLayout`, `showSpeedLimit`).
- **[luka-dev](https://github.com/luka-dev/jxe2jar)**: jxe2jar and the RGI decoder.
- **maxim-smirnov**: documentation of the LZOZ container format.
- **MacsInSpace**: the "Forget this car" tip when the cluster gets no picture.
- The **MQB Toolbox** community: the original NavActiveIgnore idea.

Files that adapt code from these projects name their source and commit in the header or README.

## License

GPL-3.0-or-later, see [LICENSE](LICENSE). It is the same license as the omonob, tomasz-twardzicki and mathsls projects
this builds on.
