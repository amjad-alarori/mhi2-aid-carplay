# Paczka E: natywne prowadzenie (port tomasz-twardzicki MU1427 v1.2.0 na MU1161)

[English version: README.md](README.md)

Stan: **działa w aucie (MU1161 + AID 791, październik 2026): ETA, dystans do celu i strzałka manewru (po ruszeniu).** Autor rozwiązania: tomasz-twardzicki (GPL-3.0-or-later),
dekoder wg luka-dev; baza mapy: omonob. Źródła: `upstream/tomasz` @ `024dd159`.

Daje na AID (wg Tomasza, sprawdzone w jego aucie na MU1427/791):
- strzałki i dystans do manewru w widoku „strzałki” i na HUD;
- dystans i czas do celu na pasku nad mapą.

## Składniki

| Plik | Skąd | SHA-256 | Gdzie w radiu |
|---|---|---|---|
| `ipod-drvr-iap2.so` (743,196 B) | łańcuch łatek Tomasza na **naszym** sterowniku | `76926bde…1b48` | `/mnt/app/armle/lib/dll/` |
| `iap2.cfg` (6,079 B) | **nasz** fabryczny + jego `[ident]` | `c61407d9…b491` | `/mnt/system/etc/mm/` |
| `rgi-observer` (16,606 B) | jego binarka (źródło `release/reader.c`) | `b683cef7…08ac` | `/mnt/app/carplaymaps/rg/` |
| `pmcp-rg.jar` (34,082 B, v2) | jego `PatchLive` na **naszych** klasach NavSD + jego helpery, potem nasz `patcher/GuardLive.java` (każde wywołanie `LiveBridge` osłonięte) | `717fb53c…a754` | `/mnt/app/eso/hmi/lsd/jars/` |

## Dowody zgodności

1. **Sterownik:** nasz fabryczny `ipod-drvr-iap2.so` (`7149a3e7…`) po podstawieniu bloku usage z MU1427 (0xae3f0–0xae48f:
   DATE, wersja `61.1`/`61.4`, TAGID, CRC debuglink) ma **dokładnie** hash fabrycznego sterownika MU1427 (`0ac13f43…`).
   Kod jest więc bajtowo ten sam.
2. Łańcuch Tomasza (`patch-driver.py` → `patch-publication.py` → `patch-activation.py`, clang ARM + pyelftools 0.31) na tym
   pliku odtwarza **bit w bit** jego wydany sterownik `3760797a…`.
3. Nasz wynik = jego wynik z naszym blokiem usage. Różnice względem naszego stocku: nagłówek programu ELF (0x94–0xb1),
   6 hooków (0x63f0, 0x909c, 0x9260, 0xe138, 0x10ba8, 0x133a0), dopisany kod (3,271 B). Sprawdzane automatycznie w `build.sh`.
4. **JAR:** 5 z 6 klas NavSD MU1161 = MU1427 bajtowo, `LaneGuidance` = MU1427 + jedna poprawka serializacji (hook na wejściu
   metody pasuje). `PatchLive` przeszedł wszystkie swoje asercje, a jego `TestLive` na naszych klasach: **123 asercje OK** (jak u niego).
5. **Czytnik:** importuje tylko `libc.so.3`. Wszystkie 43 silne importy są w libc K4525 (`485e2a50…`, wyjęta z `mifs-stage1` K4525).
   3 słabe (`_Jv_RegisterClasses`, `__register_frame_info`, `__deregister_frame_info`) to kod startowy kompilatora.
   Libc MU1161 nie mamy (backup bez stage1). **Potwierdzi dopiero radio.**

## Instalacja (przyciski GEM, etap B)

1. „System RG: wlacz”: zapisuje fabryczny sterownik i cfg w `carplaymaps/rollback/` (hash), podmienia sterownik i cfg
   (remount `/mnt/app` i `/mnt/system`), instaluje czytnik, na końcu znacznik `rg/SYSTEM_ON`.
   Nie dotyka HMI; najgorszy skutek: problem z CarPlay/iPod, „System RG: wylacz” albo „Przywroc” to cofa.
2. „Wlacz: Prowadzenie” (paczka Java `rg`): JAR przez mechanizm Java z próbnym startem.
3. Czytnik startuje z naszego bloku `lsd.sh` w tle, tylko gdy jest `SYSTEM_ON` i zestaw Java się ładuje
   (z argumentami Tomasza: `start-live /dev/ipod0/rgi-events /ramdisk/carplay-route-guidance`).

## Różnice wobec Tomasza i rzeczy do zrobienia

- Format czasu: Tomasz wysyła czas do celu. U nas licznik pokazuje godzinę przyjazdu (zdjęcie `IMG_1083`).
  Do zrobienia: respektować `timeInfoType` (audyt A9).
- Jego instalator przyjmuje tylko MU1427. Nasz jest własny (pmcp), z hashami zamiast samych rozmiarów.
- Czytnik działa u niego na MU1427, u nas niesprawdzony.

## Natywne pasy ruchu VW z zawracaniem (pakiet `rglu`, v1.3.0)

Port pasów ruchu Tomasza z MU1367 v1.4.0 (`upstream/tomasz` @ `7925a83`, w aucie u niego działa). Pliki `rg/lanes/stage.py`,
`LaneData.java` i `TestLanes.java` są skopiowane bez zmian i przypięte hashami. `apply_lanes.py` uruchamia jego `stage.guidance()`
na tych samych przypiętych źródłach mostka co `rg`; źródła mostka na `7925a83` są bajt w bajt te same co na `024dd159`.

- Dane: iAP2 RouteGuidanceLaneGuidanceInformation `0x5204` (już w naszym `iap2.cfg` i czytniku). Sterownik, `iap2.cfg` i
  `rgi-observer` bez zmian.
- Do AID przez fabryczny `LaneGuidance.computeFullLaneGuidanceList`: dwa wywołania `getLaneGuidance` -> `laneIterator`,
  `getRouteGuidanceState` -> `descriptorRouteState`, `isSetupLaneGuidanceActive` -> `lanesVisible` (patcher sprawdza 2/1/1;
  nasza klasa ma ten sam układ). Fabryczne okno 6 pasów, ustawienie „pasy ruchu” w menu VW działa dalej.
- `GuardLive ... lanes`: 6 osłoniętych wywołań w `LaneGuidance`; przy błędzie pomocnika `laneIterator` i `lanesVisible`
  wracają do fabrycznych `getLaneGuidance()` / `isSetupLaneGuidanceActive()`.
- Pasy do zawracania: tablica pasów Tomasza nie ma strzałki zawracania. `rg/lanes/uturn.py` (na kopiach roboczych, jego pliki
  zostają bez zmian) mapuje pas do zawracania na symbole pasów VW 114 (w lewo) i 146 (w prawo) i dopisuje te przypadki do
  `TestLanes`. Sprawdzone w aucie (MU1161 + AID 791, 2026-10-31): pas do zawracania ma własną strzałkę.
- Budowa: `rg/build.sh <lsd.jar> <katalog> lanes-uturn` -> `pmcp-rg.jar` `72ab7221…` (38529 B), w paczce jako
  `jars/pmcp-rglu.jar`. `lanes` bez kroku zawracania daje wcześniejszą wersję tylko z pasami (niewydawaną); bez trybu wynik
  jest bajt w bajt bazowym `717fb53c`. Testy: TestLive i TestLanes (na naszych osłoniętych klasach i fabrycznym budowniczym
  tablicy pasów).
- Instalacja: przycisk 3 na karcie 1 instaluje `rglu` (starsza instalacja z `rg` dostaje `rglu` w zamian). W menu
  zaawansowanym `java-on rglu` zastępuje `rg` w zestawie (nowy start próbny), `java-on rg` wraca. Pasy pokażą się tylko, gdy
  aplikacja w telefonie je wysyła i w VW włączone są pasy ruchu.
