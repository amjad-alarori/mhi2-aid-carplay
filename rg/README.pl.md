# Paczka E: natywne prowadzenie (paczka `rg`, port tomasz-twardzicki MU1427 v1.2.0 na MU1161)

[English version: README.md](README.md)

Stan: **działa w aucie (MU1161 + AID 791, październik 2026): ETA, dystans do celu i strzałka manewru (po ruszeniu);
pasy z pasami do zawracania od v1.3.0 (2026-10-31); w v1.4 także strzałka na starcie trasy, nazwa ulicy i pasek odległości
przed manewrem (test w aucie 2026-11-04).** Autor rozwiązania: tomasz-twardzicki (GPL-3.0-or-later), dekoder i nazwy typów
manewrów iAP2 wg luka-dev; tablica manewrów dla strzałek zastępczych: harman-f; baza mapy: omonob.
Źródła: `upstream/tomasz` @ `024dd159` (MU1427), `7925a83` (pasy MU1367 v1.4.0), `1d69473` (MU1367 v1.4.3).

Od v1.4 jest **jedna** paczka Java prowadzenia, `rg`, budowana przez `rg/build.sh <lsd.jar> <katalog> lanes-uturn-asf-m`.
Zawiera wszystko, co niżej: port MU1427, jego pasy, nasze pasy do zawracania, jego pasek odległości / nazwę ulicy /
odzyskiwanie strumienia i strzałki zastępcze. Paczek `rg` (bez pasów) i `rglu` z v1.3 już nie ma; `java-update` (przycisk 3)
zastępuje je, a także eksperymentalne `rglua`, `rgluasf`, `rgluasfa`, `rgluasfm`, `rgluasfma`, tą paczką `rg`.

Daje na AID:
- strzałki i dystans do manewru w widoku „strzałki” i na HUD (także na starcie trasy i przy skrętach na rondzie, zob.
  strzałki zastępcze niżej);
- dystans i czas do celu na pasku nad mapą;
- natywne pasy ruchu VW, także pasy do zawracania (gdy aplikacja w telefonie wysyła pasy, a w VW włączone są pasy ruchu);
- pasek odległości VW (odliczanie) przed manewrem i nazwę bieżącej ulicy.

## Składniki

| Plik | Skąd | SHA-256 | Gdzie w radiu |
|---|---|---|---|
| `ipod-drvr-iap2.so` (743,272 B) | łańcuch łatek Tomasza na **naszym** sterowniku (`76926bde…`, 743,196 B, wydawany w v1.0–v1.3) + nasza bramka logu (`rg/driver/`) | `519ea3c5…` | `/mnt/app/armle/lib/dll/` |
| `iap2.cfg` (6,079 B) | **nasz** fabryczny + jego `[ident]` | `c61407d9…b491` | `/mnt/system/etc/mm/` |
| `rgi-observer` (13,552 B) | nasz czytnik `pmcp-r1` (`rg/reader/reader.c`, pochodny od jego `release/reader.c`), gotowa binarka w `rg/reader/prebuilt/` | `3166df9b…` | `/mnt/app/carplaymaps/rg/` |
| `pmcp-guidance.jar` (47,817 B) | `pmcp-rg.jar` z `rg/build.sh … lanes-uturn-asf-m`: jego `PatchLive` na **naszych** klasach NavSD + jego helpery i funkcje, nasze zmiany, potem nasz `patcher/GuardLive.java` (każde wywołanie `LiveBridge` osłonięte) | `13ca11c4…` | `/mnt/app/eso/hmi/lsd/jars/` |

Do v1.3 czytnikiem była gotowa binarka Tomasza `rgi-observer` (16,606 B, `b683cef7…`), a JAR-em `pmcp-rg.jar`
(`717fb53c…`, bez pasów) albo `pmcp-rglu.jar` (`72ab7221…`, pasy + pasy do zawracania). Bez trybu `rg/build.sh` dalej daje
bajt w bajt bazowy `717fb53c`.

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
5. **Czytnik** (binarka Tomasza, v1.0–v1.3): importuje tylko `libc.so.3`. Wszystkie 43 silne importy są w libc K4525 (`485e2a50…`, wyjęta z `mifs-stage1` K4525).
   3 słabe (`_Jv_RegisterClasses`, `__register_frame_info`, `__deregister_frame_info`) to kod startowy kompilatora.
   Libc MU1161 nie mamy (backup bez stage1); w radiu działał od v1.0.

## Instalacja (przyciski GEM)

Wszystko to robi przycisk 3 na ekranie głównym. Pojedyncze kroki w `pmcp_advanced` → `pmcp_packages`:

1. „Route guidance system on (iAP2 driver, iap2.cfg, reader)”: zapisuje fabryczny sterownik i cfg w `carplaymaps/rollback/`
   (hash), podmienia sterownik i cfg (remount `/mnt/app` i `/mnt/system`), instaluje czytnik, na końcu znacznik
   `rg/SYSTEM_ON`. Nie dotyka HMI; najgorszy skutek: problem z CarPlay/iPod, który cofa „Route guidance system off (factory
   iAP2 driver and iap2.cfg)” albo „Remove everything (back to factory files)”.
2. „On rg: route guidance: arrows, lanes, distance bar, street, ETA (needs Route guidance system)”: JAR przez mechanizm
   Java z próbnym startem.
3. Aktualizacja z wcześniejszej karty: „Route guidance system update (driver and reader of this card, RG stays on)” podmienia
   tylko sterownik v1.0–v1.3 `76926bde…` i czytnik Tomasza `b683cef7…` (kopia robocza, hash, kopie fabryczne zostają;
   wcześniej „Status” pokazuje „Route guidance system: old”). „Java update: packages of an earlier card -> this card's
   (rglu -> rg)” tworzy jeden nowy zestaw, w którym `rg`, `rglu` albo wariant eksperymentalny staje się tą paczką `rg`
   (nowa nazwa pliku JAR, więc stary zestaw zostaje nietknięty, aż przełączy się `HMI_BOOT`; jeden start próbny, potem
   „4. Confirm”).
4. Czytnik startuje z naszego bloku `lsd.sh` w tle, tylko gdy jest `SYSTEM_ON` i zestaw Java się ładuje
   (z argumentami Tomasza: `start-live /dev/ipod0/rgi-events /ramdisk/carplay-route-guidance`).

## Różnice wobec Tomasza i rzeczy do zrobienia

- Format czasu: Tomasz wysyła czas do celu. U nas licznik pokazuje godzinę przyjazdu (zdjęcie `IMG_1083`).
  Do zrobienia: respektować `timeInfoType` (audyt A9).
- Jego instalator przyjmuje tylko MU1427. Nasz jest własny (pmcp), z hashami zamiast samych rozmiarów.
- Jego czytnik kończy się na dobre, gdy odczyt ze sterownika się zawiesi; nasz nie (czytnik `pmcp-r1` niżej).
- Ograniczenie prędkości: prowadzenie iAP2 nie przenosi liczbowego ograniczenia prędkości (badania
  [maxim-smirnov/mhi2-carplay-cluster](https://github.com/maxim-smirnov/mhi2-carplay-cluster) na iOS 26.6/27), więc nie ma
  czego przekazać do licznika VW.

## Natywne pasy ruchu VW z zawracaniem (od v1.3.0)

Port pasów ruchu Tomasza z MU1367 v1.4.0 (`upstream/tomasz` @ `7925a83`, w aucie u niego działa). Pliki `rg/lanes/stage.py`,
`LaneData.java` i `TestLanes.java` są skopiowane bez zmian i przypięte hashami. `apply_lanes.py` uruchamia jego `stage.guidance()`
na tych samych przypiętych źródłach mostka co wersja bazowa; źródła mostka na `7925a83` są bajt w bajt te same co na `024dd159`.

- Dane: iAP2 RouteGuidanceLaneGuidanceInformation `0x5204` (już w naszym `iap2.cfg` i czytniku).
- Do AID przez fabryczny `LaneGuidance.computeFullLaneGuidanceList`: dwa wywołania `getLaneGuidance` -> `laneIterator`,
  `getRouteGuidanceState` -> `descriptorRouteState`, `isSetupLaneGuidanceActive` -> `lanesVisible` (patcher sprawdza 2/1/1;
  nasza klasa ma ten sam układ). Fabryczne okno 6 pasów, ustawienie „pasy ruchu” w menu VW działa dalej.
- `GuardLive ... lanes`: 6 osłoniętych wywołań w `LaneGuidance`; przy błędzie pomocnika `laneIterator` i `lanesVisible`
  wracają do fabrycznych `getLaneGuidance()` / `isSetupLaneGuidanceActive()`.
- Pasy do zawracania: tablica pasów Tomasza nie ma strzałki zawracania. `rg/lanes/uturn.py` (na kopiach roboczych, jego pliki
  zostają bez zmian) mapuje pas do zawracania na symbole pasów VW 114 (w lewo) i 146 (w prawo) i dopisuje te przypadki do
  `TestLanes`. Sprawdzone w aucie (MU1161 + AID 791, 2026-10-31): pas do zawracania ma własną strzałkę.
- Pasy pokażą się tylko, gdy aplikacja w telefonie je wysyła i w VW włączone są pasy ruchu.

## Pasek odległości, nazwa ulicy i odzyskiwanie strumienia (v1.4)

Trzy funkcje z MU1367 v1.4.3 tomasz-twardzicki (`upstream/tomasz` @ `1d69473`, `MU1367/integration/src/guidance`), nałożone
przez `rg/lanes/asf.py` jako liczone zmiany na nasze źródła z pasami i zawracaniem:
- **a**: natywny pasek odległości VW przed manewrem (`ArrowProgress`): okno 200 m, 2000 m dla zjazdów z autostrady
  (typy iAP2 8/22/23), tylko dla fabrycznych elementów głównych `verifiedBapBargraphSetting`.
- **s**: bieżąca ulica w polu „skręć w” VW (`RoadName`, 7. łatana klasa NavSD `TurnToInfo`, osłonięta jak pozostałe: przy
  błędzie tekst fabryczny).
- **f**: `FeedRecovery`: błąd odczytu skrzynki nie zatrzymuje już prowadzenia do następnego startu; ponowna próba po 1 s od
  świeżej bazy, pierwszy błąd w `failure-first.txt` (maks. 768 B).
- Niewzięte z v1.4.3: strzałka zastępcza Tomasza, nowe kodowanie pasów, LaneEvidence, diagnostyka przejmowania.
- Testy: jego TestArrow / TestRoad / TestRecovery (skopiowane bez zmian, przypięte), obok TestLive i TestLanes.

## Strzałki zastępcze (v1.4)

`rg/lanes/maneuvers.py`. `LiveModel.map()` Tomasza nie pokazuje strzałki, gdy iOS pominie pole (kąt zjazdu, typ
skrzyżowania, strona ruchu); najbardziej widać to na starcie trasy (typ 11 bez kąta), gdzie pierwsza strzałka pojawiała się
dopiero przy drugim manewrze. Wszystko, co ścisłe mapowanie już mapuje, zostaje dokładnie takie samo; uzupełniane są tylko
jego wyniki „bez strzałki” (main 0), według harman-f/mhi2_altscreen_carplay `MibrRgiManeuvers.java` (git `c01bbdc`, Skoda
MU1440, te same elementy główne VW BAP, GPL-3.0): start trasy / zjazd z promu bez kąta -> prosto, skręty bez typu
skrzyżowania -> kierunek samego typu, brak strony ruchu -> ruch prawostronny, zjazdy bez kąta -> lekko w stronę ruchu
(ruch prawostronny, gdy strony brak: auto jeździ w Polsce). Typ skrętu na rondzie (skrzyżowanie 1) staje się symbolem ronda
z kierunkiem zjazdu zamiast zwykłego skrętu. Zmiana autostrady (51) i zjazdy z ronda 28-46 bez kąta zostają puste (bez
zgadywania). Pasek odległości pokazuje się też przy tych strzałkach. Test: `TestManeuvers` (każdy typ x skrzyżowanie x
strona x próbka kąta: wyniki ścisłe bez zmian, tylko używane elementy główne VW; strzałki zastępcze; start trasy od
początku do końca). Zestaw `TestLive vectors` Tomasza porównuje z jego ścisłym mapowaniem i na tym JAR-ze ma prawo się
różnić. Przycisk GEM „RG last maneuver” pokazuje ścisłe mapowanie; gdzie jest main 0, paczka `rg` może jeszcze pokazać
strzałkę zastępczą.

## Bramka logu w sterowniku iAP2 (v1.4, `rg/driver/`)

Hook B2 Tomasza zapisuje każdy odebrany komunikat prowadzenia bajt po bajcie do `/dev/shmem/iap2.log`, w wątku odbioru
iAP2, zawsze. `rg/driver/log-gate.S` (76 bajtów, zassemblowane bajty w repozytorium jako `rg/driver/log-gate.bin`,
przypięte) dopisuje do wstrzykniętego segmentu `patch-log-gate.py`, który przestawia jeden skok: log działa tylko wtedy,
gdy istnieje plik `/dev/shmem/pmcp-rgi-debug` (domyślnie wyłączony). Każdy inny bajt sterownika zostaje bez zmian
(sprawdzane). Wynik `519ea3c5…` (743,272 B). Docker ani toolchain QNX nie są potrzebne; `PMCP_GATE_REBUILD=1` assembluje
bajty ponownie w Dockerze (`rg/driver/build-gate.sh`) i musi dać te same bajty.

## Czytnik `pmcp-r1` (v1.4, `rg/reader/`)

Gotowy czytnik Tomasza (`b683cef7…`) kończył się na dobre 1,5 s po tym, jak odczyt ze sterownika przestał dawać dane,
i prowadzenie było martwe do następnego startu radia. `rg/reader/reader.c` (GPL, pochodny od jego `reader.c`; proces
roboczy, sprawdzanie migawek i format skrzynki RGM1 bez zmian) dodaje nadzorcę: gdy odczyt procesu roboczego się zawiesi,
po 1 s zapisuje jeden rekord „invalid”, po 10 s zabija proces roboczy i uruchamia nowy z rosnącym opóźnieniem, a sam nigdy
nie kończy się na dobre. Blokada pliku (`reader.lock`) nie dopuszcza drugiego czytnika do tego samego katalogu. Binarka jest
w repozytorium jako `rg/reader/prebuilt/rgi-observer` (`3166df9b…`, 13,552 B); `rg/reader/build.sh` buduje ją ponownie
w Dockerze (opcjonalnie).

