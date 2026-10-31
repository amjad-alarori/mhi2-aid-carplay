# Paczka D: tytuł i wykonawca utworu CarPlay na AID

[English version: README.md](README.md)

Stan: **działa w aucie (MU1161 + AID 791, październik 2026).** JAR: `build/np-mu1161-v2/pmcp-np.jar` (17,928 B, `6b638868…dc23`;
v2 2026-10-22: wszystkie 4 wywołania helpera osłonięte `buildtools/Guard.java`, kontrola API J9 `RefCheck`;
v1 `1af4d5e8…761b`).

## Dlaczego fabrycznie jest tylko „Apple CarPlay”

- Cel ASL CarPlay (`HsmTarget`) subskrybuje atrybuty DSI `{8,7,8,2,9,12}`, **bez 3** (`ATTR_NOWPLAYINGDATA`).
  HMI w ogóle nie dostaje tytułu, choć iPhone go wysyła (iAP2 NowPlaying działa fabrycznie).
- BAP AudioSD `CurrentStationInfo.setStationInfoForMirrorLink()` wysyła do licznika tylko `primaryInformation = "Apple CarPlay"`.

## Jak to działa

Trzy hooki ASM w klasach fabrycznych MU1161 (`patcher/PatchNp.java`, każdy z asercją wzorca i liczby trafień):

| Klasa.metoda | Hook |
|---|---|
| `HsmTarget.initializeDSI` | po fabrycznym `dsiCarplay.setNotification(...)`: `NowPlaying.attach(dsiCarplay)` rejestruje **własnego** słuchacza na atrybut 3 |
| `CurrentStationInfo.init` / `uninitialize` | `NowPlaying.register(this)` / `unregister(this)` |
| `CurrentStationInfo.setStationInfoForMirrorLink` | na wejściu: przy CarPlay (typ połączenia 2) i znanym tytule wpisuje tytuł (typ 72), wykonawcę (73), album (74) i kończy; inaczej kod fabryczny |

Sprawdzone w źródłach:
- **Refleksja celów ASL jest generowana przy budowie firmware'u** (`ModuleReflectionFactory`), więc nie dopisujemy metody do `HsmTarget`.
  Zamiast tego zwykła klasa implementuje `DSICarplayListener`; rozsyłanie DSI rzutuje słuchacza na interfejs i woła metodę bezpośrednio.
- `DSIProxyTarget` trzyma maskę atrybutów **osobno dla każdego słuchacza**, więc nasz słuchacz nie zmienia tego, co dostaje HMI.
  Nowy słuchacz od razu dostaje bieżącą wartość z pamięci podręcznej (`NotificationDatapool.getAvailable`).
- Zmiana utworu trafia do wątku BAP przez fabryczny `ThreadSwitchingService.enqueue(Runnable)` (jak w `ASLDataPoolAdapter`),
  który wywołuje `CurrentStationInfo.process(-1)`.
- Typy pól 72/73/74 jak w fabrycznym `setStationInfoForMediaExternalDevice` / `setArtistAndAlbum`.

Każdy hook łapie własne wyjątki: błąd tutaj zostawia fabryczne „Apple CarPlay”, nie psuje CarPlay ani licznika.
Tytuł jest przycinany do 80 znaków. AA i MirrorLink zostają fabryczne.

## Budowanie

```sh
ASM_DIR=upstream/tools/jxe2jar/repo/tools/uninline/lib \
  nowplaying/build.sh archives/x-mu1161/jar/lsd-mu1161.jar build/np-mu1161
```

Wynik: weryfikator ASM OK, klasy w wersji 46 (stockowe `HsmTarget` i `CurrentStationInfo` z konwertera mają 49; patcher obniża
je dopiero po sprawdzeniu braku literałów klas), stałe w obu klasach identyczne ze stockiem, test hosta 13/13 (`test/TestNp.java`).

## Czego nie wiemy przed autem

- czy licznik pokazuje drugą i trzecią linię dla źródła „smartfon” (dla multimediów pokazuje);
- czy `ThreadSwitchingService` jest gotowy w chwili pierwszej zmiany utworu (jeśli nie, pokaże się przy następnej aktualizacji).

W instalatorze: paczka Java `np` (GEM → pmcp → etap B → „Wlacz: Tytul i wykonawca”).
