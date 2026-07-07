// cc-redesign-3.jsx — redizajn: Kolekcija hub, Statistika, Nije čitano,
// Tražim, Dupli, Posuđeno, Export, Postavke (+sync), U najavi, Uredi, Prazno.
// Ista vizualna gramatika kao cc-screens-redesign.jsx (RScreen + FAB nav).

const { SERIES: R3_SERIES, ISSUES: R3_ISSUES, toCSV: R3_toCSV } = window.CC_DATA;

const r3I = (paths) => ({ size = 22, color = 'currentColor', sw = 2, style }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw}
    strokeLinecap="round" strokeLinejoin="round" style={style}>{paths}</svg>
);
const R3IcoChart  = r3I(<g><path d="M4.5 19V9.5M9.5 19V4.5M14.5 19v-7M19.5 19V8" /><path d="M2.5 21.5h19" /></g>);
const R3IcoWish   = r3I(<g><circle cx="10.5" cy="10.5" r="6" /><path d="m15.2 15.2 5 5" /><path d="M8.2 10.5h4.6M10.5 8.2v4.6" /></g>);
const R3IcoCopies = r3I(<g><rect x="8" y="8" width="12" height="12" rx="2" /><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2" /></g>);
const R3IcoLoan   = r3I(<g><rect x="15" y="4" width="6" height="16" rx="1" /><path d="M11 8l-4 4 4 4M3 12h8" /></g>);
const R3IcoCsv    = r3I(<g><path d="M12 3.5V15M7.5 10.5 12 15l4.5-4.5" /><path d="M4 20.5h16" /></g>);
const R3IcoBell   = r3I(<g><path d="M6 9a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6z" /><path d="M10 20a2 2 0 0 0 4 0" /></g>);
const R3IcoCal    = r3I(<g><rect x="4" y="5.5" width="16" height="15" rx="2.5" /><path d="M4 9.5h16M8.5 3v4.5M15.5 3v4.5" /></g>);
const R3IcoTrash  = r3I(<g><path d="M5 7h14M9.5 7V4.5h5V7M6.5 7l1 12.5h9l1-12.5" /></g>);
const R3IcoCloud  = r3I(<g><path d="M7 18a4.5 4.5 0 0 1-.6-8.96 6 6 0 0 1 11.6 1.6A3.7 3.7 0 0 1 17.5 18z" /><path d="m9.5 13.5 2 2 3.5-3.5" /></g>);
const R3IcoOut    = r3I(<g><path d="M9 4H5.5A1.5 1.5 0 0 0 4 5.5v13A1.5 1.5 0 0 0 5.5 20H9" /><path d="M15 8l4 4-4 4M8.5 12H19" /></g>);
const R3IcoPlusBx = r3I(<g><rect x="3.5" y="3.5" width="17" height="17" rx="4.5" /><path d="M12 8.5v7M8.5 12h7" /></g>);

function R3Header({ t, text, onBack, size = 26 }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 2px', position: 'relative', zIndex: 2 }}>
      <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 44, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <IcoBack size={22} />
      </button>
      <div style={{ flex: 1, textAlign: 'center', paddingRight: 44 }}><ComicLogo text={text} size={size} font={t.font} /></div>
    </div>
  );
}

function R3Row({ it, sub, action, onOpen }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 9, borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)' }}>
      <div onClick={onOpen} style={{ width: 46, height: 62, borderRadius: 7, overflow: 'hidden', flexShrink: 0, cursor: onOpen ? 'pointer' : 'default' }}>
        <CoverArt issue={it} height="100%" />
      </div>
      <div onClick={onOpen} style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2, cursor: onOpen ? 'pointer' : 'default' }}>
        <span style={{ fontWeight: 700, fontSize: 14.5, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>#{it.number} - {it.title}</span>
        <span style={{ fontSize: 12, color: 'var(--text2)' }}>{sub}</span>
      </div>
      {action}
    </div>
  );
}

function R3Pill({ children, onClick, solid = false }) {
  return (
    <button onClick={onClick} style={{
      appearance: 'none', cursor: 'pointer', flexShrink: 0,
      border: solid ? 'none' : '1.5px solid var(--accent)', borderRadius: 999, padding: '7px 12px',
      background: solid ? 'var(--accent)' : 'transparent', color: solid ? '#FFF' : 'var(--accent)',
      fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 12, whiteSpace: 'nowrap',
    }}>{children}</button>
  );
}

function R3Bar({ value, max, color }) {
  const pct = max > 0 ? Math.min(100, Math.round((value / max) * 100)) : 0;
  return (
    <div style={{ height: 8, borderRadius: 999, background: 'var(--deep)', overflow: 'hidden' }}>
      <div style={{ width: pct + '%', height: '100%', borderRadius: 999, background: color || 'linear-gradient(90deg, var(--accent-deep), var(--accent))' }}></div>
    </div>
  );
}

// ── R12 · KOLEKCIJA HUB — pločice umjesto liste ────────────────────────
function RScreenHub({ t, st, onNav, onAdd, onGo, onBack }) {
  const store = useStore(st);
  const merged = R3_ISSUES.map(store.getIssue);
  const counts = {
    unread:   merged.filter(it => it.owned && !it.read).length,
    trazim:   merged.filter(it => !it.owned).length,
    dupli:    merged.filter(it => it.owned && it.dupli).length,
    posudeno: merged.filter(it => it.owned && it.loaned).length,
  };
  const tiles = [
    { id: 'stats',    Ico: R3IcoChart,  label: 'STATISTIKA', sub: 'kompletnost i vrijednost' },
    { id: 'unread',   Ico: IcoEye,      label: 'NIJE ČITANO', sub: counts.unread + ' čeka', count: counts.unread },
    { id: 'trazim',   Ico: R3IcoWish,   label: 'TRAŽIM',     sub: counts.trazim + ' nedostaje', count: counts.trazim, hot: true },
    { id: 'dupli',    Ico: R3IcoCopies, label: 'DUPLI',      sub: counts.dupli + ' za zamjenu', count: counts.dupli },
    { id: 'posudeno', Ico: R3IcoLoan,   label: 'POSUĐENO',   sub: counts.posudeno + ' vani', count: counts.posudeno },
    { id: 'releases', Ico: R3IcoCal,    label: 'U NAJAVI',   sub: 'nadolazeći brojevi' },
    { id: 'export',   Ico: R3IcoCsv,    label: 'EXPORT CSV', sub: 'sigurnosna kopija' },
  ];
  return (
    <RScreen t={t} nav="polica" onNav={onNav} onAdd={onAdd}>
      <R3Header t={t} text="MOJA KOLEKCIJA" onBack={onBack} size={28} />
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '8px 16px 24px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 11 }}>
          {tiles.map(({ id, Ico, label, sub, count, hot }) => (
            <div key={id} onClick={onGo && (() => onGo(id))} style={{
              position: 'relative', padding: '14px 14px 13px', borderRadius: 16,
              background: hot ? 'linear-gradient(180deg, color-mix(in oklab, var(--accent) 70%, #fff) 0%, var(--accent) 40%, var(--accent-deep) 100%)' : 'var(--surface)',
              boxShadow: 'var(--card-shadow)', cursor: onGo ? 'pointer' : 'default',
              display: 'flex', flexDirection: 'column', gap: 8, minHeight: 96,
            }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <div style={{ width: 38, height: 38, borderRadius: 11, display: 'flex', alignItems: 'center', justifyContent: 'center', background: hot ? 'rgba(255,255,255,0.18)' : 'var(--deep)', color: hot ? '#fff' : 'var(--accent)' }}>
                  <Ico size={20} />
                </div>
                {count !== undefined && count > 0 && (
                  <span style={{ minWidth: 24, height: 24, padding: '0 7px', borderRadius: 999, background: hot ? 'rgba(255,255,255,0.22)' : 'var(--deep)', color: hot ? '#fff' : 'var(--text2)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12, fontWeight: 700 }}>{count}</span>
                )}
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                <span style={{ fontWeight: 800, fontSize: 14, letterSpacing: '0.03em', color: hot ? '#fff' : 'var(--text)' }}>{label}</span>
                <span style={{ fontSize: 11.5, color: hot ? 'rgba(255,255,255,0.85)' : 'var(--text2)' }}>{sub}</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </RScreen>
  );
}

// ── R13 · STATISTIKA ────────────────────────────────────────────────────
function RScreenStatsR({ t, st, onNav, onAdd, onBack }) {
  const store = useStore(st);
  const merged = R3_ISSUES.map(store.getIssue);
  const totals = R3_SERIES.reduce((a, s) => ({ total: a.total + s.total, owned: a.owned + s.owned, read: a.read + s.read }), { total: 0, owned: 0, read: 0 });
  const value = merged.filter(it => it.owned).reduce((a, it) => a + (it.value || 0), 0);
  const card = (label, big, sub) => (
    <div style={{ padding: '12px 14px', borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', display: 'flex', flexDirection: 'column', gap: 2 }}>
      <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.08em', textTransform: 'uppercase', fontWeight: 600 }}>{label}</span>
      <span style={{ fontSize: 23, fontWeight: 800 }}>{big}</span>
      {sub && <span style={{ fontSize: 12, color: 'var(--text2)' }}>{sub}</span>}
    </div>
  );
  return (
    <RScreen t={t} nav="polica" onNav={onNav} onAdd={onAdd}>
      <R3Header t={t} text="STATISTIKA" onBack={onBack} />
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '6px 16px 24px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          {card('Imam', totals.owned + ' / ' + totals.total, Math.round(totals.owned / totals.total * 100) + '% kolekcije')}
          {card('Pročitano', totals.read, Math.round(totals.read / totals.owned * 100) + '% od posjedovanog')}
          {card('Vrijednost', '~' + value + ' €', 'procjena · Dylan Dog EXTRA')}
          {card('Serijala', R3_SERIES.length, R3_SERIES.reduce((a, s) => a + s.editions.length, 0) + ' edicija')}
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12, marginTop: 16 }}>
          {R3_SERIES.map(s => (
            <div key={s.id} style={{ padding: '12px 14px', borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)' }}>
              <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 8 }}>
                <span style={{ fontWeight: 800, fontSize: 14, letterSpacing: '0.03em' }}>{s.name}</span>
                <span style={{ fontSize: 12, color: 'var(--text2)' }}>{s.owned}/{s.total} · {Math.round(s.owned / s.total * 100)}%</span>
              </div>
              <R3Bar value={s.owned} max={s.total} />
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', margin: '8px 0 4px' }}>
                <span style={{ fontSize: 12, color: 'var(--muted)' }}>pročitano</span>
                <span style={{ fontSize: 12, color: 'var(--muted)' }}>{s.read}/{s.owned}</span>
              </div>
              <R3Bar value={s.read} max={s.owned} color="#2E9E2E" />
            </div>
          ))}
        </div>
      </div>
    </RScreen>
  );
}

// ── R14 · NIJE ČITANO ───────────────────────────────────────────────────
function RScreenUnreadR({ t, st, onNav, onAdd, onBack, onOpenIssue }) {
  const store = useStore(st);
  const unread = R3_ISSUES.map(store.getIssue).filter(it => it.owned && !it.read);
  return (
    <RScreen t={t} nav="polica" onNav={onNav} onAdd={onAdd}>
      <R3Header t={t} text="NIJE ČITANO" onBack={onBack} />
      <p style={{ margin: '0 16px 10px', textAlign: 'center', fontSize: 12.5, color: 'var(--muted)' }}>
        {unread.length} stripova čeka — dodirni oko za pročitano
      </p>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 9, padding: '0 16px 24px' }}>
        {unread.map(it => (
          <R3Row key={it.id} it={it} sub={'Dylan Dog · EXTRA · ' + it.year}
            onOpen={onOpenIssue && (() => onOpenIssue(it))}
            action={
              <button onClick={() => store.patchIssue(it.id, { read: true })} title="Označi kao pročitano" style={{ appearance: 'none', cursor: 'pointer', border: 'none', width: 36, height: 36, borderRadius: 10, background: '#A91A1A', color: '#FFF', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, boxShadow: '0 2px 6px rgba(0,0,0,0.4)' }}>
                <IcoEye size={18} sw={2.4} />
              </button>
            } />
        ))}
        {unread.length === 0 && <p style={{ textAlign: 'center', color: 'var(--muted)', fontSize: 13, marginTop: 30 }}>Sve pročitano!</p>}
      </div>
    </RScreen>
  );
}

// ── R15 · TRAŽIM ────────────────────────────────────────────────────────
function RScreenTrazimR({ t, st, onNav, onAdd, onBack, onOpenIssue }) {
  const store = useStore(st);
  const missing = R3_ISSUES.map(store.getIssue).filter(it => !it.owned);
  const [copied, setCopied] = React.useState(false);
  const share = () => {
    const txt = 'TRAŽIM — Dylan Dog EXTRA: ' + missing.map(it => '#' + it.number).join(', ');
    try { navigator.clipboard && navigator.clipboard.writeText(txt); } catch (e) { /* iframe */ }
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };
  return (
    <RScreen t={t} nav="polica" onNav={onNav} onAdd={onAdd}>
      <R3Header t={t} text="TRAŽIM" onBack={onBack} />
      <p style={{ margin: '0 16px 10px', textAlign: 'center', fontSize: 12.5, color: 'var(--muted)' }}>
        Dylan Dog · EXTRA — nedostaje {missing.length} brojeva
      </p>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 9, padding: '0 16px 12px' }}>
        {missing.map(it => (
          <R3Row key={it.id} it={it}
            sub={it.year + ' · tržišna cijena ~' + it.value + ' €'}
            onOpen={onOpenIssue && (() => onOpenIssue(it))}
            action={<R3Pill onClick={() => store.patchIssue(it.id, { owned: true })}>+ NABAVLJEN</R3Pill>} />
        ))}
        {missing.length === 0 && <p style={{ textAlign: 'center', color: 'var(--muted)', fontSize: 13, marginTop: 30 }}>Kolekcija je kompletna!</p>}
      </div>
      <div style={{ padding: '0 16px 16px' }}>
        <RedButton small onClick={share} style={{ width: '100%' }}>{copied ? 'KOPIRANO ✓' : 'KOPIRAJ POPIS ZA SAJAM'}</RedButton>
      </div>
    </RScreen>
  );
}

// ── R16 · DUPLI ─────────────────────────────────────────────────────────
function RScreenDupliR({ t, st, onNav, onAdd, onBack, onOpenIssue, onTrade }) {
  const store = useStore(st);
  const dupli = R3_ISSUES.map(store.getIssue).filter(it => it.owned && it.dupli);
  return (
    <RScreen t={t} nav="polica" onNav={onNav} onAdd={onAdd}>
      <R3Header t={t} text="DUPLI" onBack={onBack} />
      <p style={{ margin: '0 16px 10px', textAlign: 'center', fontSize: 12.5, color: 'var(--muted)' }}>
        Dvostruki primjerci — za zamjenu ili prodaju
      </p>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 9, padding: '0 16px 24px' }}>
        {dupli.map(it => (
          <R3Row key={it.id} it={it}
            sub={'×2 primjerka · ' + (window.R2_GRADE_OF ? R2_GRADE_OF[it.condition || 4] : it.condition + '/5') + ' · ~' + it.value + ' €'}
            onOpen={onOpenIssue && (() => onOpenIssue(it))}
            action={<R3Pill onClick={() => store.patchIssue(it.id, { dupli: false })}>ZAMIJENJEN</R3Pill>} />
        ))}
        {dupli.length === 0 && <p style={{ textAlign: 'center', color: 'var(--muted)', fontSize: 13, marginTop: 30 }}>Nema duplih primjeraka.</p>}
      </div>
      <div style={{ padding: '0 16px 16px' }}>
        <RedButton small onClick={onTrade} style={{ width: '100%' }}>PONUDI ZA ZAMJENU — QR / LINK</RedButton>
      </div>
    </RScreen>
  );
}

// ── R17 · POSUĐENO ────────────────────────────────────────────────────────
function RScreenPosudenoR({ t, st, onNav, onAdd, onBack, onOpenIssue }) {
  const store = useStore(st);
  const loaned = R3_ISSUES.map(store.getIssue).filter(it => it.owned && it.loaned);
  return (
    <RScreen t={t} nav="polica" onNav={onNav} onAdd={onAdd}>
      <R3Header t={t} text="POSUĐENO" onBack={onBack} />
      <p style={{ margin: '0 16px 10px', textAlign: 'center', fontSize: 12.5, color: 'var(--muted)' }}>
        Tko ima koji broj — i od kada
      </p>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 9, padding: '0 16px 24px' }}>
        {loaned.map(it => (
          <R3Row key={it.id} it={it}
            sub={'Posuđeno: ' + it.loaned.to + ' · od ' + it.loaned.since}
            onOpen={onOpenIssue && (() => onOpenIssue(it))}
            action={<R3Pill solid onClick={() => store.patchIssue(it.id, { loaned: null })}>VRAĆENO</R3Pill>} />
        ))}
        {loaned.length === 0 && <p style={{ textAlign: 'center', color: 'var(--muted)', fontSize: 13, marginTop: 30 }}>Sve je vraćeno.</p>}
      </div>
    </RScreen>
  );
}

// ── R18 · EXPORT CSV ────────────────────────────────────────────────────
function RScreenExportR({ t, st, onNav, onAdd, onBack }) {
  const store = useStore(st);
  const merged = R3_ISSUES.map(store.getIssue);
  const csv = R3_toCSV(merged);
  const lines = csv.split('\n');
  const [saved, setSaved] = React.useState(false);
  const dl = () => {
    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'comicollect.csv';
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 4000);
    setSaved(true);
    setTimeout(() => setSaved(false), 2500);
  };
  const chip = (label, big) => (
    <div style={{ padding: '10px 14px', borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', display: 'flex', flexDirection: 'column', gap: 2 }}>
      <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.08em', textTransform: 'uppercase', fontWeight: 600 }}>{label}</span>
      <span style={{ fontSize: 21, fontWeight: 800 }}>{big}</span>
    </div>
  );
  return (
    <RScreen t={t} nav="polica" onNav={onNav} onAdd={onAdd}>
      <R3Header t={t} text="EXPORT CSV" onBack={onBack} />
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '6px 16px 24px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          {chip('Redaka', lines.length - 1)}
          {chip('Stupaca', lines[0].split(',').length)}
        </div>
        <div style={{ borderRadius: 14, background: 'var(--deep)', border: '1px solid var(--line)', padding: '12px 14px', overflow: 'hidden' }}>
          <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.08em', textTransform: 'uppercase', fontWeight: 600 }}>Pregled — comicollect.csv</span>
          <pre style={{ margin: '8px 0 0', fontFamily: "'JetBrains Mono', monospace", fontSize: 9.5, lineHeight: 1.65, color: 'var(--text2)', whiteSpace: 'pre', overflow: 'hidden' }}>{lines.slice(0, 9).join('\n') + '\n…'}</pre>
        </div>
        <RedButton onClick={dl} style={{ width: '100%' }}>{saved ? 'PREUZETO ✓' : 'PREUZMI CSV'}</RedButton>
        <p style={{ margin: 0, fontSize: 12, color: 'var(--muted)', textAlign: 'center' }}>Sigurnosna kopija — otvara se u Excelu ili Google Sheets</p>
      </div>
    </RScreen>
  );
}

// ── R19 · POSTAVKE — izgled + sinkronizacija + račun ───────────────────
function RScreenSettingsR({ t, setTweak, onNav, onAdd, onSyncNow, onLogout }) {
  const [autoSync, setAutoSync] = React.useState(true);
  const [notif, setNotif] = React.useState(true);
  const row = (label, control) => (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: '13px 16px', borderRadius: 14, background: 'var(--surface)' }}>
      <span style={{ fontSize: 14, fontWeight: 600 }}>{label}</span>
      {control}
    </div>
  );
  const seg = (key, options, labels) => (
    <div style={{ display: 'flex', gap: 6 }}>
      {options.map((o, i) => (
        <button key={String(o)} onClick={setTweak && (() => setTweak(key, o))} style={{
          appearance: 'none', cursor: 'pointer', border: '1px solid ' + (t[key] === o ? 'var(--accent)' : 'var(--line)'),
          background: t[key] === o ? 'var(--accent)' : 'transparent',
          color: t[key] === o ? '#FFF' : 'var(--text2)',
          borderRadius: 999, padding: '6px 13px', fontSize: 12, fontWeight: 600, fontFamily: "'Roboto', sans-serif",
        }}>{(labels || options)[i]}</button>
      ))}
    </div>
  );
  const toggle = (on, set) => (
    <div onClick={() => set(!on)} style={{ width: 44, height: 26, borderRadius: 999, background: on ? 'var(--accent)' : 'var(--deep)', position: 'relative', cursor: 'pointer', transition: 'background .15s', flexShrink: 0 }}>
      <div style={{ position: 'absolute', top: 3, left: on ? 21 : 3, width: 20, height: 20, borderRadius: '50%', background: '#fff', transition: 'left .15s', boxShadow: '0 1px 3px rgba(0,0,0,0.4)' }}></div>
    </div>
  );
  const section = (label) => (
    <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.1em', textTransform: 'uppercase', fontWeight: 700, margin: '8px 4px 0' }}>{label}</span>
  );
  return (
    <RScreen t={t} nav="settings" onNav={onNav} onAdd={onAdd}>
      <div style={{ padding: '14px 20px 8px', textAlign: 'center' }}><ComicLogo text="POSTAVKE" size={26} font={t.font} /></div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 10, padding: '0 16px 24px' }}>
        {section('Izgled')}
        {row('Tema', seg('theme', ['dark', 'light'], ['Tamna', 'Svijetla']))}
        {row('Boja', (
          <div style={{ display: 'flex', gap: 8 }}>
            {Object.entries(CC_ACCENTS).map(([k, v]) => (
              <button key={k} title={k} onClick={setTweak && (() => setTweak('accent', k))} style={{
                appearance: 'none', cursor: 'pointer', width: 28, height: 28, borderRadius: '50%',
                background: v.accent, border: '2px solid ' + (t.accent === k ? 'var(--text)' : 'transparent'),
              }}></button>
            ))}
          </div>
        ))}
        {row('Naslovi', seg('font', ['roboto', 'comic'], ['Roboto', 'Comic']))}
        {row('Statistika', seg('showStats', [true, false], ['Da', 'Ne']))}
        {section('Sinkronizacija')}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 0, borderRadius: 14, background: 'var(--surface)', overflow: 'hidden' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: '13px 16px' }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
              <span style={{ fontSize: 14, fontWeight: 600 }}>Automatska sinkronizacija</span>
              <span style={{ fontSize: 12, color: 'var(--text2)' }}>Promjene se spremaju lokalno i šalju na server</span>
            </div>
            {toggle(autoSync, setAutoSync)}
          </div>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '11px 16px', borderTop: '1px solid var(--line)' }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, fontSize: 12.5, color: 'var(--text2)' }}>
              <span style={{ color: 'var(--green)', display: 'flex' }}><R3IcoCloud size={16} /></span>
              Zadnja sinkronizacija: danas 9:28
            </span>
            <button onClick={onSyncNow} style={{ appearance: 'none', cursor: onSyncNow ? 'pointer' : 'default', background: 'none', border: 'none', color: 'var(--accent)', fontSize: 12.5, fontWeight: 700, fontFamily: "'Roboto', sans-serif" }}>Sinkroniziraj sad</button>
          </div>
        </div>
        {row('Obavijesti o novim brojevima', toggle(notif, setNotif))}
        {section('Račun')}
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 16px', borderRadius: 14, background: 'var(--surface)' }}>
          <div style={{ width: 40, height: 40, borderRadius: '50%', background: 'var(--deep)', border: '1.5px solid var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 800, fontSize: 15, color: 'var(--accent)', flexShrink: 0 }}>K</div>
          <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
            <span style={{ fontSize: 14, fontWeight: 700 }}>Kolekcionar</span>
            <span style={{ fontSize: 12, color: 'var(--text2)' }}>kolekcionar@email.com</span>
          </div>
          <button onClick={onLogout} style={{ appearance: 'none', cursor: onLogout ? 'pointer' : 'default', background: 'none', border: 'none', color: 'var(--text2)', display: 'flex', alignItems: 'center', gap: 6, fontSize: 12.5, fontWeight: 700, fontFamily: "'Roboto', sans-serif" }}>
            <R3IcoOut size={16} /> Odjava
          </button>
        </div>
      </div>
    </RScreen>
  );
}

// ── R20 · U NAJAVI ──────────────────────────────────────────────────────
const R3_RELEASES = [
  { id: 'r1', series: 'DYLAN DOG', edition: 'EXTRA', number: 87, title: 'Sjena nad Londonom', date: '28. lip', soon: true,  watch: true,  iss: R3_ISSUES[2] },
  { id: 'r2', series: 'TEX',       edition: 'ORIGINAL', number: 121, title: 'Kanjon duhova', date: '05. srp', soon: true,  watch: false, iss: R3_ISSUES[7] },
  { id: 'r3', series: 'ZAGOR',     edition: 'ORIGINAL', number: 97, title: 'Darkwood gori', date: '12. srp', soon: false, watch: true,  iss: R3_ISSUES[12] },
  { id: 'r4', series: 'DYLAN DOG', edition: 'MAXI', number: 18, title: 'Posljednji vlak', date: '19. srp', soon: false, watch: false, iss: R3_ISSUES[19] },
  { id: 'r5', series: 'MARTIN MYSTÈRE', edition: 'ORIGINAL', number: 39, title: 'Atlantida', date: '02. kol', soon: false, watch: false, iss: R3_ISSUES[23] },
];

function RScreenReleasesR({ t, onNav, onAdd, onBack }) {
  const [watch, setWatch] = React.useState(() => Object.fromEntries(R3_RELEASES.map(r => [r.id, r.watch])));
  const groups = [
    { key: 'soon', label: 'Ovaj tjedan', items: R3_RELEASES.filter(r => r.soon) },
    { key: 'later', label: 'Uskoro', items: R3_RELEASES.filter(r => !r.soon) },
  ];
  return (
    <RScreen t={t} nav="home" onNav={onNav} onAdd={onAdd}>
      <R3Header t={t} text="U NAJAVI" onBack={onBack} />
      <p style={{ margin: '0 16px 8px', textAlign: 'center', fontSize: 12.5, color: 'var(--muted)' }}>
        Nadolazeći brojevi — uključi zvonce za obavijest
      </p>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '4px 16px 24px', display: 'flex', flexDirection: 'column', gap: 16 }}>
        {groups.map(g => (
          <div key={g.key}>
            <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.1em', textTransform: 'uppercase', fontWeight: 700 }}>{g.label}</span>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 9, marginTop: 10 }}>
              {g.items.map(r => (
                <div key={r.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 10, borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)' }}>
                  <div style={{ width: 30, flexShrink: 0, textAlign: 'center' }}>
                    <div style={{ fontSize: 16, fontWeight: 800, lineHeight: 1, color: 'var(--accent)' }}>{r.date.split('.')[0]}</div>
                    <div style={{ fontSize: 10, color: 'var(--muted)', textTransform: 'uppercase', letterSpacing: '0.04em' }}>{r.date.split(' ')[1]}</div>
                  </div>
                  <div style={{ width: 46, height: 62, borderRadius: 7, overflow: 'hidden', flexShrink: 0 }}><CoverArt issue={r.iss} height="100%" /></div>
                  <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                    <span style={{ fontWeight: 700, fontSize: 14, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.series} #{r.number}</span>
                    <span style={{ fontSize: 12, color: 'var(--text2)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.edition} · {r.title}</span>
                  </div>
                  <button onClick={() => setWatch(w => ({ ...w, [r.id]: !w[r.id] }))} aria-label="Obavijesti me" style={{ appearance: 'none', cursor: 'pointer', width: 38, height: 38, borderRadius: 11, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', border: '1px solid ' + (watch[r.id] ? 'var(--accent)' : 'var(--line)'), background: watch[r.id] ? 'var(--accent)' : 'transparent', color: watch[r.id] ? '#fff' : 'var(--muted)' }}>
                    <R3IcoBell size={19} />
                  </button>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </RScreen>
  );
}

// ── R21 · UREDI PRIMJERAK — grade + posudba ────────────────────────────
function RScreenEditR({ t, issue, st, onNav, onAdd, onBack, onSave }) {
  const store = useStore(st);
  const it = store.getIssue(issue || window.CC_DATA.FEATURED);
  const [grade, setGrade] = React.useState(R2_GRADE_OF[it.condition || 4] || 'VF');
  const [value, setValue] = React.useState(String(it.value || 6));
  const [dupli, setDupli] = React.useState(!!it.dupli);
  const [loanOn, setLoanOn] = React.useState(!!it.loaned);
  const [loanTo, setLoanTo] = React.useState(it.loaned ? it.loaned.to : '');
  const save = () => {
    store.patchIssue(it.id, {
      condition: Math.max(1, R2_GRADE_OF.indexOf(grade)),
      value: parseInt(value, 10) || it.value,
      dupli,
      loaned: loanOn ? { to: loanTo || '—', since: (it.loaned && it.loaned.since) || '07/2026' } : null,
    });
    onSave && onSave();
  };
  return (
    <RScreen t={t} nav="polica" onNav={onNav} onAdd={onAdd}>
      <R3Header t={t} text="UREDI BROJ" onBack={onBack} size={24} />
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '8px 16px 16px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div style={{ display: 'flex', gap: 14, alignItems: 'center', padding: 12, borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)' }}>
          <div style={{ width: 56, height: 76, borderRadius: 8, overflow: 'hidden', flexShrink: 0 }}><CoverArt issue={it} height="100%" /></div>
          <div style={{ minWidth: 0 }}>
            <span style={{ fontWeight: 800, fontSize: 16 }}>#{it.number} — {it.title}</span>
            <div style={{ fontSize: 12, color: 'var(--text2)', marginTop: 3 }}>Dylan Dog · EXTRA · {it.year}</div>
          </div>
        </div>
        <Field label="Stanje"><GradeChips value={grade} onChange={setGrade} /></Field>
        <Field label="Procijenjena vrijednost"><TextField value={value} onChange={setValue} type="number" suffix="€" /></Field>
        <Toggle on={dupli} onChange={setDupli} label="Imam dupli primjerak" />
        <Toggle on={loanOn} onChange={setLoanOn} label="Posuđeno nekome" />
        {loanOn && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12, padding: 14, borderRadius: 14, background: 'rgba(169,26,26,0.10)', border: '1px solid rgba(169,26,26,0.35)' }}>
            <Field label="Kome"><TextField value={loanTo} onChange={setLoanTo} placeholder="Ime" /></Field>
            <Field label="Od kada"><TextField value={it.loaned ? it.loaned.since : '07/2026'} placeholder="MM/GGGG" /></Field>
          </div>
        )}
        <button onClick={onBack} style={{ appearance: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, cursor: onBack ? 'pointer' : 'default', border: '1.5px solid rgba(169,26,26,0.5)', background: 'transparent', color: '#D9514A', borderRadius: 12, padding: '12px', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 13.5, marginTop: 2 }}>
          <R3IcoTrash size={17} /> Ukloni iz kolekcije
        </button>
      </div>
      <div style={{ padding: '0 16px 16px' }}>
        <RedButton onClick={save} style={{ width: '100%' }}>SPREMI PROMJENE</RedButton>
      </div>
    </RScreen>
  );
}

// ── R22 · PRAZNA POLICA — pokazuje na FAB ───────────────────────────────
function RScreenEmptyR({ t, onNav, onAdd, onImport }) {
  return (
    <RScreen t={t} nav="polica" onNav={onNav} onAdd={onAdd}>
      <div style={{ padding: '14px 20px 8px', textAlign: 'center' }}><ComicLogo text="MOJA POLICA" size={26} font={t.font} /></div>
      <div style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center', padding: '0 40px 20px', gap: 18 }}>
        <div style={{ position: 'relative', width: 120, height: 120, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div style={{ position: 'absolute', inset: 0, borderRadius: 30, background: 'var(--accent)', opacity: 0.12 }}></div>
          <div style={{ position: 'absolute', inset: 0, borderRadius: 30, border: '2px dashed var(--accent)', opacity: 0.5 }}></div>
          <IcoBook size={56} color="var(--accent)" sw={1.6} />
        </div>
        <div>
          <h2 style={{ margin: 0, fontSize: 22, fontWeight: 800, letterSpacing: '0.02em' }}>Polica je prazna</h2>
          <p style={{ margin: '8px 0 0', fontSize: 14, color: 'var(--text2)', lineHeight: 1.6, maxWidth: 250 }}>
            Dodirni <b style={{ color: 'var(--accent)' }}>+</b> ispod i skeniraj svoj prvi strip.
          </p>
        </div>
        <button onClick={onImport} style={{ appearance: 'none', background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text2)', fontSize: 13.5, fontWeight: 600, fontFamily: "'Roboto', sans-serif" }}>
          Uvezi iz CSV datoteke
        </button>
      </div>
      {/* strelica prema FAB-u */}
      <div style={{ position: 'relative', height: 0, zIndex: 6 }}>
        <svg width="60" height="74" viewBox="0 0 60 74" fill="none" style={{ position: 'absolute', left: '50%', bottom: 6, transform: 'translateX(-50%)' }}>
          <path d="M30 4 C 14 22, 44 42, 30 62" stroke="var(--accent)" strokeWidth="2.5" strokeLinecap="round" strokeDasharray="1 7" fill="none" />
          <path d="M22 54 L30 64 L38 54" stroke="var(--accent)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" fill="none" />
        </svg>
      </div>
    </RScreen>
  );
}

Object.assign(window, {
  RScreenHub, RScreenStatsR, RScreenUnreadR, RScreenTrazimR, RScreenDupliR, RScreenPosudenoR,
  RScreenExportR, RScreenSettingsR, RScreenReleasesR, RScreenEditR, RScreenEmptyR,
});
