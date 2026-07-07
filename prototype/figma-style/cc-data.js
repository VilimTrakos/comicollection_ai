// cc-data.js — seed data for the Figma-style Comics Collection design
// Series / editions modeled after the user's Figma file (Bonelli fumetti,
// Croatian publishers: Ludens, Veseli Četvrtak, Libellus).

(function () {
  const SERIES = [
    {
      id: 'dylandog',
      name: 'DYLAN DOG',
      house: 'Bonelli',
      cover: 'figma-style/assets/cover-dylandog.png',
      ph: { bg: '#E0C530', ink: '#C6291E' },
      editions: [
        { id: 'dd-orig',    name: 'ORIGINAL', publisher: 'Ludens',          total: 142, owned: 118, read: 96 },
        { id: 'dd-extra',   name: 'EXTRA',    publisher: 'Ludens',          total: 86,  owned: 71,  read: 64 },
        { id: 'dd-maxi',    name: 'MAXI',     publisher: 'Veseli Četvrtak', total: 17,  owned: 9,   read: 7  },
        { id: 'dd-gigant',  name: 'GIGANT',   publisher: 'Libellus',        total: 11,  owned: 5,   read: 5  },
        { id: 'dd-special', name: 'SPECIAL',  publisher: 'Ludens',          total: 19,  owned: 12,  read: 8  },
      ],
    },
    {
      id: 'tex',
      name: 'TEX',
      house: 'Bonelli',
      cover: 'figma-style/assets/cover-tex.png',
      ph: { bg: '#B5281E', ink: '#F2D02B' },
      editions: [
        { id: 'tex-orig', name: 'ORIGINAL', publisher: 'Libellus',    total: 120, owned: 64, read: 51 },
        { id: 'tex-maxi', name: 'MAXI',     publisher: 'Libellus',    total: 24,  owned: 8,  read: 6  },
        { id: 'tex-spec', name: 'SPECIAL',  publisher: 'Strip-agent', total: 14,  owned: 3,  read: 2  },
      ],
    },
    {
      id: 'zagor',
      name: 'ZAGOR',
      house: 'Bonelli',
      cover: null,
      ph: { bg: '#B5281E', ink: '#F2D02B' },
      editions: [
        { id: 'zg-orig',  name: 'ORIGINAL', publisher: 'Ludens', total: 96, owned: 40, read: 33 },
        { id: 'zg-extra', name: 'EXTRA',    publisher: 'Ludens', total: 44, owned: 12, read: 9  },
      ],
    },
    {
      id: 'misterno',
      name: 'MISTER NO',
      house: 'Bonelli',
      cover: null,
      ph: { bg: '#1F5FA8', ink: '#E8E2D4' },
      editions: [
        { id: 'mn-orig', name: 'ORIGINAL', publisher: 'Libellus', total: 68, owned: 22, read: 18 },
      ],
    },
    {
      id: 'martin',
      name: 'MARTIN MYSTÈRE',
      house: 'Bonelli',
      cover: null,
      ph: { bg: '#1E4A42', ink: '#E8C870' },
      editions: [
        { id: 'mm-orig', name: 'ORIGINAL', publisher: 'Libellus', total: 38, owned: 15, read: 11 },
        { id: 'mm-spec', name: 'SPECIAL',  publisher: 'Libellus', total: 8,  owned: 2,  read: 1  },
      ],
    },
    {
      id: 'kenparker',
      name: 'KEN PARKER',
      house: 'Bonelli',
      cover: null,
      ph: { bg: '#3A2C20', ink: '#E8C870' },
      editions: [
        { id: 'kp-orig', name: 'ORIGINAL', publisher: 'Fibra', total: 30, owned: 11, read: 10 },
      ],
    },

    // ── DC ──────────────────────────────────────────────────────────────
    {
      id: 'batman',
      name: 'BATMAN',
      house: 'DC',
      cover: null,
      ph: { bg: '#15171C', ink: '#F2D02B' },
      editions: [
        { id: 'bm-rebirth', name: 'REBIRTH',  publisher: 'Fibra',   total: 50, owned: 27, read: 21 },
        { id: 'bm-detective', name: 'DETECTIVE', publisher: 'Fibra', total: 38, owned: 14, read: 10 },
      ],
    },
    {
      id: 'superman',
      name: 'SUPERMAN',
      house: 'DC',
      cover: null,
      ph: { bg: '#1B4F9B', ink: '#E8302E' },
      editions: [
        { id: 'sm-action', name: 'ACTION', publisher: 'Fibra', total: 42, owned: 16, read: 12 },
      ],
    },

    // ── Marvel ──────────────────────────────────────────────────────────
    {
      id: 'spiderman',
      name: 'SPIDER-MAN',
      house: 'Marvel',
      cover: null,
      ph: { bg: '#B8202C', ink: '#1B4F9B' },
      editions: [
        { id: 'sp-amazing', name: 'AMAZING', publisher: 'Fibra', total: 64, owned: 38, read: 30 },
        { id: 'sp-ultimate', name: 'ULTIMATE', publisher: 'Fibra', total: 28, owned: 9, read: 7 },
      ],
    },
    {
      id: 'xmen',
      name: 'X-MEN',
      house: 'Marvel',
      cover: null,
      ph: { bg: '#E8A21C', ink: '#15171C' },
      editions: [
        { id: 'xm-uncanny', name: 'UNCANNY', publisher: 'Fibra', total: 55, owned: 19, read: 14 },
      ],
    },

    // ── Independent ─────────────────────────────────────────────────────
    {
      id: 'hellboy',
      name: 'HELLBOY',
      house: 'Nezavisni',
      cover: null,
      ph: { bg: '#7A1A16', ink: '#E8C547' },
      editions: [
        { id: 'hb-mignola', name: 'OMNIBUS', publisher: 'Fibra', total: 16, owned: 11, read: 11 },
      ],
    },
    {
      id: 'sincity',
      name: 'SIN CITY',
      house: 'Nezavisni',
      cover: null,
      ph: { bg: '#0C0D0E', ink: '#FEF7FF' },
      editions: [
        { id: 'sc-darkhorse', name: 'NOIR', publisher: 'Fibra', total: 7, owned: 7, read: 6 },
      ],
    },
  ];

  // Publisher houses, in display order, for grouping the home grid.
  const HOUSES = ['Bonelli', 'DC', 'Marvel', 'Nezavisni'];

  // Aggregate stats per series (for home grid cards)
  SERIES.forEach(s => {
    s.total = s.editions.reduce((a, e) => a + e.total, 0);
    s.owned = s.editions.reduce((a, e) => a + e.owned, 0);
    s.read  = s.editions.reduce((a, e) => a + e.read, 0);
  });

  // Dylan Dog EXTRA issues — #24/#25 carry the real Ludens covers from the Figma
  const DD_TITLES = [
    'Zora živih mrtvaca', 'Jack Trbosjek', 'Noći punog mjeseca', 'Duh u Anni Never',
    'Ubojice', 'Đavolja jutarnja zvijezda', 'Zona sumraka', 'Povratak čudovišta',
    'Alfa i Omega', 'Kroz zrcalo', 'Killer!', 'Memorije iz nevidljivog',
    'Strah', 'Između života i smrti', 'Kanali', 'Pakleni vlak',
    'Goblin', 'Doktor Terror', 'Grimizna kraljica', 'Vrijeme smrti',
    'Inferni', 'Priča o nitkome', 'Dugi oproštaj', 'Ružičasti zečevi ubijaju',
    'Morgana', 'Johnny Freak', 'Golconda!', 'Horror Paradise',
    'Zlokobni klaun', 'Posljednji čovjek na Zemlji',
  ];

  const PH_COLORS = ['#B5281E', '#1F5FA8', '#E0C530', '#1E4A42', '#5A2A6E', '#3A2C20'];

  // Posuđeni primjerci (broj → kome / od kada)
  const LOANS = { 3: { to: 'Marko', since: '03/2026' }, 11: { to: 'Ivana', since: '05/2026' } };

  const ISSUES = DD_TITLES.map((title, i) => {
    const n = i + 1;
    const seed = (n * 37 + 11) % 100;
    const owned = seed % 5 !== 1;
    return {
      id: 'dd-extra-' + n,
      number: n,
      title,
      year: 1994 + Math.floor(i / 3),
      rating: 3 + (seed % 3),
      writer: 'Tiziano Sclavi',
      artist: ['Angelo Stano', 'Corrado Roi', 'Giampiero Casertano', 'Bruno Brindisi'][seed % 4],
      owned,
      read: owned && seed % 3 !== 0,
      condition: owned ? 2 + (seed % 4) : null,
      price: owned ? 2 + (seed % 9) : null,
      value: owned ? Math.max(2, Math.round((2 + (seed % 9)) * (0.8 + (seed % 7) / 10))) : 3 + (seed % 10),
      dupli: owned && seed % 9 === 2,
      loaned: owned ? (LOANS[n] || null) : null,
      cover: n === 24 ? 'figma-style/assets/cover-zecevi.png'
           : n === 25 ? 'figma-style/assets/cover-morgana.png'
           : null,
      phBg: PH_COLORS[seed % PH_COLORS.length],
    };
  });

  // Featured issue for the detail screen (matches Figma's Moj_dizajn_1)
  const FEATURED = {
    ...ISSUES[24], // #25 Morgana
    description: 'The iconic Italian horror comic features the paranormal detective Dylan Dog and his mystery solving adventures.',
    pages: 98,
    publisher: 'Ludens',
    edition: 'EXTRA',
  };

  // Unread = owned but not read, across the collection (sampled list)
  const UNREAD = ISSUES.filter(it => it.owned && !it.read);

  // CSV export of the tracked edition
  function toCSV(issues) {
    const list = issues || ISSUES;
    const head = 'Serijal,Edicija,Broj,Naslov,Godina,Imam,Procitano,Stanje,Cijena EUR,Vrijednost EUR,Dupli,Posudeno';
    const rows = list.map(it => [
      'Dylan Dog', 'EXTRA', it.number, '"' + it.title + '"', it.year,
      it.owned ? 'DA' : 'NE', it.read ? 'DA' : 'NE',
      it.owned ? it.condition + '/5' : '', it.owned ? it.price : '', it.owned ? it.value : '',
      it.dupli ? 'DA' : '', it.loaned ? it.loaned.to : '',
    ].join(','));
    return [head].concat(rows).join('\n');
  }

  window.CC_DATA = { SERIES, HOUSES, ISSUES, FEATURED, UNREAD, toCSV };
})();
