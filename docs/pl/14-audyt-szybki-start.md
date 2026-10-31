# Audyt: szybki start mapy na AID (próby, porażka, temat zamknięty)

[English version](../en/14-fast-start-audit.md)

Jednostka: Discover Pro MHI2 MU1161 (train `MHI2_ER_VWG13_P4512`) z AID 791, VW Passat B8 MY2018. Próby: 2026-10-31.
**Wynik: brak zysku, a jedna z prób wprowadziła AID w stan błędu, z którego wyszedł dopiero po uśpieniu auta. Nic z tego
nie weszło do v1.3.0. Temat zamknięty.**

## Cel

Po zimnym starcie strumień CarPlay dla AID jest gotowy po ok. 26 s (zdarzenie supervisora `bridge-ready`). Mapa pojawia
się na AID dopiero po ok. 43 s. Celem było pokazanie mapy CarPlay po ok. 26-30 s.

## Co blokuje mapę (ustalone w trakcie prób)

Kolejność poniżej pochodzi ze zdekompilowanych klas HMI MU1161 i konfiguracji startu jednostki. Potwierdziły ją logi z auta.

1. HMI startuje w jednym wątku (start ASL `startupv7r`, `TASK_POOL_COUNT=1`). Jednostki pracy i ich kolejność są
   w `configurationmanager.res` w `/ifs/hmi/res` (79 jednostek).
2. Jednostka #43 `SPECIAL_METHOD_WAITFOR_NAV_TO_FINISH` trzyma ten jedyny wątek, aż nawigacja VW zgłosi
   `EV_NAV_IS_COMPLETELY_READY`, czyli ok. 43 s od startu jednostki (timeout 60 s).
3. Jednostki licznika są za nią: #46 `FPK_GENERIC` (odbiornik wideo licznika, `DSIKOMOGfxStreamSink`) i #47
   `FPK_NAV_KOMO` (warunek: #43 po nazwie).
4. Moduł licznika (`mostkombi`) uruchamia odbiornik wideo dopiero, gdy zgłoszą się 3 kontrolery. Odbiornik zgłasza się
   dopiero, gdy odbiornik wideo MOST poda stan 1.
5. Nawet wtedy `WaitForServices` odbiornika otwiera strumień dopiero, gdy jednocześnie:
   - mapa licznika nawigacji VW poda status 2 (`1110044 == 2`);
   - wyświetlacz licznika jest znany (`KombiDisplay != -2`);
   - AID zgłasza, że może pokazać mapę (`MostCapabilityForMap == 2`).

Mapa CarPlay czeka więc na nawigację VW dwa razy: w kolejce startu i na bramce odbiornika.

## Próby

Wszystkie próby były pakietami Java ładowanymi przez mechanizm próbny instalatora: nowy zestaw ładuje się raz, a bez
Confirm następny start jest znowu fabryczny. Żadna nie została zatwierdzona.

| Pakiet | Co zmieniał | Wynik w aucie |
|---|---|---|
| kf (v1) | Bramka widziała status 2, gdy strumień CarPlay był gotowy. Pomijał też czekanie na odpowiedź nawigacji na „mapa widoczna”. | **Nieudane.** Po gotowości strumienia nikt ponownie nie sprawdził bramki, więc i tak otworzyła się fabrycznie po 43 s. Przez pominięcie odpowiedzi nawigacja VW zawisła na „ładowaniu”, także po restarcie. Odzyskane przyciskiem „AID fast start off” (powrót do zatwierdzonego zestawu). |
| kf2 | Timer co 1 s ponownie sprawdza bramkę, gdy strumień CarPlay jest gotowy. „Mapa widoczna” czeka, aż prawdziwy status nawigacji będzie 2, więc nigdy nie idzie za wcześnie. | **Bez zmian (ok. 40 s).** Log pokazał, że stan bramki zaczął się dopiero w 44,4 s i od razu przeszedł. Bramka nie była wąskim gardłem. kf2 był nieszkodliwy: nawigacja VW ładowała się normalnie. |
| kf3 | kf2 + sondy w starcie modułu licznika (tylko log). | **Tylko diagnoza.** Cały moduł licznika ruszył w 43,0 s: odbiornik, stan MOST i wszystkie 3 kontrolery. Przyczyną jest kolejka startu (wyżej), nie bramka. |
| kf4 | kf3 + zmiana kolejności startu HMI: jednostki licznika #46/#47 przed czekaniem na nawigację #43. Tylko gdy 4 jednostki mają dokładnie fabryczne warunki. | **Nieudane i zepsuło AID.** Przestawienie zadziałało (log: „cluster units moved before the navigation wait”), ale moduł licznika i tak ruszył dopiero w 40,0 s (zysk 3 s), bo jednostki przed nim też czekają na nawigację. Nawigacja VW w tym starcie próbnym nie wstała. |

## Co się zepsuło po kf4 i jak to naprawiono

- Po wyłączeniu kf4 (znowu ładował się zatwierdzony zestaw bez kf) AID stał na „Uruchamianie widoku mapy”. Nie było ani
  mapy VW, ani mapy CarPlay. Nawigacja VW na środkowym ekranie działała.
- Nie pomogły:
  - restart jednostki;
  - wyjęcie karty SD;
  - **Remove everything** (wszystkie pliki fabryczne, sprawdzone hashami);
  - reset fabryczny nawigacji w menu radia.

  Przyczyna nie leżała więc w plikach ani ustawieniach radia.
- Pomogło uśpienie magistrali: zapłon off, auto zamknięte na ok. 15-20 minut. Potem mapa VW na AID wróciła, a mapa
  CarPlay po ponownej instalacji.
- Najbardziej prawdopodobna przyczyna (niepotwierdzona): w starcie próbnym kf4 odbiornik dostał „status 2” od CarPlay
  w 40,1 s, zanim nawigacja VW narysowała mapę licznika. HMI wysłało wtedy do AID całą sekwencję mapy stałej:
  1. wygaszenie;
  2. kontekst 70;
  3. wybór prowadzenia;
  4. data rate 10;
  5. warstwa 3;
  6. rozjaśnienie.

  AID to osobny sterownik. Prawdopodobnie zapamiętał błąd źródła mapy i do uśpienia magistrali zgłaszał stan, którego
  fabryczna bramka (`KombiDisplay`, `MostCapabilityForMap`) nigdy nie przepuszcza. Restart radia nie resetuje AID.

## Dlaczego tą drogą się nie da

- Mapa licznika jest związana ze startem nawigacji VW (ok. 40-43 s), nawet po zmianie kolejności startu.
- Prawdziwy zysk wymagałby zmian w samym starcie nawigacji. To kod natywny i baza map, bez mechanizmu próbnego i bez
  bezpiecznego powrotu.
- Jedyne obejście to dawać AID komendy mapy przed gotowością nawigacji. Dokładnie to wprowadziło AID w opisany stan błędu.

## Wnioski (zasady projektu)

1. Nie zmieniać kolejności startu HMI.
2. Nigdy nie wysyłać do AID sekwencji mapy licznika (mapa widoczna, przełączenie kontekstu, data rate) przed prawdziwą
   gotowością nawigacji VW.
3. Gdy AID stoi na „Uruchamianie widoku mapy”, a pliki są fabryczne, najpierw niczego nie instalować ani nie resetować.
   Uśpić auto (zamknięte, 15-20 min).
4. Start próbny zadziałał za każdym razem: każdy nieudany pakiet znikał po jednym restarcie bez Confirm. Nie chroni
   jednak stanu zapisanego w innych sterownikach (AID).

## Tego samego dnia próbowane, niewydane

- **Dzień/noc licznika dla Google Maps.** Dwie próby:
  - „dzień/noc v2” wysyłał tryb nocny ponownie co 10 s;
  - moduł w `dio_manager` wysyłał `setNightMode` tylko dla wyświetlacza licznika, a potem dodatkowo oznaczał go jako
    „Instrument Cluster”.

  Telefon przyjmował każdą komendę (status 0), ale Google Maps na AID zostawały ciemne. Apple Maps przełączają się
  poprawnie drogą fabryczną. Temat zaparkowany. Co wiemy i jak to rozumiemy:
  - **Co wysyła radio.** Jedną wartość dla całej sesji CarPlay: `nightMode` (noc albo dzień). Radio wysyła ją przy
    połączeniu telefonu i przy każdej zmianie (np. po zapaleniu albo zgaszeniu świateł). Nie wysyła kolorów, motywów ani
    niczego dla konkretnej aplikacji. Telefon odpowiada na każdą komendę statusem 0. To znaczy tylko, że iOS przyjął
    wiadomość, a nie że każda aplikacja zmieniła wygląd.
  - **Oba obrazy rysuje telefon.** Ekran środkowy i mapa licznika przychodzą do radia jako gotowe wideo H.264. Radio nie
    może ich przemalować ani powiedzieć telefonowi „narysuj licznik jak ekran środkowy”.
  - **Co robią Google Maps (i Waze).** Ekran środkowy stosuje wartość poprawnie. Mapa licznika startuje ciemna. Prawdziwa
    zmiana (przełączenie świateł albo przełączenie aplikacji na iPhonie) rozjaśnia ją, ale tylko na chwilę; potem sama
    wraca do ciemnej. Ponowne wysłanie tej samej wartości nic nie daje; iOS albo aplikacja traktuje je jako „bez zmian”.
  - **Prawdopodobna przyczyna: stary odbiornik z doklejonym drugim ekranem.** Fabryczne MHI2 nigdy nie pokazywało CarPlay
    na liczniku; Apple dodało mapę licznika w iOS 13 (2019). Drugi ekran dokłada `core.so` (omonob) w `dio_manager`.
    Telefon widzi więc hybrydę: odbiornik AirPlay z ok. 2016 r., który zna tylko jeden globalny `nightMode`, plus doklejony
    ekran licznika. Radia z fabryczną mapą na liczniku prawdopodobnie przekazują więcej informacji o każdym ekranie, w tym
    jego styl jasny/ciemny. Apple Maps przy braku tej informacji wracają do `nightMode`; Google Maps najwyraźniej zostają
    przy domyślnym ciemnym stylu i nie pamiętają bieżącej wartości, gdy rysują widok licznika od nowa. To wniosek
    z zachowania, nie z kodu Google'a.
  - **Naprawa należy więc do Google'a.** Radio wysyła poprawną informację, a telefon ją potwierdza. To raczej przypadek,
    którego Google nie testował (radio z 2016 r. z dorobionym licznikiem), niż błąd w zwykłym sensie.
  - **Jedyne obejście po naszej stronie** to sztuczne „przełączenie świateł”: `dn` wysyła noc, a po ok. 1 s znowu
    prawdziwą wartość. Trzymałoby się tylko do ponownego ściemnienia przez Google Maps, radio nie widzi, kiedy ono
    następuje, a każde przełączenie może mignąć na środkowym ekranie i w Apple Maps. Niezbudowane. Ma sens tylko wtedy,
    gdy okaże się, że ciemną mapę przywraca konkretne zdarzenie (manewr, zoom, zmiana widoku licznika).
  - Większy lag Google Maps i Waze na AID oraz brak efektu `showSpeedLimit` mogą mieć tę samą przyczynę (telefon dostaje
    o ekranie licznika mniej informacji, niż oczekuje). Na to nie ma dowodu.
- **Pasy bez zawracania** (`rgl`): zastąpione przez `rglu` (pasy ze strzałkami zawracania), które jest w v1.3.0.
