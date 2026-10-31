# Package D: CarPlay track title and artist on the AID

[Polska wersja: README.pl.md](README.pl.md)

Status: **works in the car (MU1161 + AID 791, October 2026).** JAR: `build/np-mu1161-v2/pmcp-np.jar` (17,928 B, `6b638868…dc23`;
v2 2026-10-22: all 4 helper calls guarded by `buildtools/Guard.java`, J9 API check `RefCheck`;
v1 `1af4d5e8…761b`).

## Why the factory code shows only "Apple CarPlay"

- The CarPlay ASL target (`HsmTarget`) subscribes to DSI attributes `{8,7,8,2,9,12}`, **without 3** (`ATTR_NOWPLAYINGDATA`).
  The HMI never gets the title at all, although the iPhone sends it (iAP2 NowPlaying works in the factory code).
- BAP AudioSD `CurrentStationInfo.setStationInfoForMirrorLink()` sends only `primaryInformation = "Apple CarPlay"` to the cluster.

## How it works

Three ASM hooks in the factory MU1161 classes (`patcher/PatchNp.java`, each with an assertion on the pattern and the number of matches):

| Class.method | Hook |
|---|---|
| `HsmTarget.initializeDSI` | after the factory `dsiCarplay.setNotification(...)`: `NowPlaying.attach(dsiCarplay)` registers **its own** listener for attribute 3 |
| `CurrentStationInfo.init` / `uninitialize` | `NowPlaying.register(this)` / `unregister(this)` |
| `CurrentStationInfo.setStationInfoForMirrorLink` | at entry: with CarPlay (connection type 2) and a known title it fills in the title (type 72), artist (73), album (74) and returns; otherwise the factory code runs |

Checked in the sources:
- **The reflection of ASL targets is generated when the firmware is built** (`ModuleReflectionFactory`), so we do not add a method to `HsmTarget`.
  Instead, a plain class implements `DSICarplayListener`; the DSI dispatch casts the listener to the interface and calls the method directly.
- `DSIProxyTarget` keeps the attribute mask **separately for each listener**, so our listener does not change what the HMI gets.
  A new listener gets the current value from the cache right away (`NotificationDatapool.getAvailable`).
- A track change reaches the BAP thread through the factory `ThreadSwitchingService.enqueue(Runnable)` (as in `ASLDataPoolAdapter`),
  which calls `CurrentStationInfo.process(-1)`.
- Field types 72/73/74 as in the factory `setStationInfoForMediaExternalDevice` / `setArtistAndAlbum`.

Every hook catches its own exceptions: an error here leaves the factory "Apple CarPlay" and does not break CarPlay or the cluster.
The title is cut to 80 characters. AA and MirrorLink stay factory.

## Building

```sh
ASM_DIR=upstream/tools/jxe2jar/repo/tools/uninline/lib \
  nowplaying/build.sh archives/x-mu1161/jar/lsd-mu1161.jar build/np-mu1161
```

Result: ASM verifier OK, classes at version 46 (the stock `HsmTarget` and `CurrentStationInfo` from the converter are 49; the patcher lowers
them only after checking that there are no class literals), the constants in both classes identical to stock, host test 13/13 (`test/TestNp.java`).

## What we do not know before the car

- whether the cluster shows the second and third line for the "smartphone" source (it does for media);
- whether `ThreadSwitchingService` is ready at the moment of the first track change (if not, the title shows at the next update).

In the installer: Java package `np` (GEM → pmcp → stage B → "Wlacz: Tytul i wykonawca").
