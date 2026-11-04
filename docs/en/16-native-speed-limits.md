# Native speed limits alongside CarPlay

The optional native speed-limit package `sl` (by amjad-alarori, PR #3) adds text such as `Limit 50 km/h` to the AID
street text. The value comes from the built-in VW navigation database through `DSITrafficRegulation`. The CarPlay app
continues to route while VW route guidance is ended. The iPhone sends no speed limit; this is the car's own map data.

Since v1.4.1 there are two modes:

- **in front of the street name** (`turnto`): the limit goes before the street that `rg` writes to TurnToInfo. On the AID
  that one field shows in two places, the top bar and the right dial. Needs `rg`.
- **trial in CurrentPositionInfo** (`street`): the limit goes only into the NavSD CurrentPositionInfo street. Nobody has
  seen yet where AID 791 shows that field (top bar only, somewhere else, or nowhere). Photograph the result.

## Tested configuration

The R3 trial displayed the native limit through NavSD TurnToInfo, function 20, on an e-Golf with this configuration.

| Component | Configuration |
|---|---|
| Firmware | `MHI2_ER_VWG13_P4512_1`, MU1161 |
| Cluster | `5G1920795A`, hardware 408, software 3195 |
| Installed CarPlay package | v1.3.0 with `rglu` guidance |
| Route app during the test | Google Maps |
| VW route guidance during the successful test | Ended |
| Observed limit transition | 50 to 70 km/h |

The persistent setting and revised value lifetime have passed host tests. Their behavior after installation and a full
vehicle restart remains to be confirmed. Additional firmware and cluster combinations require their own validation.

## Install and confirm the optional package

Start with a working v1.4.1 install (button 3 and Confirm). The normal installation and Java recovery mechanism are
described in the [in-car guide](09-in-car-guide.md). GEM button texts are quoted exactly; the action is in brackets.

1. "1. Check card and unit (read-only)" (`verify`).
2. Advanced → packages: "On sl: native VW map speed limit in the AID road text (optional, output off until enabled)"
   (`java-on sl`). Its output mode starts off. Button 3 never installs this package.
3. Restart the unit (hold the volume knob ~10 s). This start is the Java trial for the new set.
4. Check that menus, audio, CarPlay, map and guidance work. Advanced: "Speed limit status: mode and native VW limit data
   (read-only)" (`speedlimit-status`) should show `status=valid` and a `speed_limit_raw` value while driving.
5. In that same start: "4. Confirm: everything works (only in the first start after 3)" (`java-confirm`).
6. Advanced: "Speed limit: in front of the street name (top bar and dial; needs sl and rg)" (`speedlimit-mode turnto`), or
   the trial "Speed limit TRIAL: in CurrentPositionInfo only (photograph where it shows)" (`speedlimit-mode street`).
7. The mode applies within about a second; it is kept across restarts. Back to the plain street name: "Speed limit: off
   (street name as before)" (`speedlimit-mode off`).

For the route test, connect CarPlay, start Google Maps guidance and end any VW route guidance. Keep the AID navigation
view selected. The native limit should appear in the turn-to text while the CarPlay maneuver and distance remain visible.
Check a road-limit transition with a passenger observing the displays, or compare the displays while parked at suitable
locations.

Confirmation belongs to the installer Java trial. The saved speed-limit mode is a separate setting. An unconfirmed Java
set follows the existing installer recovery behavior on the next boot.

## Persistent setting

| Action | Result |
|---|---|
| `speedlimit-mode turnto` | Save the prefix in `rg`'s TurnToInfo text as the selected mode (needs `rg`) |
| `speedlimit-mode street` | Save the CurrentPositionInfo trial as the selected mode |
| `speedlimit-mode off` | Save output off and restore the factory street text through the normal refresh path |
| `speedlimit-status` | Read the saved mode and current helper state |

The setting is stored in `/mnt/persist/pmcp/native-speedlimit-mode`. The installer replaces that small file atomically.
Missing, invalid or unreadable settings select off. The helper reads the setting during its normal polling cycle.

The selected mode survives a head unit restart. The captured road limit stays in memory for the current Java session.
After a restart, a native notification supplies the current value again.

## Value updates

The native current-sign attribute supplies the numeric limit, limit type and unit. An unchanged valid value remains
current until another native event replaces or invalidates it. The 120-second expiry used during early trials has been
removed, so a steady limit can remain visible during a longer drive on the same road.

The prefix hides when the native event is invalid, sign or limit information is absent, the numeric value or unit is
unknown, the limit type is unsupported, the clock moves backwards, or CarPlay is inactive. Native observations continue
while CarPlay is inactive. A Java restart clears the captured limit.

The initial native notification can include the `0x80` initial-notification flag. The current helper removes that flag
before requiring validity `1`. An earlier trial used the `0x8000` mask and could classify an initial valid event as invalid.
The corrected normalization has host-test coverage.

This is the last reported current native value. Sample age remains visible in diagnostics. Detecting a silent native
source stall requires an additional verified availability signal.

## Diagnostics

Run `speedlimit-status` with the affected CarPlay route active. Relevant fields include the saved output mode, helper
availability, stage registration, CarPlay connection, native validity, numeric limit, unit, sample age, filter activity and
refresh errors. The helper writes its bounded runtime state to `/ramdisk/pmcp-speedlimit.state`.

A valid sample alone establishes the native data source. Filter diagnostics establish whether the turn-to string was
decorated. BAP status counters preserve the factory call's raw boolean result. The send-buffer adapter returns whether
the cached value changed, while the base adapter can transmit and return false. These counters provide no delivery
acknowledgement. Visual rendering requires a separate display check.

If a result needs investigation, retain the complete status output and describe whether VW guidance was active, which
CarPlay app was routing, and which AID view was selected. The source code and build details are in the
[module README](../../speedlimit/README.md).

## Disable or remove

Run `speedlimit-mode off` to disable the prefix. Check the normal street text and confirm the off setting after a reboot.
To remove the optional Java package, run `java-off sl` and follow the installer prompts for the resulting Java set.
The normal Java trial and rescue procedures remain available through the installer.

## Appearance and scope

TurnToInfo carries a street string with a 76-byte UTF-8 budget. The limit prefix appears first, followed by the existing
street text when present. Long road names use the factory string truncation behavior. The signpost field retains its
factory contents.

The package currently displays the limit as text. Native traffic-sign icon rendering remains unvalidated for this
MU1161/AID combination. The verified street interface accepts strings. A separate graphics path would need validation
before an icon could become part of this feature.
