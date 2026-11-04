# pmcp installer: CarPlay map on the AID, MU1161 / 791

Status: **tested in the car (October 2026; v1.4 route guidance November 2026).** Code: [`installer/`](../../installer/).
The SD build is made by `installer/build_sd.py` (the output directory holds `BUILD-MANIFEST.txt` with the hash of every file;
the version shown in GEM is `pmcp-0.4.1-mu1161-791-<build id>`, where the id is the first 8 hex digits of the SHA-256 of the
manifest and the `pmcp.sh` template). The install card is assembled by `installer/build_card_install.py`, the rescue card by
`installer/build_rescue.py`.

## Packages (built together, installed in batches from M.I.B. buttons)

| Package | What it changes | Status |
|---|---|---|
| 0 Rescue card | nothing on the unit (separate card from `installer/build_rescue.py`) | tested in the car (`RESULT=OK`; until v1.3 `WYNIK=OK`) |
| A CarPlay video + `core.so` variants | `dio_manager` → wrapper, `/mnt/app/carplaymaps` | works |
| B Java mechanism + NavActiveIgnore | one fixed block in `lsd.sh` + JAR | works; main-screen button "3. Install all features" (no unlock needed since v1.2.0) |
| C iPhone map parameters in the URL | `core.so` only (variant `url-map-hybrid`, `showSpeedLimit=yes`) | in the menu; the parameter shows nothing on this unit |
| D Track title and artist | JAR `pmcp-np.jar` (`HsmTarget` + `CurrentStationInfo`) | works ([`nowplaying/`](../../nowplaying/)) |
| E Native guidance (port of Tomasz's work) | "Route guidance system" (iAP2 driver with log gate, `iap2.cfg`, reader `pmcp-r1`) + one JAR `pmcp-guidance.jar` (package `rg`: arrows, lanes, distance bar, street, ETA, maneuver fallbacks) | works ([`rg/`](../../rg/)) |
| F Steering-wheel zoom | JAR `pmcp-zoom.jar` (hook in `DSIKeyPanelDispatcher`, short press only) | works ([`hmiextras/`](../../hmiextras/)) |
| G Day/night for the AID map | JAR `pmcp-dn.jar` (hooks in `ASLHandler`) | works ([`hmiextras/`](../../hmiextras/)) |

**Stage A does not touch the HMI** (Java): the worst outcome is no CarPlay/AA, while GEM and "Remove everything" still work.

**Everything Java goes through one block in `lsd.sh`** (before J9 starts, nothing after it), with a trial boot:
- the block reads a single file: `/mnt/app/carplaymaps/HMI_BOOT` = `SET_ID JAR JAR …` (id = `name-8 chars of sha` joined with `+`).
  `pmcp.sh` replaces it with a single `mv`, so after a power loss the boot sees either the old or the new set, never a mix;
- a new set loads **once** as a trial (`/mnt/persist/pmcp/trial.<ID>`);
- it becomes permanent **only when "4. Confirm" (confirm) is pressed in GEM during that trial boot**. On every boot `lsd.sh` first
  deletes and then writes `/mnt/persist/pmcp/last-boot` (`set=<ID> use=trial|yes|no`); `java-confirm` requires `use=trial` for the
  current id, no `ok.<ID>` and no `DISABLED`. A stock boot after a failed trial therefore cannot confirm a broken set;
- **there is no automatic confirmation**. A running J9 process does not prove a working HMI;
- without confirmation **every following boot (e.g. a reset with the knob) is stock**; to try again: "5. Try again" (repeat
  trial boot);
- **in update mode (`RUN_MODE=swdl`) the block does nothing** (the stock `lsd.sh` starts the HMI in that mode too, with a copy of
  `jars/` in `/ramdisk`). The rescue card therefore always meets a stock HMI;
- `/mnt/persist/pmcp/DISABLED` (set by the rescue card) disables the block completely.

Coming back to the car before the unit goes to sleep is not a new boot. Only a run of `lsd.sh` counts (cold start, reset, restart
after installing). `boot.log` in `/mnt/persist/pmcp` shows what happened; "Status" in GEM also shows `last-boot`.

## What it installs

The omonob/mathsls layout on MU1161:

| Item | Source | SHA-256 |
|---|---|---|
| `altscreen-most-bridge` | mathsls MU1161 profile (= ours with the diasdio fix) | `fed7dce4…44f4` |
| `carplay-cluster-supervisor` | mathsls (fix `/ramdisk` → `/dev/null`) | `8e6ac3a8…7569` |
| `libcarplay-security-bridge.so`, `carplay-pairing-helper`, `libCarPlayPairingCore.so` | mathsls = omonob | `1cef6a39…`, `ffb7d4df…`, `90c348f9…` |
| `dio_manager.wrapper.sh` | mathsls (logs to `/dev/null`) | `8c12f697…633d` |
| `core.so` | one of 5 variants (below) | in `BUILD-MANIFEST.txt` |
| `lsd.sh` (stage B+) | generated on the host from the stock file: stock + one pmcp block before `export LD_PRELOAD` / `$J9` | `LSD_JAVA` in the manifest |
| Java JARs (stage B+) | our builds (`NavActiveIgnore.jar`, `pmcp-np.jar`, `pmcp-guidance.jar` (package `rg`), `pmcp-zoom.jar`, `pmcp-dn.jar`) | in `BUILD-MANIFEST.txt` |
| route guidance system | iAP2 driver `519ea3c5…` (743,272 B), `iap2.cfg` `c61407d9…`, reader `rgi-observer` `3166df9b…` (13,552 B), see [`rg/`](../../rg/) | in `BUILD-MANIFEST.txt` |

The current `core.so` and JAR hashes are in the manifest that `installer/build_sd.py` generates for each build.

Left out on purpose: mathsls's `libcardshim.so` (`zoomFactor` 1.5, display `properties`/`uid`). The `map-square` variant therefore
takes only mathsls's safe-area layout, not their whole configuration.

`core.so` variants (`switch` changes only this file, then restart, no "4. Confirm"), all built by `build_core.py`, all 240×144 mm.
Safe area = x / y / width / height on the 800×480 stream:

| Variant | URL | Safe area | Description |
|---|---|---|---|
| `map-clean` | `maps:/car/instrumentcluster/map` | 200 / 108 / 400 / 296 | Map only, VW shows guidance natively |
| `card-clean` | `maps:/car/instrumentcluster` | 200 / 108 / 400 / 296 | with the iPhone's manoeuvre card |
| `url-map-hybrid` | `…/map?showSpeedLimit=yes` | 200 / 108 / 400 / 296 | speed-limit parameter (no visible effect) |
| `map-clean-l40` | `maps:/car/instrumentcluster/map` | 160 / 108 / 400 / 296 | shifted 40 columns to the left |
| `map-square` | `maps:/car/instrumentcluster/map` | 240 / 60 / 320 / 340 | mathsls's MU1161 layout, closer to square, 30 fps (default until v1.2.0) |
| **`map-square-fps40`** | `maps:/car/instrumentcluster/map` | 240 / 60 / 320 / 340 | **default (main button) since v1.3.0**: `map-square` at 40 fps (the base core's value, as mathsls), no more lag than 30 fps in a test drive; an IDR every 10 frames gave artefacts |

## Fail-closed gates (what must match before anything is written)

1. **Hashing self test** on the unit: the factory `/net/rcc/usr/bin/sha1sum`, run locally on MMX (where GEM scripts run), must
   compute the correct SHA-1 of `selftest.bin`. The manifest stays SHA-256; `build_sd.py` adds a SHA-256 → SHA-1 map (`HASHMAP`) to
   `pmcp.sh` for every manifest file and every factory file that is checked. No entry in the map means refusal.
   (SHA-256 in `gawk` was dropped: the "C" locale on QNX is multibyte, only `C-TRADITIONAL` worked, and it ran at about
   10–20 KB/s. With `sha1sum` actions take seconds.)
2. **Payload on the SD card:** hash and size of every file equal to the manifest embedded in `pmcp.sh`. The loop runs over the
   manifest inside the script itself (no temporary file), so a read-only card cannot skip the check.
3. **Firmware:** `lsd.jxe` = 55,830,309 bytes (MU1161).
4. **Unit state:**
   - `STOCK`: no `/mnt/app/carplaymaps`, no navigation/control JARs, `lsd.sh`, `dio_manager`, `gal`, iAP2 driver and `iap2.cfg` stock.
     `install` is allowed only in this state. A leftover `.carplaymaps-old-*` from an interrupted `restore` does not block it
     (`install` cleans it up).
   - `VIDEO` (stage A): wrapper active, stock `lsd.sh`, none of our JARs.
   - `JAVA` (stage B+): as `VIDEO`, plus the block in `lsd.sh` and a consistent JAR set (each with its manifest hash, `HMI_BOOT`
     matching exactly). A set may also hold packages of an earlier card (`JAVA_OLD`: v1.2/v1.3 `rg` `717fb53c` and `rglu`
     `72ab7221`, the experimental `rglua`, `rgluasf`, `rgluasfa`, `rgluasfm`, `rgluasfma`); then `java-on` and `java-off`
     refuse (`JAVA_SET_HAS_OLD_PACKAGES_RUN_JAVA_UPDATE_FIRST`) until `java-update` replaces them, and "Status" shows
     "packages of an earlier card: …".
   - Route guidance system (`RGSYS`, shown by "Status"): `off`, `on`, `old` (on, but with the driver and/or reader of an
     earlier card, `RG_KNOWN`: v1.0-v1.3 driver `76926bde…`, Tomasz's reader `b683cef7…`; `rg-update` replaces them) or `unknown`.
   - `PARTIAL`: an interrupted action, stock copies intact. Only `restore` (and `rg-system-off`) is allowed.
   - `UNKNOWN`: anything else, e.g. another mod or a modified `lsd.sh`. **Everything is refused.** This includes an
     experimental card's Android Auto (`carplaymaps/aa`, leftovers of an interrupted install, or a non-factory `gal`), with
     one way out: `aa-remove` ("Remove experimental Android Auto", also the first step of button 3 and of `restore`). It
     writes only on a pmcp install and only when `gal` is factory or `carplaymaps/aa/gal.real` has the factory hash: the
     factory `gal` is staged from that copy, verified and moved in, then the AA files and markers go. Running it again
     finishes an interrupted run. After it, button 3 updates the experimental `rg` variants to `rg`.
5. **Every staged copy** is hashed before the swap; `chmod` is checked, `dio_manager` must be executable. Right before the swap the
   installer checks again that `lsd.sh` and `dio_manager` are still stock.
6. **After the swap** the state must be the expected one and `core.so` must have the expected hash. Otherwise automatic rollback.
7. **Flush to disk:** `sync` on MMX (`on -f mmx sync`), because the files live there; an RCC `sync` is not needed.

Swap order:
- stage A: old trial markers removed → `carplaymaps` directory → `dio_manager`;
- `java-on`: JAR → `HMI_BOOT` (new id = new trial boot) → `lsd.sh` (only for the first package);
- `java-off`: `HMI_BOOT` → JAR removed; for the last package: stock `lsd.sh` first, then JAR and `HMI_BOOT`;
- `restore`: `lsd.sh` → `dio_manager` → JARs → route guidance system → trial markers → `carplaymaps` moved with one `mv` to
  `.carplaymaps-old-<pid>`, and only then `rm -rf`.
- route guidance system (`rg-system-on`): `/mnt/system` goes back to read-only after the write;
- `rg-update`: this card's driver and reader staged and hashed → reader stopped → driver `mv` → reader `mv`; only files
  listed in `RG_KNOWN` are replaced, `iap2.cfg`, `SYSTEM_ON` and the factory copies stay (way back: `rg-system-off`).
  Running it again after an interruption finishes the job;
- `java-update`: new JARs (a file name no earlier card used, e.g. `pmcp-guidance.jar`) → `HMI_BOOT` (new set id = new
  trial boot) → the old JARs removed. Until `HMI_BOOT` switches, the old set stays intact.

**Power-loss test** (`installer/test/fault_inject.sh`): for every action of the chain
install → java-on nai → java-on np → rg-system-on → java-on rg → switch → java-off np → java-off rg → rg-system-off → java-off nai → restore
the script is killed before the 1st, 2nd, 3rd … command that changes the unit. For each point: a simulated **next boot** (the
`lsd.sh` block from the killed tree) must not load, without a trial, a set the user has not confirmed; the state must be
STOCK/VIDEO/JAVA/PARTIAL, and `restore` (or install+restore from STOCK) must give the stock tree.

## Use in the car: GEM buttons

Requires: M.I.B. installed ([01-mib-install-backup.md](01-mib-install-backup.md)) and an **install card** built by
`installer/build_card_install.py`: a complete card = the untouched `MIB_V3.6.0.zip` tree (autorun disarmed, `_Swdlautorun.txt`) +
the SD build from `installer/build_sd.py` (`pmcp/`, `esd/Launcher-sda0.esd`), assembled with
`python3 -I installer/build_card_install.py <SD build> <card dir>` (every build file is checked against `BUILD-MANIFEST.txt`; it
refuses an armed autorun or rescue-card files). Hashes of all files: `PMCP_CARD_MANIFEST.txt`, instructions:
`PMCP_INSTRUKCJA.txt`. You copy **the whole content** of the directory to an empty card (FAT32) instead of adding `pmcp/` to an
M.I.B. card by hand.

How it works: in GEM the unit has a symlink `engdefs/z_Launcher-sda0.esd` → **the menu file on the card**
(`/net/mmx/fs/sda0/esd/Launcher-sda0.esd`, created by M.I.B. at install time). The `pmcp_CarPlay_AID` screen is appended to that
file on the card. Nothing changes on the unit. The base file is exactly `esd/Launcher-sda0.esd` from `MIB_V3.6.0.zip`
(`22739f72…9121`); a test checks that the original content is untouched (only the end is appended).

1. On the computer: copy the whole content of the install card directory to an empty card (card root).
   Check the version in the header of the pmcp screen in GEM: it must match the first line of `BUILD-MANIFEST.txt`.
2. In the car: GEM → `=>M.I.B.<=` → **`pmcp_CarPlay_AID`**. Main screen (English):
   - "1. Check card and unit (read-only)" → `verify`;
   - "2. Install the CarPlay map on the AID" → `install map-square-fps40` (stage A);
   - "3. Install all features or update: map, route guidance, zoom, day/night, song title" → menu script `all-on.sh`:
     `rg-update`, `java-update`, `switch map-square-fps40`, `rg-system-on`, then `java-on` nai, np, rg, zoom, dn, one after
     another (one set, one trial boot); stops at the first `PMCP_FAIL`, `*_ALREADY_*` counts as done (`switch` to the map
     already active answers `SWITCH_ALREADY_<variant>`), so the same button brings any earlier install (v1.0-v1.3, or the
     experimental card's rg variants after Android Auto is removed) to this card's set;
   - "4. Confirm: everything works (only in the first start after 3)" → `java-confirm`;
   - "5. Try again: the next start is a new trial" → `java-retry`;
   - "Status (read-only)", "Remove everything (back to factory files)" → `restore`;
   - submenu `pmcp_advanced`: "0. Diagnostics (read-only, photograph the screen)" (works even when `pmcp.sh` stops at its
     self test), "Start timeline: …", "RG last maneuver: …" (what the iPhone sent and which VW arrow the strict mapping
     gives; where it shows main 0 the `rg` package may still show a fallback arrow), "Navigation diagnostics: …", and the
     submenus `pmcp_other_layouts` ("Install map layout: <variant>"), `pmcp_switch_layout` (`switch`, "Switch map layout
     to: <variant>") and `pmcp_packages`: "Route guidance system on (iAP2 driver, iap2.cfg, reader)", "Route guidance
     system off (factory iAP2 driver and iap2.cfg)", "Route guidance system update (driver and reader of this card, RG
     stays on)" (`rg-update`), "Java update: packages of an earlier card -> this card's (rglu -> rg)" (`java-update`),
     and "On …" / "Off …" for each package (nai, np, rg, zoom, dn).
   No action needs an unlock file (until v1.1.0 the Java and route guidance actions needed `pmcp/ODBLOKUJ_ETAP_B`).
3. The result is on the GEM screen. The SD card is read-only in GEM (even `mount -uw` fails), so the log cannot be written to the
   card: the installer prints `PMCP_WARN=SD_LOG_NOT_WRITABLE` and carries on. **Photograph the screen.** If the card is writable,
   the log goes to `/pmcp/log/pmcp-<action>-<pid>.log`.

All labels are in English (since v1.4) and plain ASCII.

Order (one visit to the car):
1. "1. Check card and unit" (`verify`): read-only. Expected `PMCP_VERIFY_OK state=STOCK`.
2. "2. Install the CarPlay map on the AID" (stage A), then a full restart. If the AID shows no CarPlay picture: on the iPhone,
   Settings → General → CarPlay → the car → "Forget This Car", and reconnect (the iPhone remembers the car's old displays).
   For another map layout: `pmcp_advanced` → `pmcp_switch_layout` → "Switch map layout to: …".
3. Only if the map works: "3. Install all features" → restart (trial boot) → check the HMI and the features →
   **in the same boot** "4. Confirm" → restart. Without confirmation the next boot is stock.
4. Rollback: "Remove everything (back to factory files)" and restart.

Updating from v1.0-v1.3: "1. Check" (state `JAVA`; "Status" may show "Route guidance system: old" and "packages of an
earlier card: rglu"), then "3. Install all features or update" (runs `rg-update` and `java-update`) → restart (trial
boot) → "4. Confirm". Make a new rescue card too (see below).
The rescue card is for emergencies after Confirm; testing it first is optional.

Step-by-step guide for the car: [09-in-car-guide.md](09-in-car-guide.md).

## Host tests

`installer/test/run_tests.sh SD_BUILD mksh ksh` (with `PMCP_RESCUE_SD=<rescue card>`): the unit's file tree from the backup (real
`lsd.sh`, `dio_manager`, `jars`, iAP2 driver, `iap2.cfg`; `lsd.jxe` as a file of the right size), shells `mksh` (pdksh family, like
QNX) and `ksh` (ksh93). The exit status is the number of failed checks. They cover, among other things:

- `verify` writes nothing; a wrong variant, a corrupted payload byte (also with an unwritable log directory), a corrupted self test,
  a wrong `lsd.jxe` size, a modified `lsd.sh` and a foreign mod are refused with no change to the tree;
- the full chain install → Java packages (1, 2 and 5 at once) → route guidance system → switch → restore gives a tree **byte-identical** to stock;
- **trial boot on the real `lsd.sh` block** combined with `pmcp.sh`: trial → unconfirmed boot is stock → "4. Confirm" refused →
  retry → a boot in `swdl` mode loads nothing and deletes `last-boot` → confirmation only during the trial boot → a confirmed set
  always loads → `DISABLED` disables and blocks confirmation;
- the patched `lsd.sh` = stock + one block (checked with `diff`);
- leftovers (`.carplaymaps-new-*`, `.carplaymaps-old-*`, `*.pmcp-*`, old `ok.*` markers) are cleaned up by `install`; an
  interrupted `restore` (directory already moved) does not block the tool;
- rescue card: a healthy unit is unchanged; a `JAVA` unit → stock `lsd.sh`, JARs removed, `DISABLED`; a unit with the route
  guidance system → stock driver and `iap2.cfg`, `SYSTEM_ON` and `last-boot` removed; no backup copy or no `lsd.sh` → an honest
  `RESULT=UNSURE`;
- GEM menu: number of scripts = number of menu entries, syntax, allowed actions, main button = `map-square-fps40`, the version with build
  id identical in `pmcp.sh`, the menu and `BUILD-MANIFEST`.

`installer/test/fault_inject.sh SD_BUILD mksh`: the power-loss test (above).

What the host tests do not cover: QNX paths (`on -f mmx`, `mount`, `slay`, `/net/mmx` path translation) and the factory `sha1sum`
are skipped in test mode (the host computes SHA-1 with `shasum -a 1`); file permissions are not part of the `snapshot`; the
`Swdlautorun` → `stuff.sh` chain is tested on the script only. These parts were checked in the car.

## Rescue card (package 0)

A separate card (`installer/build_rescue.py`, instructions in `PMCP_RESCUE_README.txt` on the card). An armed `Swdlautorun.txt` →
the unit enters update mode by itself (`RUN_MODE=swdl`; our block loads nothing then) → M.I.B. 3.6.0 `stuff.sh` →
`pmcp-rescue/pmcp-rescue.sh`:
- stock `lsd.sh` from `/mnt/app/carplaymaps/rollback/`;
- our JARs removed;
- `/mnt/persist/pmcp/DISABLED`, `last-boot` removed;
- route guidance system: stock iAP2 driver and `iap2.cfg` from the backup copies (selected by size; our driver sizes known:
  743,196 B for v1.0-v1.3 and 743,272 B for v1.4), `SYSTEM_ON` removed.

The video (stage A) stays; "Remove everything" in GEM cleans up the rest afterwards. On a healthy unit without pmcp the script changes
nothing and only writes the log `PMCP_RESCUE_LOG.txt` (`=== PMCP RESCUE start ===` … `RESULT=OK` or `RESULT=UNSURE` …
`=== PMCP RESCUE end ===`). The M.I.B. autorun in P4512 update mode works without any HMI interaction (checked in the car).

Until v1.3 the card was in Polish (`pmcp-ratunek/`, `PMCP_RATUNEK_LOG.txt`, `WYNIK=OK` / `WYNIK=NIEPEWNY`); the copy helpers
read both log names. A rescue card made before v1.4 still works on a unit with the v1.3 driver, but it does **not**
restore the v1.4 driver (it only knows 743,196 B): after updating to v1.4, make a new rescue card (copy helper option 2).

After use M.I.B. disarms the card (`Swdlautorun.txt` → `_Swdlautorun.txt`) so it cannot loop. Re-arming is done on a
computer (copy helper option 3, or renaming the file by hand). Since v1.2.0 the installer no longer requires a rescue test
before the Java actions; it is recommended, not enforced.

## Safeguards for starting J9 with our JARs

Classes are version 46, references are checked against the unit's `java/*` classes (RefCheck), and every call from stock code is
guarded (tools in [`buildtools/`](../../buildtools/)). The scripts use the ksh constructs of the mathsls installer (backticks,
`while read`, heredoc, `case`, `read` with redirection). Fallback if something goes wrong: the trial boot with manual confirmation,
then the rescue card. Black screen during a trial boot (before "4. Confirm"): hold the volume knob for 10 s; the next boot runs without our JARs.
