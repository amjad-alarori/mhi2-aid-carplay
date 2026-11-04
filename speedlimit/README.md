# Native VW speed limits on the AID

This optional Java package displays the built-in VW navigation speed limit in the AID navigation text. It reads the
head unit's `DSITrafficRegulation` current-sign attribute and prefixes the turn-to street with text such as
`Limit 50 km/h`. Google Maps continues to supply the CarPlay map and route guidance.

The in-car procedure is in [Native speed limits](../docs/en/16-native-speed-limits.md).

## Scope and validation

The R3 trial demonstrated the TurnToInfo output with Google Maps routing active and VW route guidance ended. The
reported native limit changed from 50 to 70 km/h and the AID text followed it on this vehicle.

| Component | Tested configuration |
|---|---|
| Vehicle | VW e-Golf |
| Head unit | `MHI2_ER_VWG13_P4512_1`, MU1161 |
| AID | `5G1920795A`, hardware 408, software 3195 |
| CarPlay package | v1.3.0 with `rglu` guidance |
| Native limit source | Navigation database, `NAVDBRAWDATA` |

The persistent mode and retained-value policy in this source revision have host-test coverage. Their in-car
confirmation is pending. Compatibility with additional firmware versions and AID variants requires separate validation.

## Runtime path

1. A guarded hook in `DSITrafficRegulationDispatcher.updateCurrentTrafficSign` copies the native event into an immutable
   snapshot. The snapshot contains primitive values and remains in the running Java process.
2. `NativeSpeedLimit` selects a valid conventional limit and preserves its metric or imperial unit. The initial-notification
   flag is `0x80`. Normalization clears that flag and requires the remaining validity value to equal `1`. The earlier trial
   mask using `0x8000` has been corrected.
3. A guarded filter in NavSD `TurnToInfo` prefixes its street string. Function 20 passes that value through
   `NavInfoAdapter` to `DSIKOMONavInfo.setTurnToStreet`. The existing signpost string follows its factory path.
4. Refreshes use the factory BAP thread-switching service and `process(-1)`. Service initialization stays on the BAP
   lifecycle thread. The helper coalesces refresh requests and rejects tasks for an unregistered stage.

The turn-to street has a 76-byte UTF-8 budget. The prefix precedes the road name so the limit survives normal string
truncation. The package retains CurrentPositionInfo instrumentation for diagnosis. The public persistent mode selects
the tested TurnToInfo route.

Every firmware-to-helper call has a `Throwable` guard. String failures retain the original string, and status-result
hooks retain the original boolean. BAP result diagnostics describe a changed-value transmission request or a deduplicated
value. Visual rendering requires a separate display check. The implementation is in the
[runtime helper](src/com/pmcp/sl/NativeSpeedLimit.java) and
[exact-class patcher](patcher/PatchNativeSpeedLimit.java).

## Current value and lifetime

The current native attribute remains usable until a later event replaces or invalidates it. The 120-second timer from
the trial builds has been removed. This permits a limit to remain visible on a long road while its value stays unchanged.

Invalid events, absent sign or limit data, unsupported limit types, unknown units, unknown numeric values and a reversed
clock hide the prefix. A failed observation clears the captured snapshot. CarPlay inactivity hides the prefix while native
observations continue in the background.

The last limit is held in memory for the running Java session. A Java restart starts with an empty snapshot and requires
a native notification. The persistent setting stores the selected output mode. Sample age remains available in the
diagnostics. Detecting a silent source stall would require a separately validated source-availability signal.

## Optional persistent mode

The installer exposes these actions.

| Action | Effect |
|---|---|
| `java-on sl` | Add `pmcp-sl.jar` through the standard Java trial mechanism |
| `speedlimit-mode turnto` | Enable the TurnToInfo prefix across restarts |
| `speedlimit-mode off` | Disable the prefix across restarts |
| `speedlimit-status` | Show the selected mode and current runtime diagnostics |
| `java-off sl` | Remove the Java package through the standard installer |

The mode file is `/mnt/persist/pmcp/native-speedlimit-mode`. The controller writes `off` or `turnto` using a staged file
and an atomic rename. A missing, unreadable or invalid mode file disables output. A fresh installation starts with output
off. The generic install-all action excludes this optional package.

Install the package, reboot into its Java trial, test the normal head unit functions and capture, then run `java-confirm`
in that same boot. Enable `turnto` after confirmation, reboot, and test again. Detailed steps and rollback are in the
[in-car procedure](../docs/en/16-native-speed-limits.md).

## Building

Build inputs include the locally converted MU1161 `lsd.jar` and ASM 9.7. The scripts pin the converted firmware and ASM
hashes, and the patcher pins every modified factory class. The tested toolchain is Eclipse Temurin JDK
`17.0.21+9`. Helper sources compile with Java 8 language and API compatibility, and the packaged classes use the factory
J9 class-file version 46.

On a POSIX host, set `JAVA_HOME` to the JDK or put its tools on `PATH`, then run from the repository root.

```sh
ASM_DIR=/path/to/asm-9.7 \
  ./speedlimit/build.sh /path/to/MU1161-stock-lsd.jar /path/to/fresh-build
```

On Windows, run the PowerShell builder from the repository root.

```powershell
.\speedlimit\build.ps1 `
  -StockJar C:\build-inputs\MU1161-stock-lsd.jar `
  -Jdk C:\build-tools\jdk-17.0.21+9 `
  -AsmDirectory C:\build-tools\asm-9.7 `
  -BuildRoot C:\build-output\native-speedlimits
```

Use a fresh output directory. The result is `pmcp-sl.jar` with `BUILD-VALIDATION.json`. The build checks exact hook scope,
untouched factory methods, original-string and boolean fallbacks, J9 API references, bytecode validity and helper behavior.
These host checks complement the vehicle evidence described above.

After assembling an installer card, the optional-package cases can run separately from the full installer suite.

```sh
PMCP_TEST_SCOPE=speedlimit \
  bash installer/test/run_tests.sh build/sd /bin/ksh
PMCP_FAULT_SCOPE=speedlimit \
  bash installer/test/fault_inject.sh build/sd /bin/ksh
```

The test fixtures use the same pinned factory files as the normal installer tests. Run the full installer suites as well
when validating a release. Host tests verify control flow and file contents. QNX execution and the AID presentation require
the vehicle checks in the procedure.

Keep firmware inputs, dumps, generated JARs, local logs and vehicle photos outside the source contribution.

## Display limitation

The implemented output uses navigation text. Native traffic-sign icon rendering remains unvalidated for this
MU1161/AID combination. The verified NavInfo street interface accepts strings, and a graphics overlay over the active
CarPlay stream requires a separately validated rendering path.
