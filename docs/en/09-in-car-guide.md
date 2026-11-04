# In-car guide: step-by-step installation (Passat B8, MHI2 MU1161, AID 791)

Installer version: **`pmcp-0.4.0-mu1161-791-…`** (the suffix identifies the build; it is the first line of
`BUILD-MANIFEST.txt` and is shown in `PMCP_INSTRUKCJA.txt` on card 1 and at the top of the green menu screen).
All green menu labels are in English (since v1.4), quoted below exactly as on the screen.

Everything is done in **one visit to the car**:

```
card 1:  1. Check  →  2. Install map  →  restart  →  map OK?  →  3. Install all features  →  restart (trial)
         →  test  →  4. Confirm (same start)  →  restart  →  works from now on
```

## Cards

| Card | Label | What it does | Note |
|---|---|---|---|
| **1 – install** | `INSTALL` | M.I.B. 3.6.0 + the installer, everything from the green menu, one action at a time | nothing starts by itself |
| **2 – rescue** | `RESCUE - DO NOT INSERT` | when inserted, the unit enters update mode **by itself** and undoes the Java changes | emergencies only; keep it out of the slot |

Both cards are made with the copy helper from the release zip (`README-FIRST.txt`). Always **only one card in the unit**,
always slot **SD1**.

## Rules for every step

- Power: battery charger/booster, or the engine running (outdoors). Ignition ON.
- **Do not interrupt** an action in the green menu (no "Back", do not pull the card) until the result is on the screen.
- Every action ends with a `PMCP_..._OK` line (good) or `PMCP_FAIL ...` (nothing was changed, or it was rolled back). On `FAIL`
  do not press anything else; take a photo of the screen.
- The SD card is read-only in the green menu, so the installer cannot write its log to the card (it prints
  `PMCP_WARN=SD_LOG_NOT_WRITABLE` and continues). **Photograph the result of every action.**
- Entering the green menu: hold **MENU for ~10 s** → `=>M.I.B.<=` → **`pmcp_CarPlay_AID`**. The header must show the version
  of your build (`pmcp-0.4.0-mu1161-791-…`); a different version = stop.
- "Restart" = **hold the volume knob for ~10 s** (the unit switches off and boots again). Switching the car off and on
  again right away is not a restart (the unit has not gone to sleep yet).

---

## Step 1. Check the card and the unit (read-only)

1. Insert **card 1**. Green menu → `=>M.I.B.<=` → `pmcp_CarPlay_AID`.
2. **"1. Check card and unit (read-only)"**. Takes a few seconds (hashes are computed by the unit's factory `sha1sum`).
3. Expected result: **`PMCP_VERIFY_OK state=STOCK`**. Nothing on the unit changes. On any other firmware the check stops here.

Read-only buttons in `pmcp_advanced`, all of them change nothing: "Start timeline" (seconds from unit start to CarPlay,
MOST, navigation), "RG last maneuver" (what the iPhone last sent for guidance and which VW arrow the strict mapping gives;
where it says main 0 the guidance package may still show a fallback arrow, e.g. at the start of a route or at a roundabout)
and "Navigation diagnostics" (why the VW navigation does not start).

If anything is unclear, **"0. Diagnostics (read-only, photograph the screen)"** (submenu `pmcp_advanced`) shows the unit's
state and changes nothing.

## Step 2. Install the map (stage A)

1. **"2. Install the CarPlay map on the AID"** → expect `PMCP_INSTALL_OK stage=A variant=map-square-fps40 ...`.
   (`map-square-fps40` is the default layout: the mathsls fork's layout, map only, closer to square, best of five after a
   longer drive; 40 frames per second like mathsls, no more lag than 30 in a test drive. `map-square` is the same at 30.
   After step 3 VW shows the manoeuvre, ETA and distance natively.)
2. Restart (knob ~10 s).
3. Connect the iPhone (CarPlay), open Apple Maps or Google Maps and **start guidance to a destination**. Switch the AID view to
   navigation/map. AID controls in this car (right side of the steering wheel): **view buttons** (cluster layout), **OK**
   between them, **up/down** next to them (cluster tabs/menu). The left side of the wheel is for driver assistance.
   Select the **Navigation** tab (up/down), then step through the layouts with the view buttons: the CarPlay map appears in
   the small centre dial and in the large full-width layout.
4. Check: CarPlay map on the AID, nothing running under the VW dials and bars.

**If the AID shows no picture:**
1. On the iPhone: Settings → General → CarPlay → this car → **"Forget This Car"**, reconnect.
2. Still nothing: green menu → **`pmcp_advanced` → `pmcp_switch_layout`** → "Switch map layout to: map-clean"
   (wider and lower map window), restart.
3. Other layouts in the same submenu (each change → restart; layouts: [AID frame map](../aid-frame-map.html)):
   `card-clean` (with the iPhone's manoeuvre card), `url-map-hybrid` (map with the speed-limit parameter, which showed
   nothing in the car), `map-clean-l40` (map 40 columns to the left), `map-clean` (200 / 108 / 400 / 296).
   Back to the default: "Switch map layout to: map-square-fps40".

Do not go on to step 3 without a map on the AID. Stage A does not touch how the head unit screen starts: the worst
outcome is no CarPlay picture, and the green menu with "Remove everything (back to factory files)" always works.

## Step 3. Install all features (or update)

**"3. Install all features or update: map, route guidance, zoom, day/night, song title"** → expect **`PMCP_ALL_ON_OK`**.

It runs, one after another: the update of an earlier route guidance system and Java set (skipped on a new install), the
main map layout (`map-square-fps40`; skipped if it is already there), the route guidance system (patched iAP2 driver,
`iap2.cfg`, reader) and the five Java packages (NavActiveIgnore, song title, route guidance `rg` with arrows, lanes,
distance bar, street name and ETA, zoom, day/night). They all land in **one set**, so there is one trial start
and one confirmation. It stops at the first failure (`PMCP_FAIL=ALL_ON_STOPPED_AT_...`; the steps before it stay done, the
screen says which). Pressing it again when everything is on changes nothing.

Updating an earlier install: the same button, see [Updating from an earlier version](#updating-from-an-earlier-version-v10-v13).

## Step 4. Trial start, test, confirm

Java changes how the head unit screen starts, so the new set goes through a **trial start**:

```
3. Install all features  →  restart  →  TRIAL START (the set loads once)
                                              │
                        everything works? ────┤
                            YES                │ NO / black screen
            in the SAME start, green menu:     │ knob ~10 s → next start is factory
            "4. Confirm: everything works"     │ (nothing confirmed, nothing to fix)
            → the set loads at every start     │
```

1. Restart (knob ~10 s). This start is the trial.
2. Check:
   - the unit starts normally (screen, radio, menus) and **CarPlay connects** (wired; plug/unplug once);
   - lanes: at a junction with lanes, the VW lane display on the AID (lane guidance must be on in the VW settings and sent by
     the phone app); a U-turn lane shows its own arrow;
   - route guidance details: an arrow right at the start of the route, the distance bar counting down before a manoeuvre,
     the current street name, and the roundabout symbol with the exit direction at roundabout turns;
   - guidance in Apple Maps: the CarPlay map **stays** on the AID (NavActiveIgnore); time and distance to destination on the
     VW bar and in the left dial; the turn arrow and the distance to the manoeuvre (the arrow appears once the car moves).
     Google Maps and Waze: check whether they work too (it is not known whether they send this data);
   - CarPlay music (Spotify/Apple Music): title and artist in the AID media view;
   - map view on the AID: a **short** press of the up/down arrow on the wheel zooms in/out (holding does nothing);
   - day/night: after a start in daylight with the lights off (not AUTO) the AID map is light; with the lights on, dark.
3. Everything works → **"4. Confirm: everything works (only in the first start after 3)"** → `PMCP_JAVA_CONFIRM_OK`.
   Only in the trial start (the installer checks this): do not switch the car off between the restart and Confirm.
4. Something is wrong or the screen stays black → restart (knob ~10 s): the next start is factory. To try again:
   **"5. Try again: the next start is a new trial"**, restart. To find out which feature is the problem, enable them one at a
   time ([advanced](#advanced-one-feature-at-a-time)).

## Step 5. Restart

Restart once more. From now on the set loads at every start. **"Status (read-only)"** shows `state=JAVA`, the set and
`This boot: set=... use=yes`.

## Updating from an earlier version (v1.0-v1.3)

1. Make **card 1 from this release** and insert it. **"1. Check card and unit (read-only)"** → `PMCP_VERIFY_OK state=JAVA`.
   "Status (read-only)" may show "Route guidance system: old" and "packages of an earlier card: rglu": that is expected,
   button 3 replaces them.
2. **"3. Install all features or update: map, route guidance, zoom, day/night, song title"** → `PMCP_ALL_ON_OK`. It replaces
   the earlier iAP2 driver and reader by this card's (the factory copies stay) and makes one new Java set in which `rglu`
   (or `rg`) becomes the new `rg`.
3. Restart: this start is the **trial**. Check that CarPlay connects, then the arrows (also right at the start of a route),
   lanes, the distance bar and the street name.
4. **"4. Confirm: everything works (only in the first start after 3)"** in the same start, then restart.
5. Make a **new card 2** (copy helper option 2): rescue cards made before v1.4 do not restore the v1.4 iAP2 driver.

**Experimental card users:** with the experimental card's Android Auto installed, "1. Check" shows state `UNKNOWN`
("Android Auto of an experimental card is installed ..."). Button 3 takes it off first (factory `gal` back from its
verified copy) and then replaces the experimental guidance packages by `rg`; restart, test, "4. Confirm". The same
removal alone: pmcp_advanced -> "Remove experimental Android Auto (factory gal back; button 3 does it too)".

---

# Emergency: card 2 (rescue)

Only if, after Confirm, the screen stays black or keeps restarting and the knob does not help:

1. Insert **card 2** into SD1 and wait (up to ~60 s). The unit enters update mode by itself and may restart several times.
   On the question in the update menu → **Continue**. Do not pull the card while it updates.
2. When the unit is back on its normal screen → remove card 2. The Java part and the route guidance system are undone
   (factory `lsd.sh`, our JARs removed, `/mnt/persist/pmcp/DISABLED`, factory iAP2 driver and `iap2.cfg`); the map stays.
3. Card 1 → "Remove everything (back to factory files)" if you want the map gone as well.
4. M.I.B. disarms card 2 after use (`Swdlautorun.txt` → `_Swdlautorun.txt`), so it cannot loop. Re-arm it on a computer:
   copy helper, option **3** (it also shows the result: `PMCP_RESCUE_LOG.txt`, `RESULT=OK`, ending with
   `=== PMCP RESCUE end ===`; a card made before v1.4 writes `PMCP_RATUNEK_LOG.txt` with `WYNIK=OK`).

Optional: card 2 can be tested once on a working unit before step 1. On a unit without our files it changes nothing of
ours (M.I.B. 3.6.0 is installed again on the way). Re-arm it afterwards with option 3.

# Rollback and failures

| Situation | What to do |
|---|---|
| No picture on the AID | iPhone: "Forget This Car", reconnect; then another layout (step 2) |
| Black screen / boot logo looping in the trial start | knob ~10 s; the next start is factory |
| A feature misbehaves | restart without Confirm (factory), then enable features one at a time ([advanced](#advanced-one-feature-at-a-time)) |
| CarPlay does not connect after step 3 | `pmcp_advanced` → `pmcp_packages` → "Route guidance system off (factory iAP2 driver and iap2.cfg)", restart |
| Black screen after Confirm | **card 2** (emergency above), then card 1 → "Remove everything (back to factory files)" |
| Roll back everything | "Remove everything (back to factory files)" → `PMCP_RESTORE_OK` → restart (factory unit) |
| Any `PMCP_FAIL` or anything unclear | do not press anything else, photograph the screen, "0. Diagnostics" (read-only) |

The only allowed firmware update is the official K4525. Never cross-flash firmware from another model.

---

# Advanced: one feature at a time

Instead of step 3, the features can be enabled one by one in **`pmcp_advanced` → `pmcp_packages`**. Every "On ..."
makes a new set → restart → trial start → test → "4. Confirm". "Off ..." goes back to the set without that package: if that set was confirmed before, it loads straight away; if not, it is a trial too. After a restart "Status" shows
`This boot: set=... use=trial` (trial, Confirm needed) or `use=yes` (confirmed).

1. **"On nai: AID map stays while the iPhone navigates (NavActiveIgnore)"**.
   Check: guidance in Apple Maps, the CarPlay map stays on the AID.
2. **"On np: CarPlay song title and artist on the AID"**.
3. Route guidance, two parts:
   - **"Route guidance system on (iAP2 driver, iap2.cfg, reader)"** (not Java, no Confirm) → restart → check **only that
     CarPlay connects**. If not: **"Route guidance system off (factory iAP2 driver and iap2.cfg)"**, restart, and skip
     the next item.
   - **"On rg: route guidance: arrows, lanes, distance bar, street, ETA (needs Route guidance system)"**.
   - From an earlier card: **"Route guidance system update (driver and reader of this card, RG stays on)"** and
     **"Java update: packages of an earlier card -> this card's (rglu -> rg)"** (one trial start, then "4. Confirm");
     button 3 runs both by itself.
4. **"On zoom: CarPlay map zoom with the steering wheel arrows"**. Watch whether it gets in the way of the cluster menu
   (same arrows).
5. **"On dn: CarPlay map day/night on the AID (sent again after start)"**.
   The key case (reported by another 791 owner, omonob #51): car outdoors in daylight, lights off (not AUTO) → start → the
   map must be light. Without this package the map stays dark until the lights are switched on.

## Cheat sheet

```
INSTALL:    card 1 → 1. Check (STOCK) → 2. Install map → restart → map on the AID?
            → 3. Install all features → restart (trial) → test → 4. Confirm → restart → done
UPDATE:     new card 1 → 1. Check (JAVA) → 3. Install all features or update → restart (trial) → test → 4. Confirm
            → restart → make a new card 2
FAILURE:    trial start broken → knob 10 s → factory start;   after Confirm broken → card 2 → Remove everything
RESCUE:     after using card 2: copy helper option 3 on a computer re-arms it
```
