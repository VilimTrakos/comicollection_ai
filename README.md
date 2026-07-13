# Comicollect

Offline-first Flutter aplikacija za privatnu kolekciju stripova, s laganim LAN
sync serverom za Raspberry Pi 3B+. Aplikacija radi i kada je server ugašen;
promjene se čuvaju u SQLite bazi na telefonu i automatski sinkroniziraju kada je
Pi dostupan na kućnoj mreži.

## Što je implementirano

- Android Flutter aplikacija u `app/` (nije web wrapper)
- dashboard, polica po serijalima, pretraga i detalji izdanja
- dodavanje, uređivanje i sinkronizirano brisanje
- pametno skeniranje: automatski barkod i naslovnica, ručna fotografija police
- lokalno OCR čitanje hrptova te pregled i skupno označavanje imam/nemam
- BSP DDLU, DSLU i DMLU testni katalog te komprimirane WebP naslovnice ugrađene u aplikaciju
- imam/pročitano, M/VF/F/G/P, cijena/vrijednost, dupli, posuđeno i bilješke
- lokalna SQLite baza i CSV izvoz u međuspremnik
- tokenom zaštićen incremental sync s pravilom "novija promjena pobjeđuje"
- Raspberry Pi server bez vanjskih Python paketa
- systemd autostart, restart nakon greške i dnevni SQLite backup (14 kopija)

## 1. Server na Raspberry Pi

Pi i telefon trebaju biti na istoj kućnoj mreži. Kopiraj direktorij `server` na
Pi i pokreni samo:

```bash
cd server
sudo ./install.sh
```

Skripta ispisuje adresu servera i jedinstveni API token. Spremi ih u
**Postavke** aplikacije. Servis se automatski pokreće nakon restarta Pi-ja.

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

## 2. Android aplikacija

Razvojni APK:

```bash
cd app
flutter pub get
flutter run
```

Instalacijski release APK:

```bash
cd app
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

Za Google Play napravi vlastiti upload key prema Flutter/Play uputama, dodaj
release signing konfiguraciju izvan repozitorija i izgradi AAB:

```bash
flutter build appbundle --release
# build/app/outputs/bundle/release/app-release.aab
```

Repozitorij namjerno ne sadrži privatni signing ključ. Prije javne objave treba
još unijeti naziv izdavača, store listing, screenshotove, privacy-policy URL i
ispuniti aktualne Google Play deklaracije. Za osobnu instalaciju na vlastiti
telefon release APK je dovoljan.

## Provjera

```bash
cd app && flutter analyze && flutter test
cd ../server && python3 -m unittest -v test_server.py
```

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
