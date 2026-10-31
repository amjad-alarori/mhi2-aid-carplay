# NavActiveIgnore z własnych klas firmware'u

[English version: README.md](README.md)

Nasz odpowiednik łatki „Ignore navigation-active status from smartphone”. Gdy iPhone prowadzi, HMI nie zgłasza
„nawigacja w telefonie”, nie zatrzymuje nawigacji VW i nie zabiera telefonowi prowadzenia. Dzięki temu mapa
na AID dalej działa, a CarPlay zachowuje swoje prowadzenie.

Podstawa: Tomasz (tomasz-twardzicki), `upstream/tomasz/MU1427/NavActiveIgnore/`, GPL-3.0-or-later.
Pomysł oryginalny: MQB Toolbox `NavActiveIgnore.jar`.

## Dlaczego nie generyczny JAR

Generyczny JAR (`CarPlayNavigationPatch.jar` u mathsls i omonob, SHA-256 `a4803f7f…`) podmienia całe klasy HMI
skompilowane z wadliwej dekompilacji:
- stałe int mają odwróconą kolejność bajtów: 100012 → -1400504064, 2910009 → 963062784;
- stałe long są wyzerowane (timeouty 5000 ms i 300 ms stają się 0);
- na gorących ścieżkach jest `printStackTrace`.

Nasz build bierze **fabryczne klasy** z przekonwertowanego `lsd.jxe` i zmienia tylko wskazane instrukcje (ASM).
Każda zmiana sprawdza dokładny wzorzec i liczbę trafień, a przy niezgodności build się przerywa.

## Zmiany (K4525)

| Klasa | Zmiana |
|---|---|
| `DSICarplayProxy.requestModeChange` | usuwa z żądań do iPhone'a „natywna nawigacja przejmuje” (`appStateID=2, state=true, speechMode=0`); całe wywołanie pomija tylko wtedy, gdy nic innego nie zostaje |
| `CarPlayModeHandling.handleModeChanges` | gdy prowadzi CarPlay: bez `valueChangedBoolean(2910009, true)`, bez `setActiveNavigation(2)`, bez `stopGuidance(6)`; gdy prowadzi HMI: bez `requestModeChange(…, "User initiated")` |
| `ASLNavigationServices.stopGuidance` | ignoruje powód 6 (smartfon przejął nawigację) |
| AA `NavigationListener` | `updateGuidanceActive` i `stopGuidance` nic nie robią, `isGuidanceActive` zwraca false |
| AA `RequestHandler.performNavFocusRequestNotification` | oba typy fokusu jak „projected”, bez `stopGuidance()` i bez `valueChangedBoolean(2910005, true)` |

Różnice względem MU1427 (Tomasz): inne ID właściwości (2910009 i 2910005 zamiast 3010002 i 3110002), switch
w `RequestHandler` obsługiwany w obu formach (table i lookup). Wywołania exbox
(`setSmartphoneGuidanceActive/Inactive`, tylko K4525) zostają fabryczne: trafiają wyłącznie do `DSIExBoxM`,
zewnętrznej skrzynki nawigacji.

Celowo **bez** zmiany data rate (`ChangeDataRate`/`ChangeDataRateSequence`). U Tomasza obie próby zawiesiły mapę
na „loading map”.

## Budowanie

```sh
ASM_DIR=upstream/tools/jxe2jar/repo/tools/uninline/lib \
  navactiveignore/build.sh K4525 archives/x-k4525/jar/lsd-k4525.jar build/nai-k4525
```

Skrypt:
- sprawdza hashe ASM 9.7 i przekonwertowanego jar;
- łata klasy, weryfikuje je (ASM `SimpleVerifier`) i wymusza wersję klas 46 (fabryczny J9; desktopowa Java przyjmie 49 i nie wyłapie błędu);
- robi raport `report/*.diff` (javap, fabryczne a patchowane);
- pakuje deterministyczny JAR i uruchamia test hosta (`-Xverify:all`, logika helpera);
- zapisuje `manifest.txt` z hashami wejść i wyjść.

Wynik K4525 (2026-10-20): `NavActiveIgnore.jar`, 13,214 B, SHA-256
`a6781738a658aa64151e24e481af726347cc99967f0a5a24b530b66215cd9c7b` (powtarzalny).

## Status i ograniczenia

- **Profil MU1161 (nasze auto, backup 2026-10-21):** pięć łatanych klas jest bajtowo identycznych z K4525, ID właściwości
  te same. Wynik `build/nai-mu1161/NavActiveIgnore.jar`, SHA-256 `823adeb022363aafc66979670e9cf4a6c58ac45297f2f2eea1680f825881ba2d`.
- **v2 (2026-10-22, po code review):** oba wywołania helpera w `DSICarplayProxy.requestModeChange` są osłonięte
  (`buildtools/Guard.java`: przy błędzie helpera zostaje fabryczne żądanie), build sprawdza API J9 (`buildtools/RefCheck.java`).
  Wynik `build/nai-mu1161-v2/NavActiveIgnore.jar`, 13,285 B, SHA-256 `dbd031ecb28a2ec91c4704e133f4e2126cf1fe11498f673bc2e07fc0b1aaa7ab`.
  Klasy są identyczne z buildem K4525, różni się tylko MANIFEST.MF. Instalujemy JAR z profilu zgodnego z firmware'em w aucie.
- Nie testowany na fabrycznym J9 (Tomasz uruchamiał ARM J9 pod QEMU) ani w aucie.
- Instalacja (wpis `-Xbootclasspath/p:` w `lsd.sh`, kopia zapasowa, rollback) należy do instalatora fail-closed.
  Odzysk: usunąć JAR z `/mnt/app/eso/hmi/lsd/jars/`; J9 pomija brakujące wpisy bootclasspath (Tomasz).
- Zastępuje generyczny `CarPlayNavigationPatch.jar`. Nie instalować obu naraz.
