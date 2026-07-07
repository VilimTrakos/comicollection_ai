# Comicollect

Aplikacija za vođenje kolekcije stripova (Bonelli, DC, Marvel, nezavisni izdavači) —
praćenje serijala i edicija, pročitano/posjedovano, stanje primjeraka (M/VF/F/G/P),
tražim/dupli/posuđeno, najave izlazaka, CSV uvoz/izvoz te enterprise način rada za
knjižnice i strip-dućane (inventar po pozicijama, članovi, posudbe, rezervacije).

## Struktura repozitorija

| Putanja      | Sadržaj                                                              |
|--------------|----------------------------------------------------------------------|
| `prototype/` | Referentni dizajn-prototip (React + Babel u browseru, claude.ai/design) |
| `app/`       | Flutter aplikacija (implementacija prototipa)                        |

## Prototip (referenca dizajna)

Statički server iz korijena repozitorija:

```bash
python3 -m http.server 8080
# → http://localhost:8080/prototype/Comicollect%20Redizajn%20Prototip.html
```

Napomena: PNG naslovnice u `prototype/figma-style/assets/` su okrnjene (limit
MCP transfera) — prototip i aplikacija koriste stilizirane placeholder naslovnice.

## Flutter aplikacija

```bash
cd app
flutter pub get
flutter run -d web-server --web-port 8081   # razvoj (hot reload)
flutter build web                            # produkcijski build → build/web
```
