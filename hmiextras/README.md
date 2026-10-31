# Packages F (steering-wheel zoom) and G (day/night for the AID map)

[Polska wersja: README.pl.md](README.pl.md)

Status: **installed in the car (MU1161 + AID 791, October 2026): zoom works; day/night of the map switches correctly (how much of that is down to package G was not checked separately).** Build: `hmiextras/build.sh` →
`build/extras-mu1161-v2/pmcp-zoom.jar` (4,740 B, `046f4821…8d7b`) and `pmcp-dn.jar` (11,421 B, `aabe871e…fbd70`)
(v2 2026-10-22 after code review; v1 `ea90f988…`, `4e637d9a…`).
Every call into our code from the factory classes is guarded (`buildtools/Guard.java`): if J9 does not load the helper, the
factory path runs. Test `test/TestZoomGuard.java`: a patched `updateKey2` without the `com/pmcp/zoom` classes does not throw LinkageError.

## F: CarPlay map zoom with the steering-wheel arrows

- ASM hook at the entry of the factory `DSIKeyPanelDispatcher.updateKey2(keyboard, key, state, p3, valid)` (MU1161):
  `if (keyboard == 4) ZoomHook.onKey2(...)` (inline filter, other keyboards never touch our code), the call is guarded.
- MFW keyboard (4), up/down keys (38/39). **Short press only:** `zoom-in` / `zoom-out`; repeats of a held key are
  ignored. **No long-hold action** (mathsls sends `map-previous`/`map-next` after 2.5 s, which `core.so` turns
  into a switch of the cluster application; holding also scrolls the cluster lists; code review 2, finding 3).
  The command goes over UDP to `127.0.0.1:7032` to `core.so` (`map_control_command_worker` → `changeMapZoomLevel`), from one daemon
  thread and with one socket. Protocol and key codes as in `Mhi2ClusterControlBridge` (omonob/mathsls); the bridge code is no longer used.
- The key is **not consumed**: the factory handling (e.g. scrolling the cluster menu) keeps working. Consequence: an arrow in the cluster menu
  also changes the CarPlay map zoom (to be checked in the car whether this gets in the way).
- Host test: a real UDP packet `zoom-in` and `zoom-out` received on port 7032; a 3 s hold with states 3/4/5 sends nothing;
  other keyboards and keys send nothing.
- Known from omonob issues: #49/#50 ("zoom does not work" on a Golf 7 v1.2.2), #48 ("OK does not reset the zoom"). We will check in the car.

## G: AID map in night mode after a start in daylight (omonob #51)

- In the factory code the night mode goes to the phone once, in `startService(ServiceConfiguration)`, and after that only on a change
  (`ASLHandler.handleDayNightMode` → `requestNightMode`). The cluster screen (altscreen) appears a few seconds later.
- ASM hook in `ASLHandler` right after the only `startService(...)` → `DayNight.sessionStarted(target, properties)`.
  A daemon thread sends the factory event 4300038 (DAYNIGHT_MODE) **to the CarPlay target** after 5, 15 and 30 s through `triggerMe`
  (dispatcher queue, target thread). The factory `handleDayNightMode` calls `requestNightMode` only while connected.
- The value is not read in our thread (a real change waiting in the queue would be overwritten with the old value; review 2,
  finding 6): the event carries a marker in parameter 1, and a second hook at the entry of the factory `handleDayNightMode` (target thread)
  fills in `properties.isNightMode()` at the time of handling and removes the marker. Real events pass through unchanged (tested).
  After a disconnect the thread ends.
- Model: chefranov v1.1.4 (`altscreen_night_resend`, "still to be confirmed in daylight"). If resending the same value
  is not enough (the phone ignores "no change"), the next step is a short night→day toggle. That is a separate variant, not built.
- `ASLHandler` MU1161 = K4525 byte for byte, version 46.

In the installer: Java packages `zoom` and `dn` (GEM → pmcp → stage B → "Wlacz: …"), with the same trial start as the rest.
