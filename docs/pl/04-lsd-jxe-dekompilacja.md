# lsd.jxe K4525 (MU1367): konwersja do JAR, dekompilacja, analiza mapy w AID

Analiza wykonana na obrazie HMI z K4525 (MU1367). Opisane klasy, ID atrybutów i punkty zaczepienia potwierdzono później na MU1161.

Wejście: `archives/x-k4525/stage2/ifs/lsd.jxe` (55,840,541 B, SHA-256 `09167f1d0ae5…a07507a`, tylko odczyt).
Wyjście: `archives/x-k4525/jar/lsd-k4525.jar` i `archives/x-k4525/src/` (cały obraz po Vineflower).
Ścieżki `archives/…` i `upstream/…` to lokalny układ katalogów roboczych (nie są częścią repozytorium). Wszystkie ścieżki źródeł poniżej są względne do `archives/x-k4525/src/`. Numery linii dotyczą wyjścia Vineflower.

## 1. Łańcuch narzędzi

| Krok | Narzędzie | Wersja / źródło | SHA-256 |
|---|---|---|---|
| JXE → JAR | `luka-dev/jxe2jar` (`src/*.py`, następca `moradek/jxe2jar`) | git `9eeb45bbf14bf8afe3452c7be96a4d1f0206a286` (2026-09-30), `upstream/tools/jxe2jar/repo` | `jxe2jar.py` `9f56143a…5b7c9`, `jxe.py` `82dd48ee…89039`, `bytecode.py` `ed6587a6…bb4`, `constpool.py` `66da7ba7…34a4`, `common.py` `be0371b8…c6db`, `bitstring.py` `04daec6b…cee0` |
| Wrapper | [`scripts/jxe2jar_run.py`](../../scripts/jxe2jar_run.py) (nasz) | uruchamia konwerter pod `python3 -I`, `--check` liczy klasy | `a375a37e…450a` |
| Dekompilator | Vineflower 1.12.0, Maven Central `https://repo1.maven.org/maven2/org/vineflower/vineflower/1.12.0/vineflower-1.12.0.jar` (SHA-1 zgodny z `.sha1`) | `upstream/tools/vineflower/` | `1dfcfe974395734fa467ce620661c7623d05ba83670de0529b1fbd63ff548b9d` |
| Dekompilator awaryjny | CFR 0.152, `https://repo1.maven.org/maven2/org/benf/cfr/0.152/cfr-0.152.jar` | `upstream/tools/cfr/` | `f686e8f3ded377d7bc87d216a90e9e9512df4156e75b06c655a16648ae8765b2` |
| JVM | OpenJDK 25.0.2 (sdkman) | | |

Bezpieczeństwo: kod konwertera przejrzany przed uruchomieniem. Używa tylko stdlib (`struct`, `io`, `zipfile`, `argparse`, `os.makedirs`), bez sieci i bez `subprocess`.
Uruchomiony pod `python3 -I` z cwd `/tmp`, a katalog `src` dodany jawnie do `sys.path`, bo `-I` go nie dodaje.
Jary `.jar` w repo (vineflower, cfr, jd-cli) **nie** były uruchamiane. Vineflower pobrany osobno ma ten sam hash co kopia w repo.

Polecenia:

```sh
python3 -I scripts/jxe2jar_run.py upstream/tools/jxe2jar/repo/src archives/x-k4525/stage2/ifs/lsd.jxe archives/x-k4525/jar/lsd-k4525.jar
java -Xmx14g -jar upstream/tools/vineflower/vineflower-1.12.0.jar --decompile-java4=true --remove-synthetic=true \
     --variable-renaming=jad --ignore-invalid-bytecode=true … archives/x-k4525/jar/lsd-k4525.jar archives/x-k4525/src
```

Opcje Vineflower odpowiadają `tools/vineflower.sh` z repo jxe2jar, bez `--include-runtime`, bo JAR zawiera własne `java.*`.

### Walidacja

| Kryterium | Wynik |
|---|---|
| Klasy w ROM (`class_count` w nagłówku) | 26,291 |
| Klasy zapisane do JAR | **26,291**, 0 „bad class”, 0 złych magic. Wersje klas: 46 (21,646) i 49 (4,645) |
| Porównanie z maximem | MU1439: 28,528 klas. K4525 jest starszy i mniejszy, więc rząd wielkości się zgadza |
| `lsd-k4525.jar` | 125,024,329 B, SHA-256 `f996e81650e9d748a4d6d3d072f1739bbd718d7b55a27dc9acb80b21b5ec1a2b`, 26,404 wpisy (klasy + zasoby z JXE) |
| `javap -p -c` | OK na `GfxStreamSinkController`, `NavigationHandler`, `ChangeDataRate`, `java.lang.String` (poprawny bytecode, stałe, wywołania) |
| Vineflower | 22,377 plików `.java` (klasy wewnętrzne zostały wbudowane), 162 MB. **1** metoda nie zdekompilowała się: `com/ibm/oti/util/DefaultPolicy#loadKeystore` (nieistotna) |
| Jakość | kod czytelny. Stałe `static final` są wklejone jako literały (np. `2110010`), a nazwy zmiennych lokalnych to `i, j, flag` (romizer je usunął) |

Uwaga praktyczna: niektóre wrappery `grep` pomijają pliki binarne. Do `.class` używaj `/usr/bin/grep -a`.

## 2. Strumień mapy do AID przez MOST (`de/vw/mib/asl/internal/mostkombi/streamsink/**`)

### Architektura

- `GfxStreamSinkController` (target `1490002`, `controller/GfxStreamSinkController.java:50`) to HSM. Rejestruje usługę `5000001` (`:93`).
- `StreamSinkCategoryManager#createCategories` (`controller/StreamSinkCategoryManager.java:47`) tworzy 5 use-case’ów. Dostarcza też adaptery `DisplayManagementAdapter`, `NavigationMapAdapter`, `NavInfoAdapter`, `AdaptationAdapter`.
- Stany: `InitializeState` → `WaitForServices` → `RunningState` (`states/StreamSinkHsmContext.java`).
- Sekwencje (`StreamSinkSequence`) idą krokami. Każdy krok ma timeout 15 s (`TIMER_WAIT_FOR_STEP_TO_EXECUTE`). Po timeoucie wołane jest `sequenceStepFailed`, a sekwencja przechodzi dalej.

ID use-case’ów (`common/api/MostKombiIdentifier.java`):

| ID | Klasa | Rola |
|---|---|---|
| 1490004 / 05 | `ChangeDataRate` / `ChangeDataRateSequence` | przenosi data rate żądany przez kombi na DisplayManager |
| 1490006 / 07 | `SwitchToPermanentMap` / `…Sequence` | kombi bez przełączania mapy (mapa stale w AID) |
| 1490009 | `MostUnlockUseCase` | sink zniknął: mapa niewidoczna, rate 0 |
| 1490010 / 11 | `SwitchMapFromABTToKombi` / `…Sequence` | przeniesienie mapy z ekranu centralnego (ABT) do AID |
| 1490012 / 13 | `SwitchMapFromKombiToABT` / `…Sequence` | przeniesienie z powrotem |
| 1490031 | `mostkombi/navinfo/functions/RouteGuidanceMode` | `DSIKOMONavInfo.setRgSelect(mode)` |

### DSI i stałe

`org.dsi.ifc.komogfxstreamsink.DSIKOMOGfxStreamSink` (v2.11.2):

| Element | Wartości |
|---|---|
| Metody | `setFGLayer(int)`, `fadeIn(int,int,int)`, `fadeOut(int)` |
| Atrybuty | `ATTR_GFXSTATE=1` (0 = niedostępny, 1 = dostępny), `ATTR_REQUESTSYNC=2`, **`ATTR_DATARATE=3`** (`OFF=0`, `REDUCEDBANDWIDTH=1`, `FULL=2`) |
| Warstwa `FGREFPIC` | `EMPTY=0`, `KDK=1`, `EV=2`, `MAP=3` |
| `FADESPEED` | `BLIT=0`, `FADE=1` |
| Listener | `updateGfxState`, `updateDataRate(rate, validity)`, `setFGLayerResult`, `fadeInResult`, `fadeOutResult` |

`DSIDisplayManagement` (obsługiwany przez `de/vw/mib/asl/framework/internal/displaymanagement/ASLDisplayManagementKomonavTarget.java`, target 1120002):

| Zdarzenie / callback | Działanie |
|---|---|
| Event `1075841828` `SWITCH_TO_KOMBI_DISPLAY_CONTEXT` | przy pierwszym razie `setDisplayType(4 = DISPLAYID_CLUSTER, 2 = DISPLAYTYPE_H264_MOST)`, potem `switchContext(ctx, 4, 0)`. Kontekst mapy = **70** |
| Event `1075841829` `SET_DATA_FRAME_RATE` | `setUpdateRate(4, rate)`. Rate w ASL: `OFF=0`, `REDUCED=1`, `FULL=10` (`DisplayManagement.java`) |
| `dsiDisplayManagementActiveContext` (`:22`) | datapool `2110010` `KOMBI_DISPLAY` (−2 nie wystartował, −1 brak kontekstu, 70 mapa) |
| `dsiDisplayManagementSetUpdateRateResult` (`:36`) | datapool `2110011` `DATA_FRAME_RATE` |
| Event `4300080` | datapool `2110014` `MOST_CAPABILITY_FOR_MAP` i `2110015` `…_FOR_KDK` |
| Event `4300081` | datapool `2110016..18` (obrazki: cover, call, station) |

### Logika

- `WaitForServices#_checkServiceStates` (`states/WaitForServices.java:99`) przechodzi do `Running`, gdy spełnione są **wszystkie** warunki:
  - `gfxState==1`;
  - `KombiDisplay != −2`;
  - `MostCapabilityForMap == 2` (MOST streaming);
  - `KombiMapStatus == 2` (READY) **albo** (map-switch obsługiwany i nawigacja w pełni działa i `ICMapServiceState == 10`).
- `RunningState#stateStart` (`states/RunningState.java:89`):
  - bez map-switch: `SwitchToPermanentMap`;
  - jest map-switch, a mapa w trakcie przenoszenia do kombi lub `RouteGuidanceMode == 3` (MAP): `ABT→Kombi`;
  - w pozostałych przypadkach: `ChangeDataRate`.
- `RunningState#updateNavInfo`:
  - BAP NavSD `ActiveRgType` (fct 39) == 3 (MAP), gdy mapa jest w ABT: `ABT→Kombi`;
  - `!= 3`, gdy mapa jest w kombi: `Kombi→ABT`.
- `ChangeDataRate#dsiKOMOGfxStreamSinkUpdateDataRate` (`usecases/ChangeDataRate.java:207`): **kombi (sink) decyduje o data rate**. HMI wykonuje wtedy `ChangeDataRateSequence`:
  1. `_stepVisibleChange` (`:182`): rate 0 lub 1 → `setMapInvisible()` (event `1074841846`); rate 2 → `setMapVisible()` (event `1074841845`);
  2. `_stepChangeDataRate` (`:201`): 0 → 0, 1 → 1, 2 → **10** (`setDataFrameRate`).
- `SwitchToPermanentMapSequence#executeNextStep` (`:149`), kroki:
  1. `fadeOut(1)`;
  2. `switchToKombiDisplayContext(70)`, jeśli `KombiDisplay == −1`;
  3. `RouteGuidanceMode` (`setRgSelect`);
  4. `ChangeDataRate`;
  5. `setFGLayer(3 = MAP)`;
  6. `fadeIn(1,0,0)`.
- `SwitchMapFromABTToKombiSequence#executeNextStep` (`:221`), kroki:
  1. `setMapSwitchState(5)` (`:234`), potem czekanie na 5;
  2. `fadeOut(1)`;
  3. `setRgSelect`;
  4. czekanie, aż mapa w ABT będzie niewidoczna;
  5. czekanie na `DATARATE ∈ {1,2}`;
  6. `ChangeDataRate`;
  7. `fadeIn`;
  8. `setMapSwitchState(2)`.
- `SwitchMapFromKombiToABTSequence#executeNextStep` (`:278`), kroki:
  1. stan 3;
  2. `fadeOut`;
  3. czekanie na `DATARATE == 0`;
  4. `setDataFrameRate(0)`;
  5. stan 4;
  6. czekanie, aż mapa w ABT będzie widoczna;
  7. stan 1;
  8. `fadeIn`.
- Stany przełączania mapy (`api/navimap/asl/NavigationMap.java`): `0` niedostępny, `1` widoczna w ABT, `2` widoczna w kombi, `3` żądanie przejścia do ABT, `4` ABT pokazuje mapę, `5` przełączanie do kombi.
- `MostUnlockUseCase#executeSequence` (`:59`): `setMapInvisible()` i `setDataFrameRate(0)`. Wołane, gdy `GfxState` spadnie do 0.

### Rozdzielczość, obszar widoku, kodowanie (poza pakietem streamsink)

| Źródło | Wartość |
|---|---|
| Kodowanie „Dashboard display config” (`DashboardDisplayConfigSetter`) | **1172**: transmisja mapy (`0` off, `1` MOST high, **`2` MOST streaming**, `3` LVDS FPK; `isFpkOverLVDS = (1172 == 3)`) |
| | **171**: kompresja (`1` H.264). `isFPKMapAvailable = (1172 == 2 && 171 == 1)` |
| | **1173**: KDK |
| | **1176**: `isNavMapSwitch` (datapool `1610050`, flaga `ASL.Configuration.isNavMapSwitch`) |
| | **172**: klasa rozdzielczości MapViewer 3 (kombi) |
| `AdaptationAdapter#isNavigationMapSwitchSupported` (`common/api/adaption/AdaptationAdapter.java:49`) | datapool `1110170` **lub** feature flag `140` |
| Viewport MapViewer instancji 3 (kombi) | `DSIMapViewerStatusTarget#mapViewerReady3Configure` (`navigation/map/dsi/factories/impl/mapviewer/status/DSIMapViewerStatusTarget.java:415`), według kodowania 172: |
| | `0` → `800×480` (`SCREEN_VIEW_PORT_MAP_KOMBI`) |
| | `1` → `800×298` (`…_KOMBI_CHN`) |
| | **`2` → `1010×376`** (`…_KOMBI_FPK_ENTRY_HIGH`, `:32`) |
| | potem `setFrameRateMode(5 = LIMITED_CLUSTER_INSTRUMENT)` |
| Mapa główna, gdy mapa jest w kombi (`mapViewerReady0`, `:339`) | max `1010×480` (`FPK_ENTRY_STD`), viewport `1010×376` |
| Pozycja auta / hotpoint w AID (`MapViewerKombiTargetHSM#getCarPosition`, `:197`) | klasa 2: `(505,188)` north-up, `(505,249)` heading-up. Klasa 0: `(400,248/353)`. Klasa 1: `(400,154/250)` |
| Zoom area w AID (`ASLNavigationMapConfiguration`, `:46-62`) | `ZOOM_AREA_DEFAULT_FPK_ENTRY 1010×376` |
| | `2D3D (368,111,274,194)` |
| | `OVERVIEW (354,105,302,244)` |
| | `FPK_ENTRY_RESOLUTION_CLASS = 2` |

**Wniosek:** HMI rysuje mapę dla AID jako osobną instancję MapViewer nr 3 (`DSIMapViewerManager#createMapViewerKombi`, `:183`, `createMapViewer(…, 3)`). Dla AID w wersji „FPK entry high” jest to **1010×376 px**. Kodowanie wysyła ją jako H.264 przez MOST (`DISPLAYTYPE_H264_MOST`), w kontekście DisplayManagera 70.
W Javie nie ma enkodera ani parametrów bitrate. Znajduje się w nim tylko poziom „update rate” 0/1/10 (OFF/REDUCED/FULL).

## 3. Rozmiar AID (small/large) i wykrywanie layoutu

- `ConfigurationManager.INSTRUMENTCLUSTER_SIZE_SMALL=0`, `_LARGE=1` (`de/vw/mib/configuration/ConfigurationManager.java:37`). Reprezentacje to `"IC_Size_Small"`, `"IC_Size_Large"` (`ConfigurationManagerImpl.java:136`).
- `ConfigurationManagerImpl#setInstrumentClusterSize` (`:1066`) przyjmuje tylko 0 lub 1. Przy zmianie woła `notifyNvListener(4 = NV_INSTRUMENTCLUSTERSIZE)`.
- **Źródło wartości:** BAP LSG **SDS_SD**, funkcja **16 `ASG_Capabilities`**, pole `displaySizeClass`: `0` SMALL, `1` MEDIUM, `2` LARGE (`bap/mqbab2/generated/sdssd/serializer/ASG_Capabilities_SetGet.java`).
  - `sdssd/functions/ASGCapabilities#setGetProperty` (`:60`): kombi wysyła SetGet, a `displaySizeChanged` (`:109`) zapisuje wartość w persystencji `SDSSD_ASGCapabilities` (`instrumentcluster/persistence`, domyślnie 1) i woła `ConfigurationAdapter#setInstrumentClusterDisplaySize`.
  - Mapowanie BAP→system (`ConfigurationAdapter.java:177`): 0 → 0, a 1 i 2 → 1.
- **Jedyny konsument** `NV_INSTRUMENTCLUSTERSIZE` to `ScaledI18nDatapoolUpdater` (`de/vw/mib/datapool/internal/ScaledI18nDatapoolUpdater.java:49-66`). Ładuje on teksty zależne od rozmiaru (`<lang>-<size>.res`, tag `"de_DE-1"`). `ConfigurationAdapter#notifyNvListener` wywołuje tylko `languageChanged()`.
  - **Rozmiar nie wpływa na mapę ani na strumień.** To klasa wielkości wyświetlacza kombi (krótkie lub długie teksty), a nie przełączenie zegarów.
- **Zdarzenie „kierowca zmienia widok w AID”** nie ma osobnego eventu „small/large dials”. Są dwa sygnały:
  1. MOST `DSIKOMOGfxStreamSinkListener.updateDataRate` (`ATTR_DATARATE`). AID żąda `FULL`, gdy mapa jest widoczna w wybranym layoucie, a `OFF` lub `REDUCED`, gdy nie jest. Obsługa: `ChangeDataRate#dsiKOMOGfxStreamSinkUpdateDataRate`.
  2. BAP NavSD **fct 39 `ActiveRgType`** SetGet z kombi (`bap/mqbab2/navsd/functions/ActiveRgType.java:97`). `rgtype`: `0` RGI (strzałki z ManeuverDescriptor), `1` MOST KDK, `2` kompas, `3` MOST MAP, `4/5` LVDS map/KDK, `255` domyślny.
     - Przy map-switch przyjmowany tylko w stanach 0, 1 i 2.
     - `mostkombi/navinfo/api/navi/NavInfoAdapter#_storeBapInfoData` (`:323`, `case 39` `:369`) obserwuje BAP LCU 50 i przekłada wartość na `RouteGuidanceMode` (`RGMODE_RGI=0`, `KDK=1`, `COMPASS=2`, `MAP=3`). Ta wartość steruje przełączaniem ABT/Kombi w `RunningState#updateNavInfo` i jest odsyłana przez `DSIKOMONavInfo.setRgSelect`.
- `ActiveRgType#setCurrentRGType` (`:150`): bez funkcji map-switch zwraca `rgtype = 3`, gdy `KombiMapStatus != 0`, a w przeciwnym razie ostatnią wartość.

## 4. CarPlay (`de/vw/mib/asl/internal/carplay/**`)

- `generated/de/vw/mib/asl/internal/carplay/ic/ASLCarPlayICDeviceImpl` (`"CarPlay.IC"`, target **13904**) to tylko urządzenie modelu (dane dla widoku HMI kombi), bez logiki.
  - Właściwości: `ROUTE_GUIDANCE_ACTIVE = 2910009`, `PHONE_CALL_PRESENT = 2910010`.
  - Lista `2910011` `DeviceState`: siła sygnału 0..5, operator, `valid`.
  - **Nie ma tu strumienia wideo ani danych manewrów.**
- `common/NavigationHandler#updateGuidanceActive` (`:17`), listener nawigacji HMI:
  - natywne prowadzenie startuje przy podłączonym CarPlay: `DSICarPlay.requestModeChange(resource 0, appState 2)`, czyli HMI przejmuje nawigację;
  - natywne prowadzenie się kończy, a `activeNavigation == 3`: appState 6;
  - na końcu zawsze `CarPlayGlobalProperies#setHmiRouteGuidanceActive(flag)` (`:374`).
- `CarPlayModeHandling` (`:192` i dalej), na podstawie `updateMode` z iPhone’a (`getNavigationType`):
  - `2` (iPhone): `2910009 := true`, `activeNavigation = 2`, natywne prowadzenie zatrzymane przez `navServices.stopGuidance(6)`, potem `ExboxGuidanceListenerImpl#setSmartphoneGuidanceActive`;
  - `3` (HMI): `2910009 := false`;
  - `1` (brak): `2910009 := false`.
- `api/impl/ASLCarplayServicesImpl#isCarPlayRouteGuidanceActive` (`:82`) zwraca `activeNavigation == 2`.
  - Konsumuje to BAP: `bap/mqbab2/navsd/functions/InfoStates#getCurrentBAPInfoState` (`:70`). Gdy CarPlay, AA lub CarLife prowadzi, NavSD **fct 38 `InfoStates` = 6 `NAVIGATION_IN_MOBILE_DEVICE_ACTIVE`**.
  - `NavigationASLDataAdapter#isGALRouteGuidanceActive` (`:223`) czyta `2910009`.
- `common/ExboxGuidanceListenerImpl` jest mostem do exboxm (§5). Gdy exbox zgłasza ACTIVE: `updateGuidanceActive(true)` i odpowiedź „smartphone INACTIVE”.
- `DSICarPlay` / `DSICarPlayListener` (`org/dsi/ifc/carplay`) **nie ma żadnych callbacków route guidance** (tylko mode, call, now-playing, cover art).
  - `ServiceConfiguration` ma jeden ekran (`xResolution`, `yResolution`, offset, `physicalDisplay*`), bez alt-screen dla kombi.
  - Kanwa CarPlay: `ASLHandler` (`:443`), z kodowania `getLayoutCarplayCanvasDimensionWidth/Height`.

## 5. exboxm guidance (`de/vw/mib/asl/api/exboxm/guidance/**`)

- API: `ExboxGuidanceManager { addListener, removeListener, getGuidanceState, changeSmartphoneGuidanceStateTo(GuidanceState) }`, `GuidanceState { INACTIVE=0, ACTIVE=1 }`, `ExboxGuidanceListener#onExboxGuidanceStateChanged`.
- Implementacja: `internal/exboxm/api/impl/guidance/ExboxGuidanceManagerImpl` i `internal/exboxm/state/ExboxStateServiceImpl`.
  - Stan exboxa pochodzi z `DSIExBoxMListener.updateMobileDeviceLinkStatus(…, ExBoxState.isExBoxNavigationActive())` (`:221`).
  - Stan smartfona trafia do `DSIExBoxM.setMobileDeviceLink(MobileDeviceLinkStatus)` (`:245-258`).
- **To wyłącznie arbitraż „kto prowadzi” (exbox = zewnętrzny moduł nawigacji, np. KOR/CHN, czy smartfon).** API nie przenosi manewrów, dystansu, ulic, pasów ani ETA. Do wstrzykiwania TBT się nie nadaje.

### Właściwa droga TBT do kombi: BAP NavSD zasilane z list ASL

Funkcje BAP NavSD (`bap/mqbab2/navsd/functions/*`) czytają `NavigationService` (`common/api/navigation/NavigationASLDataAdapter`). Ten z kolei czyta właściwości i listy ASL:

| BAP NavSD fct | Klasa | Źródło ASL | Kto zapisuje (natywnie) |
|---|---|---|---|
| 17 `RG_Status` | `RGStatus#setRouteGuidanceStatus` (`:49`) | prop `733` (status nawigacji, musi być 0), prop **`732`** (0 brak, 1 aktywne, 2 liczenie) | `navigation/bap/HsmTargetBap` (`:190-215`, event `3497006`) |
| 18 `DistanceToNextManeuver` | `DistanceToNextManeuver` | lista **741** (dystans, jednostka, bargraf on/off, bargraf %) i 751; wymaga `732 == 1` | `ASLNavBAPAPI#updateBapDistanceToNextManeuver` |
| 20 `TurnToInfo` | `TurnToInfo#setTurnToInfoStatusData` | lista **744** (ulica, drogowskaz) | `ASLNavBAPAPI#updateBapTurnToInfo` |
| 21 `DistanceToDestination` | | lista **749** | `ASLNavBAPAPI#updateBapDistanceToDestination` |
| 22 TimeToDestination / RTT | | listy **750**, **1110060** | `ASLNavBAPAPI#updateBapTimeToDestination2`, `…RTTandETA` |
| 23 `ManeuverDescriptor` | `ManeuverDescriptor#computeManeuverDescriptorStatus` (`:217`, tylko gdy `732 != 0`) | lista **751** (`mainElement`, `direction`, `zLevel`, `sideStreets`) | **prywatne** `HsmTargetBap#updateManeuverDescriptor` (`:342`), też do listy 838 |
| 24 `LaneGuidance` | `LaneGuidance` | lista **742** (`direction`, `sideStreets`, `laneType`, `markingL/R`, `description`, `guidanceInfo`), prop 731 | `ASLNavBAPAPI#updateBapLaneGuidance` |
| 38 `InfoStates` | `InfoStates` | 733, 734, `isCarPlayRouteGuidanceActive` | → 6 przy CarPlay |

- Punkt wejścia: `de.vw.mib.asl.api.navbap.ASLNavBAPFactory.getNavBAPApi()` (singleton `ASLNavBAPAPIImpl`). Metody publiczne:
  - `updateBapDistanceToNextManeuver(int dist, int unit, boolean bargraphOn, int bargraph%)`;
  - `updateBapTurnToInfo(String street, String signPost)`;
  - `updateBapLaneGuidance(INavLaneGuidanceDataNavBap[], boolean)`;
  - `updateBapDistanceToDestination(int, int, boolean)`;
  - `updateBapTimeToDestination2(h, m, k)`;
  - `updateBapTimeToDestinationRTTandETA(long, long)`;
  - `updateBapCompassInfo`.
- Brak publicznej metody dla ManeuverDescriptor i `732`. Trzeba wołać bezpośrednio `generated.de.vw.mib.asl.internal.ListManager.getGenericASLList(751).updateList(GenericCollector[])` (kolumny 0..3 jak w `HsmTargetBap:342-380`) oraz `ServiceManager.aslPropertyManager.valueChangedInteger(732, 1)`.
- Precedens syntetycznego manewru: `HsmTargetBap` `case 100100` (`:143`, tryb WPM/offroad) buduje `new BapManeuverDescriptor(6, direction, 0, null)`.
- `mainElement` (`ManeuverDescriptor_Status.MAIN_ELEMENT_*`), m.in.: `11` follow street, `13` turn, `15/16` exit R/L, `19/20` fork, `21..27` rondo, `25` U-turn, `3` arrived. Mapowanie `32→15` i `33→16` (`ManeuverDescriptor#mapToBAPMainElement`).
- Ten sam strumień BAP (LCU 50: fct 18, 19, 20, 21, 39) jest równolegle kopiowany na MOST `DSIKOMONavInfo` przez `NavInfoAdapter`. Wstrzyknięcie w listy ASL zasila więc też MOST NavInfo.
- Android Auto i CarLife mają callbacki next-turn: `AndroidAutoTarget#dsiAndroidAuto2UpdateNavigationNextTurnEvent` (`:479`), `carlife/DSIHandler#handleDsiCarlifeUpdateNavigationNextTurnInfo` (`:95`). Są to puste stuby (tylko trace), czyli gotowe miejsca na podpięcie. **CarPlay nie ma takiego callbacku w DSI.**

## 6. Punkty zaczepienia

### (a) Przełączanie layoutu AID i mapy

| Hook | Co daje |
|---|---|
| `streamsink/usecases/ChangeDataRate#dsiKOMOGfxStreamSinkUpdateDataRate(int rate, int valid)` | jedyne żywe zdarzenie „AID chce lub nie chce mapy” (FULL / REDUCED / OFF). Dobry wyzwalacz start/stop naszego strumienia |
| `ChangeDataRateSequence#_stepChangeDataRate` / `DisplayManagementAdapter#setDataFrameRate` (event `1075841829`) | miejsce, w którym HMI przełącza DisplayManager (`setUpdateRate(4, 0/1/10)`) |
| `ASLDisplayManagementKomonavTarget#gotEvent` `case 1075841828` | `setDisplayType(4, H264_MOST)` + `switchContext(70, 4, 0)`: wybór, co idzie do kombi. Tu można podmienić źródło (np. kontekst z wideo CarPlay zamiast MapViewer 3) |
| `SwitchToPermanentMapSequence` krok `setFGLayer(3)` / `fadeIn` | warstwa i przejścia w AID |
| `bap/mqbab2/navsd/functions/ActiveRgType#setGetProperty` + `NavInfoAdapter case 39` | wybór widoku nawigacji w AID (RGI, kompas, mapa) |
| `DSIMapViewerStatusTarget#mapViewerReady3Configure` (kodowanie 172) | rozmiar renderu dla AID (1010×376). Docelowa rozdzielczość, jeśli podstawiamy własny obraz |
| `ConfigurationManagerImpl#setInstrumentClusterSize` / `NvListener(4)` | **nie** layout zegarów, tylko klasa tekstów. Niska wartość dla moda |

### (b) Natywne wstrzyknięcie prowadzenia (TBT do widgetów BAP NavSD)

Stan: ta droga jest zrealizowana w paczce E „System RG” i JAR-ze [`rg/`](../../rg/README.pl.md) (port rozwiązania tomasz-twardzicki) i działa w aucie: natywna strzałka, dystans i czas do celu na AID.

1. Źródło danych: CarPlay RGI z iAP2 (natywnie `ipod-drvr-iap2` / `mm-ipod`, jak u maxima i harman-f), bo `DSICarPlay` go nie dostarcza.
2. Wstrzyknięcie w Javie (w kontekście wątku ASL, np. przez `ThreadSwitchingService`):
   - `ServiceManager.aslPropertyManager.valueChangedInteger(732, 1)` (RG aktywne);
   - `ListManager.getGenericASLList(751).updateList(...)` (manewr);
   - `ASLNavBAPFactory.getNavBAPApi().updateBapDistanceToNextManeuver(...)`, `.updateBapTurnToInfo(street, sign)`, `.updateBapLaneGuidance(...)`, `.updateBapDistanceToDestination(...)`, `.updateBapTimeToDestinationRTTandETA(...)`.
3. Konflikty do obejścia:
   - `CarPlayModeHandling` przy nawigacji iPhone’a woła `navServices.stopGuidance(6)` i ustawia `2910009 = true`, przez co `InfoStates` zmienia się na 6. AID może wtedy pokazać ekran „nawigacja w urządzeniu” zamiast strzałek. Potrzebny patch `InfoStates#getCurrentBAPInfoState` albo `ASLCarplayServicesImpl#isCarPlayRouteGuidanceActive`. W praktyce rozwiązuje to [NavActiveIgnore](../../navactiveignore/README.pl.md): gdy prowadzi CarPlay, `CarPlayModeHandling` nie ustawia `2910009`, nie woła `setActiveNavigation(2)` ani `stopGuidance(6)`.
   - `HsmTargetBap` (event `3497006`) i native DSI navigation nadpisują 732, 751, 741 i 744, gdy natywna nawigacja coś raportuje. Trzeba je wyciszyć lub gatingować flagą.
   - Natywnie `RGStatus` wymaga `733 == 0` (nawigacja OK).
4. Alternatywa niskiego ryzyka: wypełnić puste stuby `AndroidAutoTarget#dsiAndroidAuto2UpdateNavigationNextTurnEvent` i analogicznie dla CarPlay. Wymaga własnego źródła DSI.

## 7. Otwarte pytania

- Czy w Passacie B8 AID kodowanie 1172 = 2 (MOST streaming), a 172 = 2 (1010×376)? Sprawdzić w adaptacji 5F (Dashboard display config) lub w logu `DSIMapViewerStatusTarget` („adaption api value for the resolution of MapViewer 3”).
- Jak AID reaguje na `InfoStates = 6` przy jednoczesnym `RG_Status = 1` i niepustym ManeuverDescriptor: pokaże strzałki czy ekran „telefon”?
  - **Odpowiedziane:** z NavActiveIgnore i paczką E „System RG” AID pokazuje w aucie natywną strzałkę oraz dystans i czas do celu podczas prowadzenia z iPhone’a.
- Kontekst DisplayManagera 70 i enkoder H.264 (bitrate, GOP) są natywne (`DisplayManager` / `dio_manager`), nie w Javie. Trzeba ustalić, czy da się podać inne źródło niż MapViewer 3 (np. wideo CarPlay) bez zmian natywnych.
  - **Odpowiedziane inną drogą:** mapa CarPlay trafia do AID natywnym strumieniem kombi CarPlay (łatki `core.so` w [`patches/mu1161/`](../../patches/mu1161/)), bez zmian w Javie.
- Czy AID wysyła `ASG_Capabilities.displaySizeClass` także przy zmianie widoku zegarów, czy tylko przy starcie? Kod HMI obsługuje oba przypadki, ale skutkiem jest wyłącznie zestaw tekstów.
- Kto ustawia datapool `1110170` (map-switch supported) poza flagą 140 i jaka jest jego wartość w B8?
- Brak ID wątków i synchronizacji dla wywołań `ListManager` spoza HSM. Do sprawdzenia przed patchem.
