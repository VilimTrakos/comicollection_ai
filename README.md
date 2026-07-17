# Comicollect

Offline-first Flutter aplikacija za privatnu kolekciju stripova. Promjene se
spremaju u SQLite na uređaju i sinkroniziraju kroz revision-based protokol kada
je mreža dostupna. Produkcijski način rada ima stvarne račune i potpuno
izolirane kolekcije; stari single-user Raspberry Pi LAN način ostaje kao
eksplicitna kompatibilna opcija.

## Što je implementirano

- Android Flutter aplikacija u `app/` (nije web wrapper)
- dashboard, kolekcijski hub, statistika, filtrirani popisi i polica po serijalima
- napredna pretraga po serijalima/brojevima s lokalnom poviješću pretraga
- katalogom potpomognut ručni unos i skupni unos raspona s iznimkama
- dodavanje, uređivanje, detalji izdanja i sinkronizirano brisanje
- pametno skeniranje: automatski barkod i naslovnica, ručna fotografija police
- lokalno OCR čitanje hrptova te pregled i skupno označavanje imam/nemam
- BSP DDLU, DSLU i DMLU testni katalog te komprimirane WebP naslovnice ugrađene u aplikaciju
- imam/pročitano, M/VF/F/G/P, cijena/vrijednost, dupli, posuđeno i bilješke
- ocjena, broj stranica, scenarist i crtač u lokalnoj bazi i sinkronizaciji
- lokalne postavke teme, naglasne boje, naslova, statistike, synca i praćenja izdanja
- lokalna SQLite baza i CSV izvoz u međuspremnik
- revision-based sync v2 s trajnim outboxom, idempotentnim retryjem i paginacijom
- cross-device prijenos svih primjeraka, stanja kolekcije i naučenih barkodova
- registracija/prijava, kratkotrajni access tokeni i rotirajuće refresh sesije
- Android Keystore-backed spremanje refresh credentiala; access token je samo u memoriji
- zasebna auth baza i zasebna Sync v2 baza za svaki račun
- produkcijski Gunicorn/nginx/systemd profil s TLS granicom i throttlingom
- kompatibilni Raspberry Pi LAN server bez vanjskih Python paketa
- online SQLite backup cijele account generacije s lokalnom rotacijom 14 kopija

## 1. Produkcijski backend

Javni backend pokreće se iza nginx TLS reverse proxyja kao jedan ograničeni
Gunicorn `gthread` worker. Konfiguracija je fail-closed: bez pepper tajne od
najmanje 32 bajta proces se ne pokreće, a javna registracija mora se uključiti
eksplicitno. Potpuna priprema hosta, systemd hardening, nginx predložak, backup i
restore postupak opisani su u
[`docs/production-deployment.md`](docs/production-deployment.md). Account i
HTTP ugovor opisan je u [`docs/backend-auth.md`](docs/backend-auth.md).

Ovo je profesionalna single-node osnova za kontrolirani beta rollout. Prije
horizontalnog skaliranja potrebni su PostgreSQL i zajednički rate limiter;
prije javne registracije potrebni su i potvrda e-maila, oporavak lozinke te
privacy/export/delete workflow.

## 2. Kompatibilni Raspberry Pi LAN server

Pi i telefon trebaju biti na istoj kućnoj mreži. Kopiraj direktorij `server` na
Pi i pokreni samo:

```bash
cd server
sudo ./install.sh
```

Skripta zadržava postojeći `COMICOLLECT_MODE=legacy`, ispisuje adresu servera i
jedinstveni API token. Servis se automatski pokreće nakon restarta Pi-ja.

Korisne administratorske naredbe:

```bash
systemctl status comicollect
journalctl -u comicollect -f
systemctl list-timers comicollect-backup.timer
```

Baza je u `/var/lib/comicollect/comicollect.sqlite3`, backupi su u
`/var/backups/comicollect/`, a tajna u `/etc/comicollect.env`. DHCP rezervacija
za Pi u postavkama routera sprječava promjenu njegove IP adrese. Port 8787 ne
prosljeđuj na internet; ova konfiguracija je namjerno samo za pouzdani kućni LAN.

Ponovno pokretanje `sudo ./install.sh` sigurno nadogradi server i zadržava bazu,
token i backupe.

## 3. Android aplikacija

Razvoj s lokalnim backendom na Android emulatoru:

```bash
cd app
flutter pub get
flutter run --dart-define=COMICOLLECT_API_URL=http://10.0.2.2:8787
```

Debug build dopušta plaintext HTTP samo za `localhost`, `127.0.0.1` i Android
emulator adresu `10.0.2.2`. Release build prihvaća samo HTTPS origin.

Instalacijski release APK:

```bash
cd app
flutter build apk --release \
  --dart-define=COMICOLLECT_API_URL=https://api.example.com
# build/app/outputs/flutter-apk/app-release.apk
```

Za Google Play napravi vlastiti upload key prema Flutter/Play uputama, dodaj
release signing konfiguraciju izvan repozitorija i izgradi AAB:

```bash
flutter build appbundle --release \
  --dart-define=COMICOLLECT_API_URL=https://api.example.com
# build/app/outputs/bundle/release/app-release.aab
```

Repozitorij namjerno ne sadrži privatni signing ključ. Prije javne objave treba
još unijeti naziv izdavača, store listing, screenshotove, privacy-policy URL i
ispuniti aktualne Google Play deklaracije. Za osobnu instalaciju na vlastiti
telefon release APK je dovoljan.

## Provjera

```bash
cd app
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
dart tool/catalog_pipeline.dart validate
flutter test --coverage

cd ../server
python3 -m unittest discover -v
```

Isti se paket automatski izvršava u GitHub Actionsu pri svakom pushu i pull
requestu. CI zahtijeva najmanje 80% line coveragea. Vizualne regresije ključnih
ekrana nalaze se u `app/test/goldens/`; nakon namjerne promjene dizajna obnovi
ih naredbom `flutter test --update-goldens test/visual_regression_test.dart` i
pregledaj PNG razlike prije commita.

## Struktura Flutter koda

- `lib/main.dart` — samo startup i pokretanje aplikacije
- `lib/comicollect.dart` — javni package API za testove i druge klijente
- `lib/app_controller.dart` — tanki UI facade i `ChangeNotifier` stanje
- `lib/app/` — korijenski `MaterialApp`
- `lib/config/` — validirana build/runtime konfiguracija
- `lib/features/` — auth, shell, home, collection, comics, search, scanner i settings
- `lib/ui/` — tema i zajednički prezentacijski widgeti
- `lib/data/` — SQLite, auth/sync transporti te collection/settings repozitoriji
- `lib/models/` — domenski modeli bez UI ovisnosti
- `lib/services/` — auth sesija, inicijalizacija kataloga i sync koordinacija

Featurei razgovaraju s `AppController` facadeom, a trajna pohrana, postavke,
katalog i sinkronizacija imaju zasebne testabilne granice. `main.dart` ne sadrži
poslovnu logiku. Stari scanner import u `lib/screens/` ostaje samo kao
kompatibilni re-export.

Lokalna schema v6 odvaja `catalog_issues`, korisničke `collection_entries` i
1:N fizičke `copies`, te dodaje trajni sync outbox, server cursor i reviziju po
entitetu. Stare v1-v5 baze migriraju se unutar jedne SQLite transakcije. ID
primjerka je distribuirani identitet; ordinal služi samo za prikaz, pa dva
offline uređaja mogu dodati primjerke bez međusobnog prepisivanja.

Sync v2 je primarni protokol. Server dodjeljuje strogo rastuće revizije, svaku
mutaciju primjenjuje atomarno i prepoznaje ponovljeni mutation ID nakon prekida
mreže. Lokalni zapis i njegov outbox nastaju u istoj transakciji, a primljeni
podaci i cursor također se spremaju zajedno. Sat uređaja zato ne odlučuje o
konfliktima. Ugrađene naslovnice i metadata-only katalog ne šalju se na server;
sinkroniziraju se korisničko stanje, fizički primjerci, custom izdanja i naučeni
barkodovi. Potpuni wire contract i rollout pravila su u
[`docs/sync-v2.md`](docs/sync-v2.md).

Klijent pada na `/api/v1/sync` samo kada stari server doista nema v2 endpoint i
još nije zapamćen identitet v2 servera. Nakon aktivacije v2 server odbija nove
v1 upise jer ravna v1 projekcija ne može sigurno predstaviti više primjeraka;
stari klijenti još mogu čitati kompatibilnu projekciju tijekom nadogradnje.
Prijelaz je otporan na prekid procesa: trajni marker i outbox high-water čuvaju
unos nastao tijekom mrežnog zahtjeva, a nakon restarta aplikacija dovršava v1
oporavak prije v2 baselinea. Stare vrijednosti izvan strogog wire ugovora
normaliziraju se uz sačuvan izvorni JSON i vidljivo upozorenje za pregled.

## Lokalni katalog

Katalog i naslovnice ne uređuju se mrežnim pozivima iz aplikacije. Reproducibilni
alat radi isključivo nad lokalnim datotekama:

```bash
cd app
dart tool/catalog_pipeline.dart validate
dart tool/catalog_pipeline.dart import-cover /putanja/naslovnica.jpg \
  assets/catalog/covers/ddlu/0202.webp
dart tool/catalog_pipeline.dart refresh-signatures
```

`validate` provjerava shemu, jedinstvene identifikatore, popis edicija, postojanje
i WebP format svake naslovnice te podudaranje vizualnih potpisa. CI izvršava istu
provjeru. `import-cover` lokalno normalizira orijentaciju, ograničava širinu i
sprema WebP; nakon dodavanja ili promjene slike treba pokrenuti
`refresh-signatures`, pregledati JSON diff i ponovno pokrenuti `validate`.

Top-level `catalogVersion` u JSON-u monotono povećaj kada se promijene izdanja
ili metadata koja se preslikava u lokalnu bazu. Aplikacija pamti zadnju uspješno
primijenjenu verziju i svaki katalog osvježava točno jednom, pri čemu zadržava
korisničko stanje kolekcije. Promjena samo unaprijed izračunatog vizualnog
potpisa ne zahtijeva novu verziju jer se potpisi čitaju izravno iz asseta.

## Prototip

Originalni dizajn ostaje u `prototype/` kao vizualna referenca. Implementacija
koristi njegovu near-black/crvenu/tan paletu, cover placeholder stil i centralni
FAB navigation pattern.

## Testni BSP katalog

Tekstualni podaci za testiranje mogu se obnoviti iz javnih BSP popisa. Izvorni
veliki JPEG-ovi spremaju se samo u lokalni, gitignorirani `.catalog_cache/`; ne
ulaze u APK ni repozitorij:

```bash
python3 tools/import_bsp_catalog.py --download-covers
```

Kada novi uvoz mijenja katalog koji je već bio objavljen, proslijedi i novu
monotono veću verziju, primjerice `--catalog-version 2`. Alat odbija eksplicitnu
verziju koja nije veća od postojeće. Bez tog argumenta zadržava
`catalogVersion` iz postojeće izlazne datoteke za identičan rebuild.

Importer pri ponovnom pokretanju koristi spremljeni HTML. Dodaj `--refresh`
kad želiš ponovno dohvatiti aktualne BSP popise.

Mali JSON pogodan za aplikaciju nalazi se u
`app/assets/catalog/bsp_catalog.json`. Razvojni JPEG cache pretvara se u WebP
Flutter assete pomoću `tools/build_cover_assets.py`. U APK ulaze komprimirane
slike 240x320, tekst kataloga i unaprijed izračunati vizualni potpisi. Aplikacija
ih prikazuje i koristi za prepoznavanje bez pristupa mreži; tijekom rada ništa
ne dohvaća s BSP-a. Izvorni veliki JPEG-ovi ostaju izvan repozitorija.

Prije javne distribucije naslovnica treba dogovoriti pravo korištenja s
vlasnikom izvora.

Ako su `cwebp` i `dwebp` instalirani u sustavu:

```bash
python3 tools/build_cover_assets.py --cwebp cwebp --dwebp dwebp
```
