# Audit: AID fast start (tried, failed, closed)

[Polska wersja](../pl/14-audyt-szybki-start.md)

Unit: Discover Pro MHI2 MU1161 (train `MHI2_ER_VWG13_P4512`) with AID 791, VW Passat B8 MY2018. Done on 2026-10-31.
**Result: no gain, and one of the attempts put the AID into a fault state until the car slept. Nothing of this is in
v1.3.0. The topic is closed.**

## The goal

After a cold start the CarPlay stream for the AID is ready at about 26 s (supervisor event `bridge-ready`). The map
appears on the AID only at about 43 s. The aim was to show the CarPlay map at about 26-30 s.

## What holds the map back (found during the attempts)

The order below is from the decompiled MU1161 HMI classes and the unit's start configuration. Car logs confirmed it.

1. The HMI starts in one thread (ASL startup `startupv7r`, `TASK_POOL_COUNT=1`). The work units and their order come from
   `configurationmanager.res` in `/ifs/hmi/res` (79 units).
2. Unit #43 `SPECIAL_METHOD_WAITFOR_NAV_TO_FINISH` keeps that only thread until the VW navigation reports
   `EV_NAV_IS_COMPLETELY_READY`, about 43 s after the unit starts (timeout 60 s).
3. The cluster units come after it: #46 `FPK_GENERIC` (cluster video sink, `DSIKOMOGfxStreamSink`) and #47
   `FPK_NAV_KOMO` (its precondition is #43 by name).
4. The cluster module (`mostkombi`) starts the video sink only after 3 controllers have registered. The sink registers
   only when the MOST video sink reports state 1.
5. Even then, the sink's `WaitForServices` opens the stream only when the VW navigation's cluster map reports status 2
   (`1110044 == 2`), when the cluster display is known (`KombiDisplay != -2`) and when the AID reports that it can show a
   map (`MostCapabilityForMap == 2`).

So the CarPlay map waits for the VW navigation twice: in the start queue and at the sink's gate.

## The attempts

All attempts were Java packages loaded through the installer's trial mechanism: a new set loads once, and without
Confirm the next start is factory again. None of them was confirmed.

| Package | What it changed | Result in the car |
|---|---|---|
| kf (v1) | The gate saw status 2 when the CarPlay stream was ready. It also skipped the wait for the navigation's answer to "map visible". | **Failed.** The gate was never checked again after the stream became ready, so it opened at the factory 43 s anyway. Skipping the answer left the VW navigation stuck on "loading"; it did not work after a restart either. Recovered with "AID fast start off" (back to the confirmed set). |
| kf2 | A 1 s timer checks the gate again while the CarPlay stream is ready. "Map visible" is held back until the real navigation status is 2, so it is never sent early. | **No change (about 40 s).** The log showed the gate's state was entered only at 44.4 s and passed at once. The gate was not the bottleneck. kf2 was harmless: the VW navigation loaded normally. |
| kf3 | kf2 plus log-only probes in the cluster module's start. | **Diagnosis only.** The whole cluster module started at 43.0 s: the sink, the MOST state and all 3 controllers. The cause is the start queue (above), not the gate. |
| kf4 | kf3 plus a change to the HMI start order: the cluster units #46/#47 move before the navigation wait #43. This was applied only when the 4 units had exactly the factory preconditions. | **Failed, and it broke the AID.** The reorder worked (log: "cluster units moved before the navigation wait"), but the cluster module still started only at 40.0 s (3 s gain), because the units before it also wait for the navigation. The VW navigation did not start in this trial start. |

## What broke after kf4, and how it was fixed

- After kf4 was turned off (the confirmed set without kf loaded again), the AID kept showing "Starting map view".
  Neither the VW map nor the CarPlay map appeared. The VW navigation on the centre screen worked.
- None of these helped:
  - restarting the unit;
  - removing the SD card;
  - **Remove everything** (all factory files, checked by hash);
  - a factory reset of the navigation in the unit's menu.
  So the cause was not in the unit's files or settings.
- The fix was letting the bus sleep: ignition off, car locked for about 15-20 minutes. After that the VW map was back on
  the AID, and the CarPlay map came back after a fresh install.
- Most likely cause (not proven): in the kf4 trial the sink got the CarPlay "status 2" at 40.1 s, before the VW
  navigation drew its cluster map. The HMI then sent the AID the whole permanent-map sequence:
  1. fade out;
  2. display context 70;
  3. route guidance select;
  4. data rate 10;
  5. foreground layer 3;
  6. fade in.

  The AID is a separate ECU. It probably kept a map-source fault and kept reporting a state that the factory gate
  (`KombiDisplay`, `MostCapabilityForMap`) never accepts, until the bus slept. A restart of the head unit does not reset
  the AID.

## Why it cannot work this way

- The cluster map is tied to the VW navigation start, about 40-43 s, even with the start order changed.
- A real gain would need changes to the navigation's own start. That is native code and the map database, with no trial
  mechanism and no safe way back.
- The only other way round would be to give the AID map commands before the navigation is ready. That is exactly what put
  the AID into the fault state above.

## Lessons (rules for this project)

1. Do not change the HMI start order.
2. Never send the cluster map sequence (map visible, context switch, data rate) to the AID before the VW navigation is
   really ready.
3. If the AID shows "Starting map view" and the files are factory, do not reinstall or reset anything first. Let the car
   sleep (locked, 15-20 min).
4. The trial start worked every time: each failed package was gone after one restart without Confirm. It does not
   protect state stored in other ECUs (the AID).

## Also tried on the same day, not shipped

- **Cluster day/night for Google Maps.** Two attempts:
  - "day/night v2" re-sent the night mode every 10 s;
  - a module in `dio_manager` sent `setNightMode` for the cluster display only, and later also marked the display as
    "Instrument Cluster".

  The phone accepted every command (status 0), but Google Maps on the AID stayed dark. Apple Maps switches correctly with
  the factory path. The head unit's AirPlay receiver knows only `nightMode`, not the "appearance" setting that Google
  Maps seems to use. Parked.
- **Lanes without U-turns** (`rgl`): replaced by `rglu` (lanes with U-turn arrows), which is in v1.3.0.
