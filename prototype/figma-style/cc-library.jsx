// cc-library.jsx — Library hub + collector features:
// Statistika, Tražim (missing), Dupli (duplicates), Posuđeno (loans), CSV export.

const { SERIES: L_SERIES, ISSUES: L_ISSUES, toCSV: L_toCSV } = window.CC_DATA;

// Local icon factory (same stroke style as cc-ui icons)
const libI = (paths) => ({ size = 22, color = 'currentColor', sw = 2, style }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw}
    strokeLinecap="round" strokeLinejoin="round" style={style}>{paths}</svg>
);
const IcoChart  = libI(<g><path d="M4.5 19V9.5M9.5 19V4.5M14.5 19v-7M19.5 19V8" /><path d="M2.5 21.5h19" /></g>);
const IcoWish   = libI(<g><circle cx="10.5" cy="10.5" r="6" /><path d="m15.2 15.2 5 5" /><path d="M8.2 10.5h4.6M10.5 8.2v4.6" /></g>);
const IcoCopies = libI(<g><rect x="8" y="8" width="12" height="12" rx="2" /><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2" /></g>);
const IcoLoan   = libI(<g><rect x="15" y="4" width="6" height="16" rx="1" /><path d="M11 8l-4 4 4 4M3 12h8" /></g>);
const IcoCsv    = libI(<g><path d="M12 3.5V15M7.5 10.5 12 15l4.5-4.5" /><path d="M4 20.5h16" /></g>);

function LibHeader({ t, text, onBack }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 8px', position: 'relative', zIndex: 2 }}>
      <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 40, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <IcoBack size={22} />
      </button>
      <div style={{ flex: 1, textAlign: 'center', paddingRight: 40 }}>
        <ComicLogo text={text} size={26} font={t.font} />
      </div>
    </div>
  );
}

function LibIssueRow({ it, sub, action, onOpen }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 9, borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)' }}>
      <div onClick={onOpen} style={{ width: 46, height: 62, borderRadius: 7, overflow: 'hidden', flexShrink: 0, cursor: onOpen ? 'pointer' : 'default' }}>
        <CoverArt issue={it} height="100%" />
      </div>
      <div onClick={onOpen} style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2, cursor: onOpen ? 'pointer' : 'default' }}>
        <span style={{ fontWeight: 700, fontSize: 14.5, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>#{it.number} - {it.title}</span>
        <span style={{ fontSize: 11.5, color: 'var(--text2)' }}>{sub}</span>
      </div>
      {action}
    </div>
  );
}

function LibPill({ children, onClick, solid = false }) {
  return (
    <button onClick={onClick} style={{
      appearance: 'none', cursor: 'pointer', flexShrink: 0,
      border: solid ? 'none' : '1.5px solid var(--accent)', borderRadius: 999, padding: '7px 12px',
      background: solid ? 'var(--accent)' : 'transparent', color: solid ? '#FFF' : 'var(--accent)',
      fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 11.5, whiteSpace: 'nowrap',
    }}>{children}</button>
  );
}

// ── Library hub ─────────────────────────────────────────────────────────
function ScreenLibrary({ t, st, onGo, onNav }) {
  const store = useStore(st);
  const merged = L_ISSUES.map(store.getIssue);
  const counts = {
    unread:   merged.filter(it => it.owned && !it.read).length,
    trazim:   merged.filter(it => !it.owned).length,
    dupli:    merged.filter(it => it.owned && it.dupli).length,
    posudeno: merged.filter(it => it.owned && it.loaned).length,
  };
  const rows = [
    { id: 'stats',    Ico: IcoChart,  label: 'STATISTIKA',  sub: 'Kompletnost po serijalu i ediciji' },
    { id: 'unread',   Ico: IcoEye,    label: 'NIJE ČITANO', sub: 'Stripovi koji čekaju čitanje', count: counts.unread },
    { id: 'trazim',   Ico: IcoWish,   label: 'TRAŽIM',      sub: 'Brojevi koji nedostaju u kolekciji', count: counts.trazim, hot: true },
    { id: 'dupli',    Ico: IcoCopies, label: 'DUPLI',       sub: 'Dvostruki primjerci za zamjenu', count: counts.dupli },
    { id: 'posudeno', Ico: IcoLoan,   label: 'POSUĐENO',    sub: 'Kome je koji broj posuđen', count: counts.posudeno },
    { id: 'export',   Ico: IcoCsv,    label: 'EXPORT CSV',  sub: 'Sigurnosna kopija cijele kolekcije' },
  ];
  return (
    <CCScreen t={t} nav="unread" onNav={onNav}>
      <CCTitle t={t} text="MOJA KOLEKCIJA" size={28} />
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 10, padding: '4px 16px 20px' }}>
        {rows.map(({ id, Ico, label, sub, count, hot }) => (
          <div key={id} onClick={onGo && (() => onGo(id))} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: 14, borderRadius: 16, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', cursor: onGo ? 'pointer' : 'default' }}>
            <div style={{ width: 42, height: 42, borderRadius: 12, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', background: hot ? 'var(--accent)' : 'var(--deep)', color: hot ? '#FFF' : 'var(--text2)' }}>
              <Ico size={22} />
            </div>
            <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
              <span style={{ fontWeight: 800, fontSize: 15, letterSpacing: '0.03em' }}>{label}</span>
              <span style={{ fontSize: 11.5, color: 'var(--text2)' }}>{sub}</span>
            </div>
            {count !== undefined && count > 0 && (
              <span style={{ minWidth: 26, height: 26, padding: '0 7px', borderRadius: 999, background: hot ? 'var(--accent)' : 'var(--deep)', color: hot ? '#FFF' : 'var(--text2)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12.5, fontWeight: 700, flexShrink: 0 }}>{count}</span>
            )}
            <IcoPlay size={14} color="var(--accent)" style={{ flexShrink: 0 }} />
          </div>
        ))}
      </div>
    </CCScreen>
  );
}

// ── Statistika ──────────────────────────────────────────────────────────
function LibBar({ value, max, color }) {
  const pct = max > 0 ? Math.min(100, Math.round((value / max) * 100)) : 0;
  return (
    <div style={{ height: 8, borderRadius: 999, background: 'var(--deep)', overflow: 'hidden' }}>
      <div style={{ width: pct + '%', height: '100%', borderRadius: 999, background: color || 'var(--accent)' }}></div>
    </div>
  );
}

function ScreenStats({ t, st, onBack, onNav }) {
  const store = useStore(st);
  const merged = L_ISSUES.map(store.getIssue);
  const totals = L_SERIES.reduce((a, s) => ({ total: a.total + s.total, owned: a.owned + s.owned, read: a.read + s.read }), { total: 0, owned: 0, read: 0 });
  const value = merged.filter(it => it.owned).reduce((a, it) => a + (it.value || 0), 0);
  const card = (label, big, sub) => (
    <div style={{ padding: '12px 14px', borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', display: 'flex', flexDirection: 'column', gap: 2 }}>
      <span style={{ fontSize: 11, color: 'var(--muted)', letterSpacing: '0.08em', textTransform: 'uppercase' }}>{label}</span>
      <span style={{ fontSize: 23, fontWeight: 800, color: 'var(--text)' }}>{big}</span>
      {sub && <span style={{ fontSize: 11.5, color: 'var(--text2)' }}>{sub}</span>}
    </div>
  );
  return (
    <CCScreen t={t} nav="unread" onNav={onNav}>
      <LibHeader t={t} text="STATISTIKA" onBack={onBack} />
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '4px 16px 20px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          {card('Imam', totals.owned + ' / ' + totals.total, Math.round(totals.owned / totals.total * 100) + '% kolekcije')}
          {card('Pročitano', totals.read, Math.round(totals.read / totals.owned * 100) + '% od posjedovanog')}
          {card('Vrijednost', '~' + value + ' €', 'procjena · Dylan Dog EXTRA')}
          {card('Serijala', L_SERIES.length, L_SERIES.reduce((a, s) => a + s.editions.length, 0) + ' edicija')}
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12, marginTop: 16 }}>
          {L_SERIES.map(s => (
            <div key={s.id} style={{ padding: '12px 14px', borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)' }}>
              <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 8 }}>
                <span style={{ fontWeight: 800, fontSize: 14, letterSpacing: '0.03em' }}>{s.name}</span>
                <span style={{ fontSize: 12, color: 'var(--text2)' }}>{s.owned}/{s.total} · {Math.round(s.owned / s.total * 100)}%</span>
              </div>
              <LibBar value={s.owned} max={s.total} />
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', margin: '8px 0 4px' }}>
                <span style={{ fontSize: 11, color: 'var(--muted)' }}>pročitano</span>
                <span style={{ fontSize: 11, color: 'var(--muted)' }}>{s.read}/{s.owned}</span>
              </div>
              <LibBar value={s.read} max={s.owned} color="#2E9E2E" />
            </div>
          ))}
        </div>
      </div>
    </CCScreen>
  );
}

// ── Tražim (missing issues / wishlist) ─────────────────────────────────
function ScreenTrazim({ t, st, onBack, onNav, onOpenIssue }) {
  const store = useStore(st);
  const missing = L_ISSUES.map(store.getIssue).filter(it => !it.owned);
  const [copied, setCopied] = React.useState(false);
  const share = () => {
    const txt = 'TRAŽIM — Dylan Dog EXTRA: ' + missing.map(it => '#' + it.number).join(', ');
    try { navigator.clipboard && navigator.clipboard.writeText(txt); } catch (e) { /* iframe */ }
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };
  return (
    <CCScreen t={t} nav="unread" onNav={onNav}>
      <LibHeader t={t} text="TRAŽIM" onBack={onBack} />
      <p style={{ margin: '0 16px 10px', textAlign: 'center', fontSize: 12.5, color: 'var(--muted)' }}>
        Dylan Dog · EXTRA — nedostaje {missing.length} brojeva
      </p>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 9, padding: '0 16px 12px' }}>
        {missing.map(it => (
          <LibIssueRow key={it.id} it={it}
            sub={it.year + ' · tržišna cijena ~' + it.value + ' €'}
            onOpen={onOpenIssue && (() => onOpenIssue(it))}
            action={<LibPill onClick={() => store.patchIssue(it.id, { owned: true })}>+ NABAVLJEN</LibPill>} />
        ))}
        {missing.length === 0 && <p style={{ textAlign: 'center', color: 'var(--muted)', fontSize: 13, marginTop: 30 }}>Kolekcija je kompletna!</p>}
      </div>
      <div style={{ padding: '0 16px 16px' }}>
        <RedButton small onClick={share} style={{ width: '100%' }}>{copied ? 'KOPIRANO ✓' : 'KOPIRAJ POPIS ZA SAJAM'}</RedButton>
      </div>
    </CCScreen>
  );
}

// ── Dupli (duplicates for trade) ───────────────────────────────────────
function ScreenDupli({ t, st, onBack, onNav, onOpenIssue }) {
  const store = useStore(st);
  const dupli = L_ISSUES.map(store.getIssue).filter(it => it.owned && it.dupli);
  return (
    <CCScreen t={t} nav="unread" onNav={onNav}>
      <LibHeader t={t} text="DUPLI" onBack={onBack} />
      <p style={{ margin: '0 16px 10px', textAlign: 'center', fontSize: 12.5, color: 'var(--muted)' }}>
        Dvostruki primjerci — za zamjenu ili prodaju
      </p>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 9, padding: '0 16px 20px' }}>
        {dupli.map(it => (
          <LibIssueRow key={it.id} it={it}
            sub={'×2 primjerka · stanje ' + it.condition + '/5 · ~' + it.value + ' €'}
            onOpen={onOpenIssue && (() => onOpenIssue(it))}
            action={<LibPill onClick={() => store.patchIssue(it.id, { dupli: false })}>ZAMIJENJEN</LibPill>} />
        ))}
        {dupli.length === 0 && <p style={{ textAlign: 'center', color: 'var(--muted)', fontSize: 13, marginTop: 30 }}>Nema duplih primjeraka.</p>}
      </div>
    </CCScreen>
  );
}

// ── Posuđeno (loaned out) ──────────────────────────────────────────────
function ScreenPosudeno({ t, st, onBack, onNav, onOpenIssue }) {
  const store = useStore(st);
  const loaned = L_ISSUES.map(store.getIssue).filter(it => it.owned && it.loaned);
  return (
    <CCScreen t={t} nav="unread" onNav={onNav}>
      <LibHeader t={t} text="POSUĐENO" onBack={onBack} />
      <p style={{ margin: '0 16px 10px', textAlign: 'center', fontSize: 12.5, color: 'var(--muted)' }}>
        Tko ima koji broj — i od kada
      </p>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 9, padding: '0 16px 20px' }}>
        {loaned.map(it => (
          <LibIssueRow key={it.id} it={it}
            sub={'Posuđeno: ' + it.loaned.to + ' · od ' + it.loaned.since}
            onOpen={onOpenIssue && (() => onOpenIssue(it))}
            action={<LibPill solid onClick={() => store.patchIssue(it.id, { loaned: null })}>VRAĆENO</LibPill>} />
        ))}
        {loaned.length === 0 && <p style={{ textAlign: 'center', color: 'var(--muted)', fontSize: 13, marginTop: 30 }}>Sve je vraćeno.</p>}
      </div>
    </CCScreen>
  );
}

// ── CSV export ─────────────────────────────────────────────────────────
function ScreenExport({ t, st, onBack, onNav }) {
  const store = useStore(st);
  const merged = L_ISSUES.map(store.getIssue);
  const csv = L_toCSV(merged);
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
      <span style={{ fontSize: 11, color: 'var(--muted)', letterSpacing: '0.08em', textTransform: 'uppercase' }}>{label}</span>
      <span style={{ fontSize: 21, fontWeight: 800, color: 'var(--text)' }}>{big}</span>
    </div>
  );
  return (
    <CCScreen t={t} nav="unread" onNav={onNav}>
      <LibHeader t={t} text="EXPORT CSV" onBack={onBack} />
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '4px 16px 20px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          {chip('Redaka', lines.length - 1)}
          {chip('Stupaca', lines[0].split(',').length)}
        </div>
        <div style={{ borderRadius: 14, background: 'var(--deep)', border: '1px solid var(--line)', padding: '12px 14px', overflow: 'hidden' }}>
          <span style={{ fontSize: 11, color: 'var(--muted)', letterSpacing: '0.08em', textTransform: 'uppercase' }}>Pregled — comicollect.csv</span>
          <pre style={{ margin: '8px 0 0', fontFamily: "'JetBrains Mono', monospace", fontSize: 9.5, lineHeight: 1.65, color: 'var(--text2)', whiteSpace: 'pre', overflow: 'hidden' }}>{lines.slice(0, 9).join('\n') + '\n…'}</pre>
        </div>
        <RedButton onClick={dl} style={{ width: '100%' }}>{saved ? 'PREUZETO ✓' : 'PREUZMI CSV'}</RedButton>
        <p style={{ margin: 0, fontSize: 11.5, color: 'var(--muted)', textAlign: 'center' }}>Sigurnosna kopija — otvara se u Excelu ili Google Sheets</p>
      </div>
    </CCScreen>
  );
}

Object.assign(window, {
  ScreenLibrary, ScreenStats, ScreenTrazim, ScreenDupli, ScreenPosudeno, ScreenExport,
});
