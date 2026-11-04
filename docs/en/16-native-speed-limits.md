# Native speed limits alongside CarPlay

The optional native speed-limit package adds text such as `Limit 50 km/h` to the AID turn-to street area. The value comes
from the built-in VW navigation database through `DSITrafficRegulation`. Google Maps can continue routing through
CarPlay while VW route guidance is ended.

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

Start with a working CarPlay map and guidance installation. The normal installation and Java recovery mechanism are
described in the [in-car guide](09-in-car-guide.md).

The action names below identify the corresponding controls in the generated installer menu.

1. Run the card and unit check with the card built for this firmware.
2. Run `java-on sl` to add the native speed-limit package. Its output mode starts off. The generic install-all action
   excludes this optional package.
3. Reboot the head unit using the volume knob. This boot is the Java trial for the new set.
4. Check that the normal head unit menus, audio, CarPlay connection, map and guidance work. Run `speedlimit-status` and
   check that the helper is capturing native limit data. The output can remain off during this check.
5. Run `java-confirm` in that same trial boot after those checks pass.
6. Run `speedlimit-mode turnto` to enable the prefix persistently.
7. Reboot again and test the confirmed set and saved output mode.

For the route test, connect CarPlay, start Google Maps guidance and end any VW route guidance. Keep the AID navigation
view selected. The native limit should appear in the turn-to text while the CarPlay maneuver and distance remain visible.
Check a road-limit transition with a passenger observing the displays, or compare the displays while parked at suitable
locations.

Confirmation belongs to the installer Java trial. The saved speed-limit mode is a separate setting. An unconfirmed Java
set follows the existing installer recovery behavior on the next boot.

## Persistent setting

| Action | Result |
|---|---|
| `speedlimit-mode turnto` | Save TurnToInfo output as the selected mode |
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
