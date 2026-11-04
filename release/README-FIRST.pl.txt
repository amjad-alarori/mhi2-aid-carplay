Mapa CarPlay na Active Info Display (wirtualny kokpit)
VW Passat B8 / MQB z radiem Discover Pro MHI2 - gotowe karty SD
Build: @@VERSION@@
English version: README-FIRST.txt
==========================================================================================

CO TO ROBI
  Pokazuje mapę CarPlay (Apple Maps, Google Maps) na 12,3" cyfrowym liczniku (AID),
  z natywnymi strzałkami skrętu VW, pasami ruchu, paskiem odległości, nazwą ulicy i godziną
  przyjazdu, zoomem mapy z kierownicy i tytułem bieżącego utworu.

DLA KOGO
  Tylko dla tego zestawu (sprawdzone na jednym aucie):
    - radio Discover Pro MHI2, oprogramowanie MU1161, train MHI2_ER_VWG13_P4512
    - 12,3" Active Info Display, numer części kończący się na 791
    - iPhone z CarPlay
  Nie musisz znać wersji oprogramowania: instalator w aucie najpierw sprawdza każdy plik.
  Jeśli twoje radio jest inne, zatrzymuje się i niczego nie zmienia.

  Używasz tego na własne ryzyko. Projekt niezwiązany z Volkswagenem, Harmanem ani Apple.

CO JEST POTRZEBNE
  - M.I.B. zainstalowane w radiu i zrobiony nim backup
    (zobacz docs/01-instalacja-MIB-i-backup.pl.md - zrób to najpierw, jeśli jeszcze nie)
  - dwie karty SD, dowolny rozmiar, sformatowane jako FAT32 (muszą być PUSTE)
  - komputer z Windows albo Mac ze slotem lub czytnikiem kart SD
  - w aucie: prostownik albo pracujący silnik (na zewnątrz)

------------------------------------------------------------------------------------------
CZĘŚĆ 1 - ZRÓB DWIE KARTY SD (na komputerze, około 5 minut)
------------------------------------------------------------------------------------------
  1. Rozpakuj ten zip.
       Windows: prawy przycisk na zipie -> "Wyodrębnij wszystkie..." -> Wyodrębnij.
       Mac: kliknij dwukrotnie zip.
  2. Uruchom pomocnika kopiowania:
       Windows: kliknij dwukrotnie  Copy-to-SD-Windows.bat
                (jeśli Windows pokaże "System Windows ochronił ten komputer":
                "Więcej informacji" -> "Uruchom mimo to")
       Mac:     prawy przycisk na  Copy-to-SD-macOS.command  -> Otwórz -> Otwórz
                (jeśli Mac odmówi: Ustawienia systemowe -> Prywatność i ochrona ->
                "Otwórz mimo to")
  3. Pomocnik pyta, co zrobić. Wybierz 1, żeby zrobić KARTĘ 1 (INSTALL), potem uruchom go
     jeszcze raz i wybierz 2 dla KARTY 2 (RESCUE). Włóż pustą kartę, gdy o to poprosi.
     Kopiuje pliki, sprawdza każdy z nich i wysuwa kartę.
     Nigdy niczego nie formatuje ani nie usuwa. Karta, która nie jest pusta, zostaje odrzucona.
  4. Podpisz karty długopisem:
       KARTA 1: "INSTALL"
       KARTA 2: "RESCUE - DO NOT INSERT"

  Formatowanie karty jako FAT32 (to ją KASUJE):
       Windows: Eksplorator plików -> prawy przycisk na karcie -> Formatuj ->
                System plików "FAT32" (karty powyżej 32 GB: Windows nie proponuje FAT32 -
                użyj karty 32 GB lub mniejszej)
       Mac:     Narzędzie dyskowe -> wybierz kartę -> Wymaż -> Format "MS-DOS (FAT)",
                Schemat "Główny rekord rozruchowy" (Master Boot Record)

------------------------------------------------------------------------------------------
CZĘŚĆ 2 - W AUCIE
------------------------------------------------------------------------------------------
  Zasady dla każdego kroku:
    - Tylko JEDNA karta w radiu naraz, zawsze slot SD1.
    - Zapłon włączony, podłączony prostownik albo pracujący silnik.
    - Zrób zdjęcie ekranu po każdej akcji (nie ma pliku logu).
    - Nigdy nie wyjmuj karty ani nie naciskaj Wstecz, gdy akcja trwa. Poczekaj na linię
      zaczynającą się od PMCP_..._OK (dobrze) albo PMCP_FAIL (nic nie zmieniono albo wycofano).
    - "Restart" = przytrzymaj pokrętło głośności około 10 sekund.

  Weź obie karty do auta. Potrzebna jest tylko KARTA 1. KARTA 2 (ratunkowa) jest na awarię.

  Krok 1. Sprawdzenie (niczego nie zmienia)
    Włóż KARTĘ 1. Przytrzymaj przycisk MENU około 10 sekund -> otwiera się zielone menu.
    Wejdź w  =>M.I.B.<=  ->  pmcp_CarPlay_AID.
    Górna linia musi pokazać:  @@VERSION@@
    Naciśnij  "1. Check card and unit (read-only)".
    Oczekiwane:  PMCP_VERIFY_OK state=STOCK
    Cokolwiek innego: STOP, zrób zdjęcie, poproś o pomoc. Nic nie zostało zmienione.

  Krok 2. Instalacja mapy
    Naciśnij  "2. Install the CarPlay map on the AID".   Oczekiwane:  PMCP_INSTALL_OK ...
    Restart (pokrętło głośności 10 s).
    Podłącz iPhone'a, uruchom nawigację w Apple Maps albo Google Maps i przełącz licznik
    na widok nawigacji/mapy (przyciski po prawej stronie kierownicy).
    Brak obrazu na liczniku? W iPhonie: Ustawienia -> Ogólne -> CarPlay -> twoje auto ->
    "Zapomnij to auto", potem podłącz ponownie. Dalej nic: nie przechodź do kroku 3.

  Krok 3. Instalacja reszty (tylko jeśli mapa działa)
    Zielone menu -> pmcp_CarPlay_AID -> "3. Install all features or update: map, route guidance, ...".
    (Masz już zainstalowaną wcześniejszą wersję? Zobacz AKTUALIZACJA niżej.)
    Oczekiwane:  PMCP_ALL_ON_OK
    Restart (pokrętło głośności 10 s). Ten start jest PRÓBNY.

  Krok 4. Test, potem potwierdzenie
    Sprawdź: CarPlay się łączy, mapa jest na liczniku, a podczas nawigacji pojawia się
    strzałka skrętu VW, dystans i godzina przyjazdu (strzałka pokazuje się, gdy auto ruszy),
    a do tego pasy ruchu, pasek odległości przed skrętem i nazwa ulicy.
      - Wszystko działa: otwórz zielone menu i naciśnij "4. Confirm: everything works"
        W TYM SAMYM STARCIE (nie wyłączaj auta przed tym).
      - Coś jest nie tak albo ekran zostaje czarny: po prostu zrób restart
        (pokrętło głośności 10 s).
        Bez Confirm następny start jest oryginalny, fabryczny. Nie trzeba niczego naprawiać.
        Żeby spróbować jeszcze raz: "5. Try again", potem restart.

  Krok 5. Jeszcze jeden restart (pokrętło głośności 10 s). Gotowe: od teraz tak to działa.

  Żeby usunąć wszystko: "Remove everything (back to factory files)", potem restart.
  "Status (read-only)" pokazuje, co jest zainstalowane.

  AKTUALIZACJA z wcześniejszej wersji (v1.0 - v1.3):
    1. Zrób KARTĘ 1 z tej paczki. W aucie: "1. Check card and unit (read-only)".
       Oczekiwane: PMCP_VERIFY_OK state=JAVA. "Status (read-only)" może pokazać
       "Route guidance system: old" i "packages of an earlier card: rglu" - tak ma być.
    2. "3. Install all features or update: ..."  ->  PMCP_ALL_ON_OK
    3. Restart: ten start jest PRÓBNY. Sprawdź strzałki, pasy, nazwę ulicy.
    4. "4. Confirm: everything works" w tym samym starcie, potem restart.
    5. Zrób NOWĄ KARTĘ 2 pomocnikiem kopiowania (opcja 2): karty ratunkowe sprzed v1.4
       nie przywracają nowego sterownika prowadzenia.
    Używałeś karty eksperymentalnej z Android Auto? Krok 1 pokaże wtedy stan UNKNOWN; tak
    ma być. Przycisk 3 najpierw przywraca fabryczne Android Auto, potem aktualizuje resztę.

------------------------------------------------------------------------------------------
AWARIA - KARTA 2 (RATUNKOWA)
------------------------------------------------------------------------------------------
  Tylko jeśli po naciśnięciu Confirm ekran zostaje czarny albo ciągle się restartuje,
  a przytrzymanie pokrętła głośności ~10 s nie pomaga:
    1. Włóż KARTĘ 2 do slotu SD1 i poczekaj do 60 sekund. Radio samo wchodzi w tryb
       aktualizacji i może kilka razy się zrestartować. Jeśli o coś zapyta, wybierz Kontynuuj.
       NIE wyjmuj karty podczas aktualizacji.
    2. Gdy wróci normalny ekran, wyjmij kartę. Funkcje są znowu wyłączone; obraz mapy
       zostaje. W zielonym menu: "Remove everything (back to factory files)", jeśli chcesz
       cofnąć też mapę.
    3. Karta po użyciu sama się rozbraja, więc nie uruchomi się ponownie przypadkiem. Żeby
       przygotować ją na następny raz: na komputerze uruchom pomocnika kopiowania i wybierz 3
       (pokazuje też wynik przebiegu; RESULT=OK = zadziałała).
  Opcjonalnie: przed krokiem 1 możesz raz sprawdzić KARTĘ 2 na działającym radiu. W radiu
  bez naszych plików niczego nie zmienia. Potem uzbrój ją ponownie pomocnikiem kopiowania,
  opcja 3.

  Pojedyncze funkcje i inne układy mapy są w podmenu  pmcp_advanced  (napisy po angielsku,
  opisane w docs/tutorial-w-aucie.pl.md).
