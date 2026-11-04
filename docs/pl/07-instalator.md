# Instalator pmcp: mapa CarPlay na AID, MU1161 / 791

Stan: **przetestowany w aucie (październik 2026; prowadzenie v1.4 listopad 2026).** Kod: [`installer/`](../../installer/).
Build SD tworzy `installer/build_sd.py` (w katalogu wyjściowym `BUILD-MANIFEST.txt` z hashami wszystkich plików, wersja
w GEM `pmcp-0.4.0-mu1161-791-<id buildu>`, gdzie ID to pierwsze 8 znaków SHA-256 manifestu i szablonu `pmcp.sh`).
Kartę instalacyjną składa `installer/build_card_install.py`, kartę ratunkową `installer/build_rescue.py`.

## Paczki (budowane razem, wgrywane partiami przyciskami M.I.B.)

| Paczka | Co zmienia | Status |
|---|---|---|
| 0 Karta ratunkowa | nic w radiu (osobna karta z `installer/build_rescue.py`) | sprawdzona w aucie (`RESULT=OK`; do v1.3 `WYNIK=OK`) |
| A Obraz CarPlay + warianty `core.so` | `dio_manager` → wrapper, `/mnt/app/carplaymaps` | działa |
| B Mechanizm Java + NavActiveIgnore | jeden stały blok w `lsd.sh` + JAR | działa; przycisk „3. Install all features” na ekranie głównym (od v1.2.0 bez odblokowania) |
| C Parametry mapy iPhone'a w URL | tylko `core.so` (wariant `url-map-hybrid`, `showSpeedLimit=yes`) | w menu; na tej jednostce parametr nic nie pokazuje |
| D Tytuł i wykonawca | JAR `pmcp-np.jar` (`HsmTarget` + `CurrentStationInfo`) | działa ([`nowplaying/`](../../nowplaying/README.pl.md)) |
| E Natywne prowadzenie (port Tomasza) | „Route guidance system” (sterownik iAP2 z bramką logu, `iap2.cfg`, czytnik `pmcp-r1`) + jeden JAR `pmcp-guidance.jar` (paczka `rg`: strzałki, pasy, pasek odległości, ulica, ETA, zastępcze strzałki) | działa ([`rg/`](../../rg/README.pl.md)) |
| F Zoom z kierownicy | JAR `pmcp-zoom.jar` (hook w `DSIKeyPanelDispatcher`, tylko krótkie naciśnięcie) | działa ([`hmiextras/`](../../hmiextras/README.pl.md)) |
| G Dzień/noc mapy na AID | JAR `pmcp-dn.jar` (hooki w `ASLHandler`) | działa ([`hmiextras/`](../../hmiextras/README.pl.md)) |

**Etap A nie dotyka HMI** (Java): najgorszy skutek to brak CarPlay/AA, a GEM i „Remove everything” działają.

**Wszystko w Javie przechodzi przez jeden blok w `lsd.sh`** (przed startem J9, nic po nim) z próbnym startem:
- blok czyta jeden plik: `/mnt/app/carplaymaps/HMI_BOOT` = `ID_ZESTAWU JAR JAR …` (ID = `nazwa-8 znaków sha` połączone `+`).
  `pmcp.sh` podmienia go jednym `mv`, więc przy zaniku zasilania start widzi stary albo nowy zestaw, nigdy mieszankę;
- nowy zestaw ładuje się **raz** próbnie (`/mnt/persist/pmcp/trial.<ID>`);
- zostaje na stałe **tylko po naciśnięciu w GEM „4. Confirm” w trakcie tego startu próbnego**. `lsd.sh` przy każdym starcie najpierw
  usuwa, potem zapisuje `/mnt/persist/pmcp/last-boot` (`set=<ID> use=trial|yes|no`); `java-confirm` wymaga `use=trial` dla bieżącego ID,
  braku `ok.<ID>` i braku `DISABLED`. Fabryczny start po nieudanej próbie nie może więc potwierdzić zepsutego zestawu;
- **nie ma automatycznego potwierdzenia**. Żywy proces J9 nie dowodzi działającego HMI;
- bez potwierdzenia **każdy następny start (np. reset pokrętłem) jest fabryczny**; ponowna próba: „5. Try again”;
- **w trybie aktualizacji (`RUN_MODE=swdl`) blok nic nie robi** (fabryczny `lsd.sh` uruchamia HMI także w tym trybie, z kopią `jars/`
  w `/ramdisk`). Karta ratunkowa zawsze trafia na fabryczne HMI;
- `/mnt/persist/pmcp/DISABLED` (karta ratunkowa) wyłącza blok całkowicie.

Szybki powrót do auta, zanim radio uśnie, to nie jest nowy start. Liczy się tylko przebieg `lsd.sh` (zimny start, reset, restart po
instalacji). `boot.log` na `/mnt/persist/pmcp` pokazuje, co się działo, „Status” w GEM pokazuje też `last-boot`.

## Co instaluje

Układ omonob/mathsls na MU1161:

| Element | Źródło | SHA-256 |
|---|---|---|
| `altscreen-most-bridge` | mathsls profil MU1161 (= nasz z poprawką diasdio) | `fed7dce4…44f4` |
| `carplay-cluster-supervisor` | mathsls (poprawka `/ramdisk` → `/dev/null`) | `8e6ac3a8…7569` |
| `libcarplay-security-bridge.so`, `carplay-pairing-helper`, `libCarPlayPairingCore.so` | mathsls = omonob | `1cef6a39…`, `ffb7d4df…`, `90c348f9…` |
| `dio_manager.wrapper.sh` | mathsls (logi na `/dev/null`) | `8c12f697…633d` |
| `core.so` | jeden z 5 wariantów (niżej) | w `BUILD-MANIFEST.txt` |
| `lsd.sh` (etap B+) | wygenerowany na hoście z fabrycznego: fabryczny + jeden blok pmcp przed `export LD_PRELOAD` / `$J9` | `LSD_JAVA` w manifeście |
| JAR-y Java (etap B+) | nasze buildy (`NavActiveIgnore.jar`, `pmcp-np.jar`, `pmcp-guidance.jar` (paczka `rg`), `pmcp-zoom.jar`, `pmcp-dn.jar`) | w `BUILD-MANIFEST.txt` |
| system prowadzenia | sterownik iAP2 `519ea3c5…` (743,272 B), `iap2.cfg` `c61407d9…`, czytnik `rgi-observer` `3166df9b…` (13,552 B), zob. [`rg/`](../../rg/README.pl.md) | w `BUILD-MANIFEST.txt` |

Aktualne hashe `core.so` i JAR-ów są w manifeście, który generuje `installer/build_sd.py` dla danego buildu.

Celowo pominięte: `libcardshim.so` mathsls (`zoomFactor` 1.5, `properties`/`uid` wyświetlacza). Wariant `map-square` przejmuje
więc tylko układ safe area mathsls, nie całą ich konfigurację.

Warianty `core.so` (`switch` zmienia tylko ten plik, potem restart, bez „4. Confirm”), wszystkie z `build_core.py`, wszystkie
240×144 mm. Safe area = x / y / szerokość / wysokość na strumieniu 800×480:

| Wariant | URL | Safe area | Opis |
|---|---|---|---|
| `map-clean` | `maps:/car/instrumentcluster/map` | 200 / 108 / 400 / 296 | Sama mapa, VW pokazuje prowadzenie natywnie |
| `card-clean` | `maps:/car/instrumentcluster` | 200 / 108 / 400 / 296 | z kartą manewru iPhone'a |
| `url-map-hybrid` | `…/map?showSpeedLimit=yes` | 200 / 108 / 400 / 296 | parametr ograniczenia prędkości (bez widocznego efektu) |
| `map-clean-l40` | `maps:/car/instrumentcluster/map` | 160 / 108 / 400 / 296 | przesunięty o 40 kolumn w lewo |
| `map-square` | `maps:/car/instrumentcluster/map` | 240 / 60 / 320 / 340 | układ mathsls dla MU1161, bliżej kwadratu, 30 kl./s (domyślny do v1.2.0) |
| **`map-square-fps40`** | `maps:/car/instrumentcluster/map` | 240 / 60 / 320 / 340 | **domyślny (główny przycisk) od v1.3.0**: `map-square` przy 40 kl./s (wartość bazowego core, jak u mathsls), w jeździe testowej bez większego opóźnienia niż 30 kl./s; IDR co 10 klatek dawało artefakty |

## Bramki fail-closed (co musi się zgadzać, zanim cokolwiek zostanie zapisane)

1. **Self test hashowania** na jednostce: fabryczny `/net/rcc/usr/bin/sha1sum`, uruchamiany lokalnie na MMX (tam działają skrypty
   GEM), musi policzyć poprawny SHA-1 pliku `selftest.bin`. Manifest zostaje w SHA-256; `build_sd.py` dokłada do `pmcp.sh` mapę
   SHA-256 → SHA-1 (`HASHMAP`) dla każdego pliku z manifestu i każdego sprawdzanego pliku fabrycznego. Brak wpisu w mapie = odmowa.
   (SHA-256 w `gawk` porzucono: locale „C” na QNX jest wielobajtowe, działało tylko `C-TRADITIONAL`, a szybkość wynosiła
   ok. 10–20 KB/s. Z `sha1sum` akcje trwają sekundy.)
2. **Payload na SD:** hash i rozmiar każdego pliku równy manifestowi wbudowanemu w `pmcp.sh`. Pętla idzie po manifeście w samym
   skrypcie (bez pliku tymczasowego), więc niezapisywalna karta nie może pominąć kontroli.
3. **Firmware:** `lsd.jxe` = 55,830,309 B (MU1161).
4. **Stan jednostki:**
   - `STOCK`: brak `/mnt/app/carplaymaps`, brak JAR-ów nawigacji/sterowania, `lsd.sh`, `dio_manager`, `gal`, sterownik iAP2 i `iap2.cfg` fabryczne.
     Tylko w tym stanie wolno `install`. Pozostałość `.carplaymaps-old-*` po przerwanym `restore` nie przeszkadza (sprząta ją `install`).
   - `VIDEO` (etap A): wrapper aktywny, `lsd.sh` fabryczny, brak naszych JAR-ów.
   - `JAVA` (etap B+): jak `VIDEO` plus blok w `lsd.sh` i spójny zestaw JAR-ów (każdy z hashem z manifestu, `HMI_BOOT` dokładnie zgodny).
     Zestaw może też zawierać paczki wcześniejszej karty (`JAVA_OLD`: `rg` `717fb53c` i `rglu` `72ab7221` z v1.2/v1.3,
     eksperymentalne `rglua`, `rgluasf`, `rgluasfa`, `rgluasfm`, `rgluasfma`); wtedy `java-on` i `java-off` odmawiają
     (`JAVA_SET_HAS_OLD_PACKAGES_RUN_JAVA_UPDATE_FIRST`), dopóki `java-update` ich nie zastąpi, a „Status” pokazuje
     „packages of an earlier card: …”.
   - System prowadzenia (`RGSYS`, pokazuje go „Status”): `off`, `on`, `old` (włączony, ale ze sterownikiem i/lub czytnikiem
     wcześniejszej karty, `RG_KNOWN`: sterownik v1.0–v1.3 `76926bde…`, czytnik Tomasza `b683cef7…`; zastępuje je `rg-update`)
     albo `unknown`.
   - `PARTIAL`: przerwana akcja, kopie fabryczne nienaruszone. Wolno tylko `restore` (i `rg-system-off`).
   - `UNKNOWN`: cokolwiek innego, np. inny mod albo zmieniony `lsd.sh`. **Wszystko jest odrzucane.** Także Android Auto
     z karty eksperymentalnej (`carplaymaps/aa`, resztki przerwanej instalacji albo niefabryczny `gal`), z jednym wyjściem:
     `aa-remove` („Remove experimental Android Auto”, też pierwszy krok przycisku 3 i `restore`). Zapisuje tylko na instalacji
     pmcp i tylko gdy `gal` jest fabryczny albo `carplaymaps/aa/gal.real` ma fabryczny hash: fabryczny `gal` jest
     kopiowany z tej kopii, sprawdzany i przenoszony, potem znikają pliki i znaczniki AA. Ponowne uruchomienie kończy
     przerwane. Potem przycisk 3 zmienia eksperymentalne warianty `rg` na `rg`.
5. **Każda skopiowana kopia** (staging) jest hashowana przed przełączeniem; `chmod` sprawdzany, `dio_manager` musi być wykonywalny.
   Bezpośrednio przed przełączeniem jeszcze raz sprawdzamy, czy `lsd.sh` i `dio_manager` są dalej fabryczne.
6. **Po przełączeniu** stan musi być oczekiwany, a `core.so` mieć oczekiwany hash. Inaczej automatyczny rollback.
7. **Zapis na dysk:** `sync` na MMX (`on -f mmx sync`), bo tam są pliki; `sync` RCC nie jest wymagany.

Kolejność przełączania:
- etap A: stare znaczniki próby usunięte → katalog `carplaymaps` → `dio_manager`;
- `java-on`: JAR → `HMI_BOOT` (nowy ID = nowy próbny start) → `lsd.sh` (tylko przy pierwszej paczce);
- `java-off`: `HMI_BOOT` → usunięcie JAR-a; ostatnia paczka: najpierw fabryczny `lsd.sh`, potem JAR i `HMI_BOOT`;
- `restore`: `lsd.sh` → `dio_manager` → JAR-y → system prowadzenia → znaczniki próby → `carplaymaps` jednym `mv` do `.carplaymaps-old-<pid>`,
  dopiero potem `rm -rf`.
- system prowadzenia (`rg-system-on`): `/mnt/system` wraca na read-only po zapisie;
- `rg-update`: sterownik i czytnik z tej karty skopiowane i zhashowane → czytnik zatrzymany → `mv` sterownika → `mv` czytnika;
  podmieniane są tylko pliki z `RG_KNOWN`, `iap2.cfg`, `SYSTEM_ON` i kopie fabryczne zostają (droga powrotu: `rg-system-off`).
  Ponowne uruchomienie po przerwaniu kończy robotę;
- `java-update`: nowe JAR-y (nazwa pliku, której nie używała żadna wcześniejsza karta, np. `pmcp-guidance.jar`) → `HMI_BOOT`
  (nowy ID = nowy start próbny) → usunięcie starych JAR-ów. Do przełączenia `HMI_BOOT` stary zestaw zostaje nietknięty.

**Test zaników zasilania** (`installer/test/fault_inject.sh`): dla każdej akcji łańcucha
install → java-on nai → java-on np → rg-system-on → java-on rg → switch → java-off np → java-off rg → rg-system-off → java-off nai → restore
skrypt jest zabijany przed 1., 2., 3. … poleceniem zmieniającym jednostkę. Dla każdego punktu: symulowany **następny start**
(blok `lsd.sh` z zabitego drzewa) nie może załadować bez próby zestawu, którego użytkownik nie potwierdził; stan musi być
STOCK/VIDEO/JAVA/PARTIAL, a `restore` (albo install+restore przy STOCK) musi dać drzewo fabryczne.

## Użycie w aucie: przyciski w GEM

Wymaga: M.I.B. zainstalowany ([01-mib-instalacja-backup.md](01-mib-instalacja-backup.md)) i **karta instalacyjna** zbudowana przez
`installer/build_card_install.py`: kompletna karta = nietknięte drzewo `MIB_V3.6.0.zip` (autorun rozbrojony, `_Swdlautorun.txt`) +
build SD z `installer/build_sd.py` (`pmcp/`, `esd/Launcher-sda0.esd`), złożona przez
`python3 -I installer/build_card_install.py <build SD> <katalog karty>` (każdy plik buildu sprawdzony z `BUILD-MANIFEST.txt`, odmowa przy
uzbrojonym autorunie albo plikach karty ratunkowej). Hashe wszystkich plików: `PMCP_CARD_MANIFEST.txt`, instrukcja
`PMCP_INSTRUKCJA.txt`. Kopiujesz **całą zawartość** katalogu na pustą kartę (FAT32), zamiast dogrywać `pmcp/` na kartę M.I.B. ręcznie.

Jak to działa: jednostka ma w GEM symlink `engdefs/z_Launcher-sda0.esd` → **plik menu na karcie**
(`/net/mmx/fs/sda0/esd/Launcher-sda0.esd`, zakłada go M.I.B. przy instalacji). Do tego pliku na karcie dopisujemy
ekran `pmcp_CarPlay_AID`. W jednostce nic się nie zmienia. Plik bazowy to dokładnie `esd/Launcher-sda0.esd`
z `MIB_V3.6.0.zip` (`22739f72…9121`); test sprawdza, że oryginalna treść jest nietknięta (dopisany tylko koniec).

1. Na komputerze: skopiuj całą zawartość katalogu karty instalacyjnej na pustą kartę (katalog główny karty).
   Sprawdź w GEM w nagłówku ekranu pmcp wersję: musi być ta z pierwszej linii `BUILD-MANIFEST.txt`.
2. W aucie: GEM → `=>M.I.B.<=` → **`pmcp_CarPlay_AID`**. Ekran główny (po angielsku):
   - „1. Check card and unit (read-only)” → `verify`;
   - „2. Install the CarPlay map on the AID” → `install map-square-fps40` (etap A);
   - „3. Install all features or update: map, route guidance, zoom, day/night, song title” → skrypt menu `all-on.sh`:
     `rg-update`, `java-update`, `switch map-square-fps40`, `rg-system-on`, potem `java-on` nai, np, rg, zoom, dn po kolei
     (jeden zestaw, jeden start próbny); stop na pierwszym `PMCP_FAIL`, `*_ALREADY_*` liczy się jako zrobione (`switch` na już
     aktywną mapę odpowiada `SWITCH_ALREADY_<wariant>`), więc ten sam przycisk doprowadza każdą wcześniejszą instalację
     (v1.0–v1.3 albo warianty rg z karty eksperymentalnej po usunięciu Android Auto) do zestawu z karty;
   - „4. Confirm: everything works (only in the first start after 3)” → `java-confirm`;
   - „5. Try again: the next start is a new trial” → `java-retry`;
   - „Status (read-only)”, „Remove everything (back to factory files)” → `restore`;
   - podmenu `pmcp_advanced`: „0. Diagnostics (read-only, photograph the screen)” (działa nawet wtedy, gdy `pmcp.sh`
     zatrzyma się na self teście), „Start timeline: …”, „RG last maneuver: …” (co wysłał iPhone i jaką strzałkę VW daje
     ścisłe mapowanie; gdzie pokazuje main 0, paczka `rg` może jeszcze pokazać strzałkę zastępczą), „Navigation
     diagnostics: …” oraz podmenu `pmcp_other_layouts` („Install map layout: <wariant>”), `pmcp_switch_layout` (`switch`,
     „Switch map layout to: <wariant>”) i `pmcp_packages`: „Route guidance system on (iAP2 driver, iap2.cfg, reader)”,
     „Route guidance system off (factory iAP2 driver and iap2.cfg)”, „Route guidance system update (driver and reader of
     this card, RG stays on)” (`rg-update`), „Java update: packages of an earlier card -> this card's (rglu -> rg)”
     (`java-update`) oraz „On …” / „Off …” dla każdej paczki (nai, np, rg, zoom, dn).
   Żadna akcja nie wymaga pliku odblokowania (do v1.1.0 akcje Java i systemu prowadzenia wymagały `pmcp/ODBLOKUJ_ETAP_B`).
3. Wynik jest na ekranie GEM. Karta SD jest w GEM tylko do odczytu (nawet `mount -uw` się nie udaje), więc logu nie da się
   zapisać na kartę: instalator wypisuje `PMCP_WARN=SD_LOG_NOT_WRITABLE` i działa dalej. **Rób zdjęcia ekranu.** Jeśli karta
   jest zapisywalna, log trafia do `/pmcp/log/pmcp-<akcja>-<pid>.log`.

Wszystkie etykiety są po angielsku (od v1.4) i w czystym ASCII.

Kolejność (jedna wizyta w aucie):
1. „1. Check card and unit” (`verify`): tylko odczyt. Oczekiwane `PMCP_VERIFY_OK state=STOCK`.
2. „2. Install the CarPlay map on the AID” (etap A), potem pełny restart. Jeśli na AID nie ma obrazu CarPlay: w iPhonie
   Ustawienia → Ogólne → CarPlay → auto → „Zapomnij to auto” i podłączyć ponownie (iPhone pamięta stare wyświetlacze auta).
   Inny układ mapy: `pmcp_advanced` → `pmcp_switch_layout` → „Switch map layout to: …”.
3. Tylko gdy mapa działa: „3. Install all features” → restart (start próbny) → sprawdzić HMI i funkcje → **w tym samym starcie**
   „4. Confirm” → restart. Bez potwierdzenia następny start jest fabryczny.
4. Wycofanie: „Remove everything (back to factory files)” i restart.

Aktualizacja z v1.0–v1.3: „1. Check” (stan `JAVA`; „Status” może pokazać „Route guidance system: old” i „packages of an
earlier card: rglu”), potem „3. Install all features or update” (uruchamia `rg-update` i `java-update`) → restart (start
próbny) → „4. Confirm”. Zrób też nową kartę ratunkową (niżej).
Karta ratunkowa jest na awarię po potwierdzeniu; wcześniejszy test jest opcjonalny.

Szczegółowy przewodnik po kolejnych krokach w aucie: [09-tutorial-w-aucie.md](09-tutorial-w-aucie.md).

## Testy na hoście

`installer/test/run_tests.sh SD_BUILD mksh ksh` (z `PMCP_RESCUE_SD=<karta ratunkowa>`): drzewo jednostki z backupu (prawdziwe
`lsd.sh`, `dio_manager`, `jars`, sterownik iAP2, `iap2.cfg`; `lsd.jxe` jako plik o właściwym rozmiarze),
shelle `mksh` (rodzina pdksh, jak QNX) i `ksh` (ksh93). Kod wyjścia = liczba nieudanych kontroli. Obejmują m.in.:

- `verify` niczego nie zapisuje; zły wariant, uszkodzony bajt payloadu (też przy niezapisywalnym katalogu logów), uszkodzony self test,
  zły rozmiar `lsd.jxe`, zmieniony `lsd.sh` i obcy mod są odrzucane bez zmian w drzewie;
- pełny łańcuch install → paczki Java (1, 2 i 5 naraz) → system prowadzenia → switch → restore daje drzewo **bajtowo identyczne** z fabrycznym;
- **próbny start na prawdziwym bloku `lsd.sh`** połączony z `pmcp.sh`: próba → start bez potwierdzenia fabryczny →
  „4. Confirm” odrzucone → retry → start w trybie `swdl` niczego nie ładuje i kasuje `last-boot` → potwierdzenie tylko w starcie próbnym →
  potwierdzony zestaw ładuje się zawsze → `DISABLED` wyłącza i blokuje potwierdzenie;
- `lsd.sh` po łatce = fabryczny + jeden blok (sprawdzane `diff`);
- pozostałości (`.carplaymaps-new-*`, `.carplaymaps-old-*`, `*.pmcp-*`, stare znaczniki `ok.*`) sprząta `install`; przerwany `restore`
  (katalog już przeniesiony) nie blokuje narzędzia;
- karta ratunkowa: zdrowe radio bez zmian; radio `JAVA` → fabryczny `lsd.sh`, JAR-y usunięte, `DISABLED`; radio z systemem
  prowadzenia → fabryczny sterownik i `iap2.cfg`, `SYSTEM_ON` i `last-boot` usunięte; brak kopii albo brak `lsd.sh` → uczciwe
  `RESULT=UNSURE` (wynik niepewny);
- menu GEM: liczba skryptów = liczba wpisów menu, składnia, dozwolone akcje, główny przycisk = `map-square-fps40`,
  wersja z ID buildu ta sama w `pmcp.sh`, menu i `BUILD-MANIFEST`.

`installer/test/fault_inject.sh SD_BUILD mksh`: test zaników zasilania (wyżej).

Czego testy hosta nie pokrywają: ścieżki QNX (`on -f mmx`, `mount`, `slay`, tłumaczenie ścieżek `/net/mmx`) i fabryczny `sha1sum`
są w trybie testowym pomijane (host liczy SHA-1 przez `shasum -a 1`); uprawnienia plików nie są w `snapshot`; łańcuch
`Swdlautorun` → `stuff.sh` jest testowany tylko na skrypcie. Te elementy sprawdzono w aucie.

## Karta ratunkowa (paczka 0)

Osobna karta (`installer/build_rescue.py`, instrukcja `PMCP_RESCUE_README.txt` na karcie). Uzbrojony `Swdlautorun.txt` →
radio samo wchodzi w tryb aktualizacji (`RUN_MODE=swdl`; nasz blok nic wtedy nie ładuje) → M.I.B. 3.6.0 `stuff.sh` →
`pmcp-rescue/pmcp-rescue.sh`:
- fabryczny `lsd.sh` z `/mnt/app/carplaymaps/rollback/`;
- usunięcie naszych JAR-ów;
- `/mnt/persist/pmcp/DISABLED`, usunięcie `last-boot`;
- system prowadzenia: fabryczny sterownik iAP2 i `iap2.cfg` z kopii (po rozmiarach; zna oba nasze sterowniki: 743,196 B
  z v1.0–v1.3 i 743,272 B z v1.4), usunięcie `SYSTEM_ON`.

Obraz (etap A) zostaje, resztę sprząta potem „Remove everything” w GEM. Na zdrowym radiu bez pmcp skrypt nic nie zmienia, tylko zapisuje log
`PMCP_RESCUE_LOG.txt` (`=== PMCP RESCUE start ===` … `RESULT=OK` albo `RESULT=UNSURE` … `=== PMCP RESCUE end ===`).
Autorun M.I.B. w trybie aktualizacji P4512 działa bez interakcji z HMI (sprawdzone w aucie).

Do v1.3 karta była po polsku (`pmcp-ratunek/`, `PMCP_RATUNEK_LOG.txt`, `WYNIK=OK` / `WYNIK=NIEPEWNY`); pomocniki kopiowania
czytają obie nazwy logu. Karta ratunkowa sprzed v1.4 działa dalej w radiu ze sterownikiem z v1.3, ale **nie** przywraca
sterownika z v1.4 (zna tylko 743,196 B): po aktualizacji do v1.4 zrób nową kartę ratunkową (pomocnik kopiowania, opcja 2).

Po użyciu M.I.B. rozbraja kartę (`Swdlautorun.txt` → `_Swdlautorun.txt`), więc nie zapętli się. Ponowne uzbrojenie na
komputerze (pomocnik kopiowania, opcja 3, albo ręczna zmiana nazwy). Od v1.2.0 instalator nie wymaga testu karty ratunkowej
przed akcjami Java; jest zalecany, nie wymuszany.

## Zabezpieczenia startu J9 z naszymi JAR-ami

Klasy w wersji 46, odwołania sprawdzone względem klas `java/*` jednostki (RefCheck), każde wywołanie z kodu fabrycznego osłonięte
(narzędzia w [`buildtools/`](../../buildtools/)). Skrypty używają konstrukcji ksh z instalatora mathsls (backticki, `while read`,
heredoc, `case`, `read` z przekierowaniem). Zabezpieczenie na wypadek błędu: próbny start z ręcznym potwierdzeniem, potem karta
ratunkowa. Czarny ekran w starcie próbnym (przed „4. Confirm”): pokrętło głośności 10 s, następny start jest bez naszych JAR-ów.
