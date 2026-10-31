# mhi2-aid-carplay

Mapa CarPlay i natywne prowadzenie na wirtualnym kokpicie (AID) **VW Passata B8 (MY2018)** z radiem **Discover Pro MHI2**:
**MU1161**, train `MHI2_ER_VWG13_P4512`, AID 791.

[English version: README.md](README.md)

![Mapa CarPlay z natywnym prowadzeniem VW na AID](docs/img/aid-carplay-2026-10/IMG_1127.jpg)

W repo jest tylko to, co dotyczy tego radia. Całość opiera się na pracy projektów wymienionych w sekcji
[Podziękowania](#podziękowania). Tam jest ogólne rozwiązanie mapy CarPlay na liczniku MHI2.

> **Uwaga.** To modyfikuje system multimedialny auta. Uruchomione w dokładnie jednym aucie: MU1161 + AID 791, firmware
> P4512. Każdy krok instalatora sprawdza hashe plików i zatrzymuje się przy każdej niezgodności, ale używasz na własne
> ryzyko. Nigdy nie wgrywaj firmware'u z innej gałęzi (cross-flash), żeby coś pasowało. Projekt niezwiązany z Volkswagenem,
> Harmanem ani Apple.

## Co działa (sprawdzone w aucie, październik 2026)

| Funkcja | Stan |
|---|---|
| Mapa CarPlay na AID (Mapy Apple, Google Maps), duże i małe zegary | działa |
| NavActiveIgnore: radio nie zatrzymuje i nie blokuje nawigacji z telefonu | działa |
| Natywne prowadzenie VW z iPhone'a: dystans i czas do celu na pasku VW i w lewej tarczy | działa |
| Natywna strzałka manewru i dystans do manewru (pojawia się po ruszeniu) | działa |
| Natywne pasy ruchu VW, także pasy do zawracania (gdy aplikacja w telefonie wysyła pasy) | działa |
| Przybliżanie mapy strzałkami na kierownicy | działa |
| Tytuł i wykonawca utworu z CarPlay na AID | działa |
| Przełączanie dzień/noc mapy na liczniku | działa |
| Ograniczenie prędkości z telefonu (`showSpeedLimit=yes`) | na tym radiu nic nie pokazuje |

![Mapa bez aktywnej nawigacji](docs/img/aid-carplay-2026-10/IMG_1102.jpg)

Więcej zdjęć i interaktywny model ramki AID (gdzie obraz trafia na panel w każdym wariancie):
[`docs/aid-frame-map.pl.html`](docs/aid-frame-map.pl.html), zdjęcia w [`docs/img/`](docs/img/).

## Składniki

| Katalog | Co buduje | Trafia do radia |
|---|---|---|
| [`patches/mu1161/`](patches/mu1161/) | warianty `core.so` strumienia CarPlay na licznik (safe area, URL, liczba klatek, klatki kluczowe, rozmiar fizyczny) z jednej przypiętej hashem bazy | `core.so` |
| [`navactiveignore/`](navactiveignore/README.pl.md) | NavActiveIgnore z własnych klas HMI radia | Java (HMI) |
| [`rg/`](rg/README.pl.md) | natywne prowadzenie: port rozwiązania tomasz-twardzicki z MU1427 na MU1161 (iAP2 RouteGuidance → BAP) | Java, sterownik iAP2, `iap2.cfg`, czytnik |
| [`nowplaying/`](nowplaying/README.pl.md) | tytuł i wykonawca utworu CarPlay na liczniku | Java (HMI) |
| [`hmiextras/`](hmiextras/README.pl.md) | zoom z kierownicy i ponowne wysłanie dzień/noc do mapy na liczniku | Java (HMI) |
| [`installer/`](installer/) | instalator na kartę SD uruchamiany z menu GEM w M.I.B., karta ratunkowa, testy na Macu | nic sam z siebie |
| [`buildtools/`](buildtools/) | kontrole przy budowaniu: osłona try/catch każdego wywołania haka, zgodność z API J9 CDC | nic |
| [`scripts/`](scripts/) | czytniki obrazów firmware'u tylko do odczytu (QNX6, IFS, LZOZ, JXE → JAR), tester kart SD | nic |
| [`firmware/`](firmware/) | hashe i notatki oficjalnej aktualizacji K4525 (jedyny dozwolony firmware) | nic |

### Warianty układu mapy (GEM → `pmcp_zmien_wariant`)

Strumień ma 800×480 i leży 1:1 na panelu AID. Safe area: x / y / szerokość / wysokość.

| Wariant | URL | Safe area | Uwagi |
|---|---|---|---|
| `map-clean` | `maps:/car/instrumentcluster/map` | 200 / 108 / 400 / 296 | sama mapa, prowadzenie pokazuje VW natywnie |
| `card-clean` | `maps:/car/instrumentcluster` | 200 / 108 / 400 / 296 | z kartą manewru iPhone'a |
| `url-map-hybrid` | `…/map?showSpeedLimit=yes` | 200 / 108 / 400 / 296 | parametr ograniczenia prędkości (bez efektu) |
| `map-clean-l40` | `maps:/car/instrumentcluster/map` | 160 / 108 / 400 / 296 | 40 kolumn w lewo |
| `map-square` | `maps:/car/instrumentcluster/map` | 240 / 60 / 320 / 340 | układ mathsls dla MU1161, bliżej kwadratu; najlepszy po dłuższej jeździe; 30 kl./s |
| `map-square-fps40` (domyślny) | `maps:/car/instrumentcluster/map` | 240 / 60 / 320 / 340 | `map-square` przy 40 kl./s (jak u mathsls); w jeździe testowej bez większego opóźnienia niż 30 kl./s |

Wszystkie warianty deklarują rozmiar fizyczny 240×144 mm. Zmiana wariantu podmienia jeden plik (`core.so`) i wymaga restartu.

## Pobieranie i instalacja

**[Pobierz najnowsze wydanie](https://github.com/chrzanowy/mhi2-aid-carplay/releases/latest)**: plik
`mhi2-aid-carplay-cards-<build id>.zip` z gotowymi obiema kartami SD. Nic nie trzeba instalować, Windows albo Mac.

1. Rozpakuj zip i otwórz `README-FIRST.txt` (po angielsku, krok po kroku).
2. Dwuklik na `Copy-to-SD-Windows.bat` (Windows) albo `Copy-to-SD-macOS.command` (Mac): kopiuje kartę na **pustą**
   kartę SD FAT32, sprawdza każdy plik i wysuwa kartę. Niczego nie formatuje ani nie usuwa. Zrób kartę 1
   (instalacyjną) i kartę 2 (ratunkową, na awarię).
3. W aucie, jedna wizyta, tylko karta 1 (część 2 w `README-FIRST.txt`, szczegóły: [tutorial w aucie](docs/pl/09-tutorial-w-aucie.md)):
   **1. Check → 2. Install map → restart → mapa OK? → 3. Install all features → restart (start próbny) → test →
   4. Confirm → restart.** Od tej chwili tak już zostaje.
   Karta 2 jest tylko na awarię po potwierdzeniu. Po użyciu sama się rozbraja; opcja 3 pomocnika kopiowania ją uzbraja.

Wcześniej potrzebny jest [M.I.B. w radiu i backup](docs/pl/01-mib-instalacja-backup.md). Instalator na karcie najpierw
sprawdza każdy plik radia; przy innym firmware zatrzymuje się i niczego nie zmienia.

Samodzielne zbudowanie kart z własnego backupu (zaawansowane, macOS): `./install.sh`, szczegóły w
[README.md](README.md#build-the-cards-yourself-advanced).

## Instalator

Instalator uruchamia się z menu GEM (inżynierskiego) w [M.I.B.](https://github.com/Mr-MIBonk/M.I.B._More-Incredible-Bash)
z karty SD. Zasady:

- **Fail-closed.** Każdy plik w radiu i na karcie jest sprawdzany dokładnym hashem i rozmiarem, zanim cokolwiek zostanie
  zapisane. Nieznany stan oznacza brak zmian.
- Pliki są kopiowane do katalogu przejściowego, sprawdzane i dopiero wtedy podmieniane. Wcześniej powstaje kopia plików
  fabrycznych. „Przywróć pliki fabryczne” działa zawsze.
- **Paczki Java mają start próbny.** Po „Wlacz” i restarcie zmianę trzeba potwierdzić („Potwierdz”) w tym samym starcie.
  Inaczej następny start jest znowu fabryczny.
- Osobna **karta ratunkowa** (`installer/build_rescue.py`) startuje sama w trybie aktualizacji i przywraca fabryczne HMI
  bez potrzeby wchodzenia do GEM.
- Testy na Macu (`installer/test/run_tests.sh`, `fault_inject.sh`) uruchamiają instalator na kopii drzewa plików radia,
  w powłokach `mksh` i `ksh`. Symulują też zanik zasilania na każdym kroku zapisu.

Instrukcja krok po kroku w aucie: [`docs/pl/09-tutorial-w-aucie.md`](docs/pl/09-tutorial-w-aucie.md).
Projekt instalatora: [`docs/pl/07-instalator.md`](docs/pl/07-instalator.md).

## Budowanie

Repo (źródła) **nie zawiera binarek** ani niczego z firmware'u Volkswagena. Każdy build czyta wejścia z katalogu roboczego obok
repo i sprawdza każde wejście hashem SHA-256:

```
workspace/
  mhi2-aid-carplay/        to repo
  upstream/                klony projektów niżej, na przypiętych commitach
  backup/MU1161/           backup M.I.B. Twojego radia (albo zmienna PMCP_BACKUP)
  archives/                menu GEM z M.I.B. 3.6.0, przekonwertowany lsd.jar Twojego radia
```

| Wejście | Źródło | Przypięte |
|---|---|---|
| bazowy `core.so` (profil MU1102/791, sha256 `00b48a8f…`) | paczka omonob w M.I.B. | commit `3a2526a3` |
| natywne prowadzenie, miejsca łatek | tomasz-twardzicki/MHI2-Carplay-Maps | commit `024dd159` |
| paczka referencyjna MU1161/791 | mathsls/MHI2-Carplay-Maps | commit `cdd576b0` |
| konwerter JXE → JAR | luka-dev/jxe2jar | commit `9eeb45bb` |
| menu GEM (`Launcher-sda0.esd`) | zip M.I.B. 3.6.0 | sha256 `4bfc6e72…` |
| klasy HMI, sterownik iAP2 | Twoje radio (backup M.I.B.) | sha256 każdego pliku |
| narzędzia | ASM 9.7 (buildy Java), pyelftools 0.31 w `upstream/tools/venv-elftools` (`rg/`), gawk 3.1.5 w `upstream/tools/` (testy) | jary ASM po sha256 |

Kolejność: `navactiveignore/`, `nowplaying/`, `hmiextras/`, `rg/` (w każdym `build.sh`; potrzebny JDK 11+ i ASM 9.7
w `$ASM_DIR`), potem `patches/mu1161/build_core.py`, `installer/build_sd.py`, `installer/build_card_install.py`
i `installer/build_rescue.py`. Pythona uruchamiaj z `python3 -I`. Gdy którekolwiek wejście ma inny hash, build się zatrzymuje.

## Dokumentacja

Po polsku w [`docs/pl/`](docs/pl/), po angielsku w [`docs/en/`](docs/en/):

| Temat | Polski | English |
|---|---|---|
| Instalacja M.I.B. i backup radia (zrób najpierw) | [01-mib-instalacja-backup](docs/pl/01-mib-instalacja-backup.md) | [01-mib-install-backup](docs/en/01-mib-install-backup.md) |
| Analiza HMI: strumień mapy, wykrywanie rozmiaru AID, klasy CarPlay i prowadzenia | [04-lsd-jxe-dekompilacja](docs/pl/04-lsd-jxe-dekompilacja.md) | [04-lsd-jxe-decompilation](docs/en/04-lsd-jxe-decompilation.md) |
| Projekt instalatora | [07-instalator](docs/pl/07-instalator.md) | [07-installer](docs/en/07-installer.md) |
| Audyt: szybki start mapy na AID (próby, porażka, dlaczego AID wymagał uśpienia auta) | [14-audyt-szybki-start](docs/pl/14-audyt-szybki-start.md) | [14-fast-start-audit](docs/en/14-fast-start-audit.md) |
| Instrukcja krok po kroku w aucie | [09-tutorial-w-aucie](docs/pl/09-tutorial-w-aucie.md) | [09-in-car-guide](docs/en/09-in-car-guide.md) |
| Interaktywny model ramki AID | [aid-frame-map.pl.html](docs/aid-frame-map.pl.html) | [aid-frame-map.html](docs/aid-frame-map.html) |

Katalogi składników mają `README.md` po angielsku i `README.pl.md` po polsku.

## Podziękowania

Ten projekt nie powstałby bez:

- **[omonob/MHI2-Carplay-Maps](https://github.com/omonob/MHI2-Carplay-Maps)**: pierwotne rozwiązanie mapy CarPlay na
  wirtualnym kokpicie MHI2. Jego `core.so` (profil MU1102/791) jest bazą, którą łata każdy wariant tutaj.
- **[Mr-MIBonk/M.I.B.](https://github.com/Mr-MIBonk/M.I.B._More-Incredible-Bash)**: narzędzia GEM, z których startuje
  instalator, backup radia i dystrybucja paczki omonob.
- **[tomasz-twardzicki/MHI2-Carplay-Maps](https://github.com/tomasz-twardzicki/MHI2-Carplay-Maps)**: miejsca łatek
  `core.so` (liczba klatek, klatki kluczowe, URL, safe area), klasy NavActiveIgnore i rozwiązanie natywnego prowadzenia
  (łańcuch łatek sterownika, most HMI, czytnik RGI), które `rg/` przenosi na MU1161.
- **[mathsls/MHI2-Carplay-Maps](https://github.com/mathsls/MHI2-Carplay-Maps)**: pierwszy build dla MU1161 + AID 791.
  Z niego pochodzą miejsca rozmiaru fizycznego i układ wariantu `map-square`.
- **[ZzYunOvO/MHI2-Carplay-Maps](https://github.com/ZzYunOvO/MHI2-Carplay-Maps)**: zestaw narzędzi, na którym opierają
  się forki mathsls i tomasz-twardzicki.
- **diasdio** i **ramasauskas**: poprawki klatek kluczowych i wysokości safe area, poprawka kolejki AUSAFE w moście MOST.
- **harman-f**: parametry URL licznika (`showETA`, `maneuverLayout`, `showSpeedLimit`).
- **[luka-dev](https://github.com/luka-dev/jxe2jar)**: jxe2jar i dekoder RGI.
- **maxim-smirnov**: opis formatu kontenera LZOZ.
- **MacsInSpace**: wskazówka „Zapomnij to auto”, gdy licznik nie dostaje obrazu.
- Społeczność **MQB Toolbox**: pierwotny pomysł NavActiveIgnore.

Pliki, które adaptują kod z tych projektów, podają źródło i commit w nagłówku albo w README.

## Licencja

GPL-3.0-or-later, zobacz [LICENSE](LICENSE). To ta sama licencja co w projektach omonob, tomasz-twardzicki i mathsls,
na których to się opiera.
