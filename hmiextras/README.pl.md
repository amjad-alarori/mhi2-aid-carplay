# Paczki F (zoom z kierownicy) i G (dzień/noc mapy na AID)

[English version: README.md](README.md)

Stan: **zainstalowane w aucie (MU1161 + AID 791, październik 2026): zoom działa; dzień/noc mapy przełącza się poprawnie (nie sprawdzano osobno, ile w tym zasługi paczki G).** Build: `hmiextras/build.sh` →
`build/extras-mu1161-v2/pmcp-zoom.jar` (4,740 B, `046f4821…8d7b`) i `pmcp-dn.jar` (11,421 B, `aabe871e…fbd70`)
(v2 2026-10-22 po code review; v1 `ea90f988…`, `4e637d9a…`).
Każde wywołanie naszego kodu z klas fabrycznych jest osłonięte (`buildtools/Guard.java`): jeśli J9 nie załaduje helpera, działa
ścieżka fabryczna. Test `test/TestZoomGuard.java`: łatany `updateKey2` bez klas `com/pmcp/zoom` nie rzuca LinkageError.

## F: zoom mapy CarPlay strzałkami na kierownicy

- Hook ASM na wejściu fabrycznego `DSIKeyPanelDispatcher.updateKey2(keyboard, key, state, p3, valid)` (MU1161):
  `if (keyboard == 4) ZoomHook.onKey2(...)` (filtr inline, inne klawiatury nie dotykają naszego kodu), wywołanie osłonięte.
- Klawiatura MFW (4), klawisze góra/dół (38/39). **Tylko krótkie naciśnięcie:** `zoom-in` / `zoom-out`; powtórzenia trzymanego klawisza
  ignorowane. **Bez akcji długiego przytrzymania** (mathsls wysyła po 2.5 s `map-previous`/`map-next`, co `core.so` zamienia
  w przełączenie aplikacji klastra; przytrzymaniem przewija się też listy licznika; code review 2, finding 3).
  Polecenie idzie przez UDP na `127.0.0.1:7032` do `core.so` (`map_control_command_worker` → `changeMapZoomLevel`), z jednego wątku
  demona i jednym gniazdem. Protokół i kody klawiszy jak w `Mhi2ClusterControlBridge` (omonob/mathsls); kod mostka nie jest już używany.
- Klawisz **nie jest przejmowany**: fabryczna obsługa (np. przewijanie menu licznika) działa dalej. Skutek: strzałka w menu licznika
  zmienia też zoom mapy CarPlay (do sprawdzenia w aucie, czy to przeszkadza).
- Test hosta: prawdziwy pakiet UDP `zoom-in` i `zoom-out` odebrany na porcie 7032; przytrzymanie 3 s ze stanami 3/4/5 nic nie wysyła;
  inne klawiatury i klawisze nic nie wysyłają.
- Znane z issues omonob: #49/#50 („zoom nie działa” na Golfie 7 v1.2.2), #48 („OK nie resetuje zoomu”). Sprawdzimy w aucie.

## G: mapa na AID w nocnym trybie po starcie w dzień (omonob #51)

- Fabrycznie tryb nocny idzie do telefonu raz, w `startService(ServiceConfiguration)`, a potem tylko przy zmianie
  (`ASLHandler.handleDayNightMode` → `requestNightMode`). Ekran klastra (altscreen) pojawia się kilka sekund później.
- Hook ASM w `ASLHandler` zaraz po jedynym `startService(...)` → `DayNight.sessionStarted(target, properties)`.
  Wątek demona po 5, 15 i 30 s wysyła **do celu CarPlay** fabryczne zdarzenie 4300038 (DAYNIGHT_MODE) przez `triggerMe`
  (kolejka dyspozytora, wątek celu). Fabryczne `handleDayNightMode` wywołuje `requestNightMode` tylko przy połączeniu.
- Wartość nie jest czytana w naszym wątku (realna zmiana czekająca w kolejce zostałaby nadpisana starą wartością; review 2,
  finding 6): zdarzenie niesie znacznik w parametrze 1, a drugi hook na wejściu fabrycznego `handleDayNightMode` (wątek celu)
  wpisuje `properties.isNightMode()` w chwili obsługi i usuwa znacznik. Realne zdarzenia przechodzą bez zmian (test).
  Po rozłączeniu wątek kończy.
- Wzór: chefranov v1.1.4 (`altscreen_night_resend`, „still to be confirmed in daylight”). Jeśli ponowne wysłanie tej samej wartości
  nie wystarczy (telefon ignoruje „bez zmian”), następny krok to krótkie przełączenie noc→dzień. To osobny wariant, nie zbudowany.
- `ASLHandler` MU1161 = K4525 bajtowo, wersja 46.

W instalatorze: paczki Java `zoom` i `dn` (GEM → pmcp → etap B → „Wlacz: …”), z tym samym próbnym startem co reszta.
