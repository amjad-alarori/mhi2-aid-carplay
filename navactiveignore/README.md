# NavActiveIgnore from the unit's own firmware classes

[Polska wersja: README.pl.md](README.pl.md)

Our equivalent of the "Ignore navigation-active status from smartphone" patch. While the iPhone is guiding, the HMI does not report
"navigation on the phone", does not stop VW navigation and does not take guidance away from the phone. This keeps the map
on the AID working, and CarPlay keeps its guidance.

Based on: Tomasz (tomasz-twardzicki), `upstream/tomasz/MU1427/NavActiveIgnore/`, GPL-3.0-or-later.
Original idea: MQB Toolbox `NavActiveIgnore.jar`.

## Why not the generic JAR

The generic JAR (`CarPlayNavigationPatch.jar` in mathsls and omonob, SHA-256 `a4803f7f…`) replaces whole HMI classes
compiled from a faulty decompilation:
- int constants have their byte order reversed: 100012 → -1400504064, 2910009 → 963062784;
- long constants are zeroed (the 5000 ms and 300 ms timeouts become 0);
- there is `printStackTrace` on hot paths.

Our build takes the **factory classes** from the converted `lsd.jxe` and changes only the selected instructions (ASM).
Every change checks the exact pattern and the number of matches, and on a mismatch the build stops.

## Changes (K4525)

| Class | Change |
|---|---|
| `DSICarplayProxy.requestModeChange` | removes "native navigation takes over" (`appStateID=2, state=true, speechMode=0`) from the requests to the iPhone; skips the whole call only when nothing else is left |
| `CarPlayModeHandling.handleModeChanges` | while CarPlay is guiding: no `valueChangedBoolean(2910009, true)`, no `setActiveNavigation(2)`, no `stopGuidance(6)`; while the HMI is guiding: no `requestModeChange(…, "User initiated")` |
| `ASLNavigationServices.stopGuidance` | ignores reason 6 (smartphone took over navigation) |
| AA `NavigationListener` | `updateGuidanceActive` and `stopGuidance` do nothing, `isGuidanceActive` returns false |
| AA `RequestHandler.performNavFocusRequestNotification` | both focus types treated as "projected", no `stopGuidance()` and no `valueChangedBoolean(2910005, true)` |

Differences from MU1427 (Tomasz): different property IDs (2910009 and 2910005 instead of 3010002 and 3110002), the switch
in `RequestHandler` handled in both forms (table and lookup). The exbox calls
(`setSmartphoneGuidanceActive/Inactive`, K4525 only) stay factory: they go only to `DSIExBoxM`,
the external navigation box.

Deliberately **no** data rate change (`ChangeDataRate`/`ChangeDataRateSequence`). For Tomasz both attempts froze the map
on "loading map".

## Building

```sh
ASM_DIR=upstream/tools/jxe2jar/repo/tools/uninline/lib \
  navactiveignore/build.sh K4525 archives/x-k4525/jar/lsd-k4525.jar build/nai-k4525
```

The script:
- checks the hashes of ASM 9.7 and of the converted jar;
- patches the classes, verifies them (ASM `SimpleVerifier`) and forces class version 46 (factory J9; desktop Java accepts 49 and would not catch the error);
- writes a report `report/*.diff` (javap, factory vs patched);
- packs a deterministic JAR and runs the host test (`-Xverify:all`, helper logic);
- writes `manifest.txt` with the hashes of inputs and outputs.

K4525 result (2026-10-20): `NavActiveIgnore.jar`, 13,214 B, SHA-256
`a6781738a658aa64151e24e481af726347cc99967f0a5a24b530b66215cd9c7b` (reproducible).

## Status and limitations

- **MU1161 profile (our car, backup 2026-10-21):** the five patched classes are byte-identical to K4525, the property IDs
  are the same. Result `build/nai-mu1161/NavActiveIgnore.jar`, SHA-256 `823adeb022363aafc66979670e9cf4a6c58ac45297f2f2eea1680f825881ba2d`.
- **v2 (2026-10-22, after code review):** both helper calls in `DSICarplayProxy.requestModeChange` are guarded
  (`buildtools/Guard.java`: on a helper error the factory request stays), the build checks the J9 API (`buildtools/RefCheck.java`).
  Result `build/nai-mu1161-v2/NavActiveIgnore.jar`, 13,285 B, SHA-256 `dbd031ecb28a2ec91c4704e133f4e2126cf1fe11498f673bc2e07fc0b1aaa7ab`.
  The classes are identical to the K4525 build, only MANIFEST.MF differs. We install the JAR from the profile that matches the firmware in the car.
- Not tested on the factory J9 (Tomasz ran ARM J9 under QEMU) or in the car.
- Installation (the `-Xbootclasspath/p:` entry in `lsd.sh`, backup, rollback) belongs to the fail-closed installer.
  Recovery: remove the JAR from `/mnt/app/eso/hmi/lsd/jars/`; J9 skips missing bootclasspath entries (Tomasz).
- Replaces the generic `CarPlayNavigationPatch.jar`. Do not install both at once.
