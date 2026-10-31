# Tutorial w aucie: instalacja krok po kroku (Passat B8, MHI2 MU1161, AID 791)

Wersja instalatora: **`pmcp-0.3.0-mu1161-791-…`** (końcówka to identyfikator buildu; jest w pierwszej linii
`BUILD-MANIFEST.txt`, w `PMCP_INSTRUKCJA.txt` na karcie 1 i na górze ekranu zielonego menu).
Ekran główny zielonego menu jest po angielsku. Podmenu `pmcp_advanced` ma pierwotne polskie napisy bez ogonków.

Wszystko robisz **podczas jednej wizyty w aucie**:

```
karta 1:  1. Check  →  2. Install map  →  restart  →  mapa OK?  →  3. Install all features  →  restart (próbny)
          →  test  →  4. Confirm (ten sam start)  →  restart  →  działa od teraz
```

## Karty

| Karta | Opis | Co robi | Uwagi |
|---|---|---|---|
| **1 – instalacyjna** | `INSTALL` | M.I.B. 3.6.0 + instalator, wszystko z zielonego menu, jedna akcja naraz | nic nie startuje samo |
| **2 – ratunkowa** | `RESCUE - DO NOT INSERT` | po włożeniu radio **samo** wchodzi w tryb aktualizacji i cofa zmiany Javy | tylko na awarię; nie trzymaj jej w slocie |

Obie karty robi pomocnik kopiowania z paczki wydania (`README-FIRST.txt`). Zawsze **tylko jedna karta w radiu**,
zawsze slot **SD1**.

## Zasady dla każdego kroku

- Zasilanie: prostownik/booster albo pracujący silnik (na zewnątrz). Zapłon ON.
- **Nie przerywaj** akcji w zielonym menu (bez „Wstecz”, nie wyjmuj karty), aż wynik pojawi się na ekranie.
- Każda akcja kończy się linią `PMCP_..._OK` (dobrze) albo `PMCP_FAIL ...` (nic nie zmieniono albo wycofano). Przy `FAIL`
  nic więcej nie naciskaj, zrób zdjęcie ekranu.
- Karta SD w zielonym menu jest tylko do odczytu, więc instalator nie zapisze na niej logu (pokazuje
  `PMCP_WARN=SD_LOG_NOT_WRITABLE` i działa dalej). **Fotografuj wynik każdej akcji.**
- Wejście do zielonego menu: przytrzymaj **MENU ~10 s** → `=>M.I.B.<=` → **`pmcp_CarPlay_AID`**. Nagłówek musi pokazać
  wersję twojego buildu (`pmcp-0.3.0-mu1161-791-…`); inna wersja = stop.
- „Restart” = **przytrzymaj pokrętło głośności ~10 s** (radio się wyłącza i startuje). Wyłączenie i włączenie auta od razu
  to nie restart (radio jeszcze nie zasnęło).

---

## Krok 1. Sprawdzenie karty i radia (tylko odczyt)

1. Włóż **kartę 1**. Zielone menu → `=>M.I.B.<=` → `pmcp_CarPlay_AID`.
2. **„1. Check card and unit (read-only)”**. Trwa kilka sekund (hashe liczy fabryczny `sha1sum` radia).
3. Oczekiwany wynik: **`PMCP_VERIFY_OK state=STOCK`**. W radiu nic się nie zmienia. Przy innym firmware zatrzyma się tutaj.

Gdy coś jest niejasne: **„0. Diagnostyka (tylko odczyt, zrob zdjecia ekranu)”** (podmenu `pmcp_advanced`) pokazuje stan
radia i niczego nie zmienia.

## Krok 2. Instalacja mapy (etap A)

1. **„2. Install the CarPlay map on the AID”** → oczekiwane `PMCP_INSTALL_OK stage=A variant=map-square-fps40 ...`.
   (`map-square-fps40` to układ domyślny: układ forka mathsls, sama mapa, bliżej kwadratu, najlepszy z pięciu po dłuższej
   jeździe; 40 klatek na sekundę jak u mathsls, w jeździe testowej bez większego opóźnienia niż 30. `map-square` to to samo
   przy 30. Po kroku 3 manewr, ETA i dystans pokazuje natywnie VW.)
2. Restart (pokrętło ~10 s).
3. Podłącz iPhone'a (CarPlay), włącz Apple Maps albo Google Maps i **uruchom prowadzenie do celu**. Na AID przełącz widok na
   nawigację/mapę. Sterowanie AID w tym aucie (prawa strona kierownicy): **przyciski widoku** (układ licznika), między nimi
   **OK**, obok **góra/dół** (zakładki/menu licznika). Lewa strona kierownicy to asystenci.
   Ustaw zakładkę **Nawigacja** (góra/dół), potem przejdź przyciskami widoku przez układy: mapa CarPlay jest w małej tarczy
   w środku i w dużym układzie na całą szerokość.
4. Sprawdź: mapa CarPlay na AID, nic nie wchodzi pod tarcze i paski VW.

**Jeśli na AID nie ma obrazu:**
1. W iPhonie: Ustawienia → Ogólne → CarPlay → to auto → **„Zapomnij to auto”**, podłącz ponownie.
2. Dalej nic: zielone menu → **`pmcp_advanced` → `pmcp_zmien_wariant`** → „Zmien wariant na: map-clean” (szersze i niższe
   okno mapy), restart.
3. Inne układy w tym samym podmenu (każda zmiana → restart; układy: [mapa ramki AID](../aid-frame-map.pl.html)):
   `card-clean` (z kartą manewru iPhone'a), `url-map-hybrid` (mapa z parametrem ograniczenia prędkości, który w aucie nic
   nie pokazał), `map-clean-l40` (mapa 40 kolumn w lewo), `map-clean` (200 / 108 / 400 / 296).
   Powrót do domyślnego: „Zmien wariant na: map-square-fps40”.

Bez mapy na AID nie przechodź do kroku 3. Etap A nie zmienia startu ekranu radia: najgorszy skutek to brak obrazu CarPlay,
a zielone menu z „Remove everything (back to factory files)” działa zawsze.

## Krok 3. Instalacja wszystkich funkcji (albo aktualizacja)

**„3. Install all features or update: main map, arrows, lanes, ETA, zoom, song title”** → oczekiwane **`PMCP_ALL_ON_OK`**.

Uruchamia po kolei: główny układ mapy (`map-square-fps40`; pomijany, jeśli już jest), system prowadzenia (łatany sterownik
iAP2, `iap2.cfg`, czytnik) i pięć paczek Java (NavActiveIgnore, tytuł utworu, prowadzenie z pasami ruchu i pasami do
zawracania, zoom, dzień/noc). Wszystkie trafiają do **jednego zestawu**, więc jest jeden start próbny i jedno
potwierdzenie. Zatrzymuje się na pierwszym błędzie (`PMCP_FAIL=ALL_ON_STOPPED_AT_...`; wcześniejsze kroki zostają, ekran
pokazuje które). Ponowne naciśnięcie, gdy wszystko jest włączone, niczego nie zmienia.

**Aktualizacja wcześniejszej instalacji (v1.0-v1.2):** ten sam przycisk. Z nową kartą 1: „1. Check” (pokazuje
zainstalowany stan), potem „3. ...” → `PMCP_ALL_ON_OK`. Kroki już zrobione są pomijane (`*_ALREADY_*`); mapa przełącza się
na `map-square-fps40`, a prowadzenie `rg` zastępuje `rglu` (pasy). Dalej ten sam start próbny i Confirm co niżej.

## Krok 4. Start próbny, test, potwierdzenie

Java zmienia start ekranu radia, więc nowy zestaw przechodzi **start próbny**:

```
3. Install all features  →  restart  →  START PRÓBNY (zestaw ładuje się raz)
                                              │
                         wszystko działa? ────┤
                            TAK                │ NIE / czarny ekran
            w TYM SAMYM starcie, zielone menu: │ pokrętło ~10 s → następny start fabryczny
            „4. Confirm: everything works”     │ (nic nie potwierdzone, nic do naprawy)
            → zestaw ładuje się przy każdym starcie
```

1. Restart (pokrętło ~10 s). Ten start jest próbny.
2. Sprawdź:
   - radio startuje normalnie (ekran, radio, menu) i **CarPlay się łączy** (po kablu; raz odłącz i podłącz);
   - pasy: na skrzyżowaniu z pasami wyświetlanie pasów VW na AID (pasy ruchu muszą być włączone w ustawieniach VW i wysyłane
     przez aplikację w telefonie); pas do zawracania ma własną strzałkę;
   - prowadzenie w Apple Maps: mapa CarPlay **zostaje** na AID (NavActiveIgnore); czas i dystans do celu na pasku VW i w lewej
     tarczy; strzałka manewru i dystans do manewru (strzałka pojawia się po ruszeniu). Google Maps i Waze: sprawdź, czy też
     działa (nie wiadomo, czy wysyłają te dane);
   - muzyka z CarPlay (Spotify/Apple Music): tytuł i wykonawca w widoku mediów AID;
   - widok mapy na AID: **krótkie** naciśnięcie strzałki góra/dół na kierownicy przybliża/oddala (przytrzymanie nic nie robi);
   - dzień/noc: po starcie w dzień ze zgaszonymi światłami (nie AUTO) mapa na AID jest jasna; przy włączonych światłach ciemna.
3. Wszystko działa → **„4. Confirm: everything works (only in the first start after 3)”** → `PMCP_JAVA_CONFIRM_OK`.
   Tylko w starcie próbnym (instalator to sprawdza): nie wyłączaj auta między restartem a potwierdzeniem.
4. Coś nie działa albo ekran zostaje czarny → restart (pokrętło ~10 s): następny start jest fabryczny. Żeby spróbować
   ponownie: **„5. Try again: the next start is a new trial”**, restart. Żeby znaleźć funkcję, która sprawia kłopot, włączaj je
   po jednej ([zaawansowane](#zaawansowane-funkcje-po-jednej)).

## Krok 5. Restart

Jeszcze jeden restart. Od teraz zestaw ładuje się przy każdym starcie. **„Status (read-only)”** pokazuje `state=JAVA`,
zestaw i `This boot: set=... use=yes`.

---

# Awaria: karta 2 (ratunkowa)

Tylko gdy po potwierdzeniu ekran zostaje czarny albo radio się ciągle restartuje, a pokrętło nie pomaga:

1. Włóż **kartę 2** do SD1 i czekaj (do ~60 s). Radio samo wchodzi w tryb aktualizacji, może się kilka razy zrestartować.
   Na pytanie w menu aktualizacji → **Continue** (Dalej). Nie wyjmuj karty podczas aktualizacji.
2. Gdy radio wróci do normalnego ekranu → wyjmij kartę 2. Część Java i system prowadzenia są cofnięte (fabryczny `lsd.sh`,
   nasze JAR-y usunięte, `/mnt/persist/pmcp/DISABLED`, fabryczny sterownik iAP2 i `iap2.cfg`); mapa zostaje.
3. Karta 1 → „Remove everything (back to factory files)”, jeśli ma zniknąć także mapa.
4. M.I.B. po użyciu rozbraja kartę 2 (`Swdlautorun.txt` → `_Swdlautorun.txt`), więc nie zapętli się. Ponowne uzbrojenie na
   komputerze: pomocnik kopiowania, opcja **3** (pokazuje też wynik: `PMCP_RATUNEK_LOG.txt`, `WYNIK=OK`, na końcu
   `=== PMCP RATUNEK koniec ===`).

Opcjonalnie: kartę 2 można raz przetestować na sprawnym radiu przed krokiem 1. Na radiu bez naszych plików nie zmienia nic
naszego (po drodze ponownie instaluje się M.I.B. 3.6.0). Potem uzbrój ją opcją 3.

# Wycofanie i awarie

| Sytuacja | Co robić |
|---|---|
| Brak obrazu na AID | iPhone: „Zapomnij to auto”, podłącz ponownie; potem inny układ (krok 2) |
| Czarny ekran / logo w kółko w starcie próbnym | pokrętło ~10 s; następny start jest fabryczny |
| Któraś funkcja źle działa | restart bez potwierdzenia (fabryczny), potem funkcje po jednej ([zaawansowane](#zaawansowane-funkcje-po-jednej)) |
| CarPlay nie łączy się po kroku 3 | `pmcp_advanced` → `pmcp_etap_B_java` → „System RG: wylacz”, restart |
| Czarny ekran po potwierdzeniu | **karta 2** (awaria wyżej), potem karta 1 → „Remove everything (back to factory files)” |
| Wycofanie wszystkiego | „Remove everything (back to factory files)” → `PMCP_RESTORE_OK` → restart (radio fabryczne) |
| Każdy `PMCP_FAIL` albo coś niejasnego | nic więcej nie naciskaj, zdjęcie ekranu, „0. Diagnostyka” (tylko odczyt) |

Jedyna dozwolona aktualizacja firmware to oficjalna K4525. Nigdy cross-flash z innego modelu.

---

# Zaawansowane: funkcje po jednej

Zamiast kroku 3 funkcje można włączać po jednej w **`pmcp_advanced` → `pmcp_etap_B_java`**. Każde „Wlacz” tworzy nowy
zestaw → restart → start próbny → test → „4. Confirm”. „Wylacz” wraca do zestawu bez tej paczki: jeśli ten zestaw był
wcześniej potwierdzony, ładuje się od razu; jeśli nie, też jest próbny. Po restarcie „Status” pokazuje
`This boot: set=... use=trial` (próbny, potrzebne Confirm) albo `use=yes` (potwierdzony).

1. **„Wlacz: NavActiveIgnore (mapa na AID przy prowadzeniu w iPhonie)”**. Sprawdź: prowadzenie w Apple Maps, mapa CarPlay
   zostaje na AID.
2. **„Wlacz: Tytul i wykonawca utworu CarPlay na AID”**.
3. Prowadzenie, dwie części:
   - **„System RG: wlacz (sterownik iAP2, iap2.cfg, czytnik)”** (nie Java, bez Confirm) → restart → sprawdź **tylko, czy
     CarPlay się łączy**. Jeśli nie: **„System RG: wylacz (fabryczny sterownik i iap2.cfg)”**, restart i pomiń następny punkt.
   - **„Wlacz: Prowadzenie + pasy ruchu z zawracaniem (zamiast rg, wymaga Systemu RG)”**. Bez pasów: „Wlacz: Prowadzenie
     bez pasow ruchu: strzalki, dystans, czas (zamiast rglu, wymaga Systemu RG)”. Włączenie jednego zastępuje drugie.
4. **„Wlacz: Zoom mapy CarPlay strzalkami na kierownicy”**. Obserwuj, czy nie przeszkadza w menu licznika (te same strzałki).
5. **„Wlacz: Dzien/noc mapy CarPlay na AID (ponowne wyslanie po starcie)”**. Kluczowy przypadek (zgłoszony przez innego
   właściciela 791, omonob #51): auto na zewnątrz w dzień, światła zgaszone (nie AUTO) → start → mapa musi być jasna. Bez tej
   paczki mapa zostaje ciemna, aż włączysz światła.

## Ściąga

```
INSTALACJA:  karta 1 → 1. Check (STOCK) → 2. Install map → restart → mapa na AID?
             → 3. Install all features → restart (próbny) → test → 4. Confirm → restart → gotowe
AKTUALIZACJA: nowa karta 1 → 1. Check → 3. Install all features or update → restart (próbny) → test → 4. Confirm → restart
AWARIA:      start próbny zepsuty → pokrętło 10 s → start fabryczny;   po Confirm zepsute → karta 2 → Remove everything
RATUNEK:     po użyciu karty 2: pomocnik kopiowania opcja 3 na komputerze ponownie ją uzbraja
```
