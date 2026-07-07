// cc-redesign-5.jsx — R27 foto korice (u sken-toku), R28 zamjena duplih
// (QR / javni popis), R29 batch unos raspona. Ista gramatika (RScreen + FAB).

const { SERIES: R5_SERIES, ISSUES: R5_ISSUES } = window.CC_DATA;

const r5I = (paths) => ({ size = 22, color = 'currentColor', sw = 2, style }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw}
    strokeLinecap="round" strokeLinejoin="round" style={style}>{paths}</svg>
);
const R5IcoCam   = r5I(<g><path d="M3 8.5a2 2 0 0 1 2-2h2l1.4-2h7.2L17 6.5h2a2 2 0 0 1 2 2V18a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" /><circle cx="12" cy="13" r="3.6" /></g>);
const R5IcoQr    = r5I(<g><rect x="4" y="4" width="6.5" height="6.5" rx="1" /><rect x="13.5" y="4" width="6.5" height="6.5" rx="1" /><rect x="4" y="13.5" width="6.5" height="6.5" rx="1" /><path d="M13.5 13.5h2.5v2.5h-2.5zM17.5 17.5H20V20h-2.5zM17.5 13.5H20M13.5 17.5v2.5" /></g>);
const R5IcoLink  = r5I(<g><path d="M10 14a4 4 0 0 0 6 .4l2.5-2.5a4 4 0 1 0-5.7-5.7L11.6 7.4" /><path d="M14 10a4 4 0 0 0-6-.4L5.5 12.1a4 4 0 1 0 5.7 5.7l1.2-1.2" /></g>);
const R5IcoStack = r5I(<g><path d="M12 3.5 21 8l-9 4.5L3 8z" /><path d="m3 12.5 9 4.5 9-4.5M3 17l9 4.5L21 17" transform="translate(0 -1)" /></g>);

// dekorativni QR uzorak
function R5Qr({ size = 120 }) {
  const cells = [];
  let seed = 7;
  const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
  for (let y = 0; y < 13; y++) for (let x = 0; x < 13; x++) {
    const finder = (x < 4 && y < 4) || (x > 8 && y < 4) || (x < 4 && y > 8);
    if (!finder && rnd() > 0.52) cells.push(<rect key={x + '-' + y} x={x * 8} y={y * 8} width="7" height="7" fill="#131412" />);
  }
  const finder = (fx, fy) => (
    <g key={fx + ',' + fy}>
      <rect x={fx * 8} y={fy * 8} width="31" height="31" fill="none" stroke="#131412" strokeWidth="7" />
      <rect x={fx * 8 + 12} y={fy * 8 + 12} width="7" height="7" fill="#131412" />
    </g>
  );
  return (
    <svg width={size} height={size} viewBox="-6 -6 116 116" style={{ display: 'block', background: '#FFF', borderRadius: 10, padding: 0 }}>
      {cells}{finder(0, 0)}{finder(9, 0)}{finder(0, 9)}
    </svg>
  );
}

// ── R27 · FOTO KORICE — dio sken-toka ───────────────────────────────────
function RScreenPhotoR({ t, onDone, onSkip }) {
  const it = R5_ISSUES[24];
  return (
    <div className="cc-screen" style={{
      ...ccVars(t, 'dark'), width: 393, height: 852, borderRadius: 28, overflow: 'hidden',
      background: '#0A0B0B', boxShadow: '0 0 0 8px #CAC4D0',
      display: 'flex', flexDirection: 'column', position: 'relative',
      fontFamily: "'Roboto', sans-serif", color: '#fff',
    }}>
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(120% 80% at 50% 42%, #2A2C2B 0%, #111212 55%, #060707 100%)' }}></div>
      <Halftone color="#fff" opacity={0.06} size={5} />
      {/* primjerak na stolu */}
      <div style={{ position: 'absolute', left: '50%', top: '44%', transform: 'translate(-50%,-50%) rotate(-1.5deg)', width: 218, borderRadius: 8, overflow: 'hidden', boxShadow: '0 24px 60px rgba(0,0,0,0.65)' }}>
        <div style={{ aspectRatio: '3/4', position: 'relative' }}><CoverArt issue={it} height="100%" /></div>
      </div>
      {/* okvir 3:4 */}
      <div style={{ position: 'absolute', left: '50%', top: '44%', transform: 'translate(-50%,-50%)', width: 252, height: 336, borderRadius: 14, border: '2.5px solid var(--accent)', boxShadow: '0 0 0 2000px rgba(6,8,8,0.45)' }}></div>
      <div style={{ position: 'relative', zIndex: 3, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 16px 0' }}>
        <button onClick={onSkip} aria-label="Close" style={{ appearance: 'none', width: 44, height: 44, borderRadius: '50%', background: 'rgba(0,0,0,0.45)', border: 'none', color: '#fff', cursor: onSkip ? 'pointer' : 'default', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><IcoX size={20} sw={2.4} /></button>
        <span style={{ fontSize: 13, fontWeight: 600, background: 'rgba(0,0,0,0.45)', padding: '7px 14px', borderRadius: 999 }}>Slikaj svoj primjerak · #25</span>
        <div style={{ width: 44 }}></div>
      </div>
      <div style={{ position: 'relative', zIndex: 3, marginTop: 'auto', padding: '0 24px 30px', display: 'flex', flexDirection: 'column', gap: 14, alignItems: 'center' }}>
        <span style={{ fontSize: 13, color: 'rgba(255,255,255,0.85)', textAlign: 'center', lineHeight: 1.5 }}>Tvoja fotka pamti stanje hrpta i posvete —<br />korisno za procjenu i prodaju</span>
        <button onClick={onDone} style={{ appearance: 'none', cursor: onDone ? 'pointer' : 'default', width: 64, height: 64, borderRadius: '50%', border: '4px solid rgba(255,255,255,0.85)', background: 'var(--accent)', color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 6px 20px rgba(0,0,0,0.5)' }}>
          <R5IcoCam size={28} />
        </button>
        <button onClick={onSkip} style={{ appearance: 'none', background: 'none', border: 'none', cursor: onSkip ? 'pointer' : 'default', color: 'rgba(255,255,255,0.9)', fontSize: 13.5, fontWeight: 600, fontFamily: "'Roboto', sans-serif" }}>
          Preskoči — koristi službenu koricu
        </button>
      </div>
    </div>
  );
}

// ── R28 · ZAMJENA — javni popis duplih + tražim ────────────────────────
function RScreenTradeR({ t, st, onNav, onAdd, onBack }) {
  const store = useStore(st);
  const merged = R5_ISSUES.map(store.getIssue);
  const dupli = merged.filter(it => it.owned && it.dupli);
  const trazim = merged.filter(it => !it.owned);
  const [copied, setCopied] = React.useState(false);
  const copy = () => {
    try { navigator.clipboard && navigator.clipboard.writeText('https://comicollect.app/z/kolekcionar'); } catch (e) { /* iframe */ }
    setCopied(true); setTimeout(() => setCopied(false), 2000);
  };
  const chipRow = (label, items, color) => (
    <div>
      <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.1em', textTransform: 'uppercase', fontWeight: 700 }}>{label} · {items.length}</span>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 8 }}>
        {items.slice(0, 12).map(it => (
          <span key={it.id} style={{ padding: '5px 10px', borderRadius: 999, background: 'var(--deep)', border: '1px solid ' + color, color: 'var(--text)', fontSize: 12, fontWeight: 700 }}>#{it.number}</span>
        ))}
        {items.length > 12 && <span style={{ padding: '5px 10px', borderRadius: 999, color: 'var(--muted)', fontSize: 12, fontWeight: 600 }}>+{items.length - 12}</span>}
      </div>
    </div>
  );
  return (
    <RScreen t={t} nav="polica" onNav={onNav} onAdd={onAdd}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 2px' }}>
        <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 44, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><IcoBack size={22} /></button>
        <div style={{ flex: 1, textAlign: 'center', paddingRight: 44 }}><ComicLogo text="ZAMJENA" size={26} font={t.font} /></div>
      </div>
      <p style={{ margin: '0 16px 10px', textAlign: 'center', fontSize: 12.5, color: 'var(--muted)' }}>
        Javni popis za sajam ili grupu — drugi vide što nudiš i što tražiš
      </p>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '2px 16px 16px', display: 'flex', flexDirection: 'column', gap: 16 }}>
        {/* share kartica s QR */}
        <div style={{ display: 'flex', gap: 14, alignItems: 'center', padding: 14, borderRadius: 16, background: 'var(--surface)', boxShadow: 'var(--card-shadow)' }}>
          <R5Qr size={104} />
          <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 5 }}>
            <span style={{ fontWeight: 800, fontSize: 15 }}>Kolekcionar</span>
            <span style={{ fontSize: 12, color: 'var(--text2)', wordBreak: 'break-all' }}>comicollect.app/z/kolekcionar</span>
            <span style={{ fontSize: 12, color: 'var(--muted)' }}>Dylan Dog · EXTRA</span>
          </div>
        </div>
        {chipRow('Nudim — dupli', dupli, 'rgba(62,198,62,0.55)')}
        {chipRow('Tražim', trazim, 'rgba(198,41,30,0.6)')}
      </div>
      <div style={{ padding: '0 16px 16px', display: 'flex', gap: 10 }}>
        <button onClick={copy} style={{ appearance: 'none', cursor: 'pointer', flex: 1, border: '1.5px solid var(--line)', borderRadius: 999, padding: '13px 8px', background: 'transparent', color: 'var(--text)', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 13, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7 }}>
          <R5IcoLink size={16} /> {copied ? 'KOPIRANO ✓' : 'KOPIRAJ LINK'}
        </button>
        <RedButton style={{ flex: 1 }}><span style={{ display: 'inline-flex', alignItems: 'center', gap: 7 }}><R5IcoQr size={16} /> POKAŽI QR</span></RedButton>
      </div>
    </RScreen>
  );
}

// ── R29 · BATCH UNOS RASPONA ────────────────────────────────────────────
function RScreenBatchR({ t, onNav, onAdd, onBack, onSave }) {
  const [series, setSeries] = React.useState('DYLAN DOG');
  const sObj = R5_SERIES.find(s => s.name === series) || R5_SERIES[0];
  const editions = sObj.editions.map(e => e.name);
  const [edition, setEdition] = React.useState(editions[0]);
  const [from, setFrom] = React.useState('1');
  const [to, setTo] = React.useState('50');
  const [excSet, setExcSet] = React.useState(() => new Set([12, 33]));
  const [grade, setGrade] = React.useState('VF');
  React.useEffect(() => { setEdition(editions[0]); }, [series]);
  const a = parseInt(from, 10), b = parseInt(to, 10);
  const validRange = !isNaN(a) && !isNaN(b) && b >= a;
  const nums = validRange ? Array.from({ length: Math.min(b - a + 1, 150) }, (_, i) => a + i) : [];
  const exc = [...excSet].filter(n => n >= a && n <= b).sort((x, y) => x - y);
  const toggleExc = n => setExcSet(prev => { const s = new Set(prev); if (s.has(n)) s.delete(n); else s.add(n); return s; });
  const count = validRange ? (b - a + 1 - exc.length) : 0;
  return (
    <RScreen t={t} nav="home" onNav={onNav} onAdd={onAdd}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 2px' }}>
        <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 44, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><IcoBack size={22} /></button>
        <div style={{ flex: 1, textAlign: 'center', paddingRight: 44 }}><ComicLogo text="UNOS RASPONA" size={22} font={t.font} /></div>
      </div>
      <p style={{ margin: '2px 16px 10px', textAlign: 'center', fontSize: 12.5, color: 'var(--muted)' }}>
        Za prvi unos postojeće kolekcije — cijeli raspon odjednom
      </p>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '4px 16px 16px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <Field label="Serijal"><SelectField value={series} onChange={setSeries} options={R5_SERIES.map(s => s.name)} /></Field>
        <Field label="Edicija"><SelectField value={edition} onChange={setEdition} options={editions} /></Field>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <Field label="Od broja"><TextField value={from} onChange={setFrom} type="number" /></Field>
          <Field label="Do broja"><TextField value={to} onChange={setTo} type="number" /></Field>
        </div>
        <Field label="Osim brojeva (nemam ih) — tapni broj">
          {validRange ? (
            <div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 6 }}>
                {nums.map(n => {
                  const off = excSet.has(n);
                  return (
                    <button key={n} onClick={() => toggleExc(n)} style={{
                      appearance: 'none', cursor: 'pointer', minHeight: 40, borderRadius: 9,
                      fontFamily: "'Roboto', sans-serif", fontSize: 13, fontWeight: 700,
                      border: off ? '1.5px solid var(--accent)' : '1px solid var(--line)',
                      background: off ? 'color-mix(in oklab, var(--accent) 18%, transparent)' : 'var(--surface)',
                      color: off ? 'var(--accent)' : 'var(--text2)',
                      textDecoration: off ? 'line-through' : 'none',
                    }}>{n}</button>
                  );
                })}
              </div>
              {b - a + 1 > 150 && (
                <div style={{ marginTop: 7, fontSize: 11.5, color: 'var(--muted)' }}>Prikazano prvih 150 brojeva — suzi raspon za ostale.</div>
              )}
            </div>
          ) : (
            <div style={{ padding: '11px 14px', borderRadius: 12, background: 'var(--deep)', fontSize: 12.5, color: 'var(--muted)' }}>Upiši ispravan raspon (od ≤ do) pa označi brojeve koje nemaš.</div>
          )}
        </Field>
        <Field label="Stanje za sve"><GradeChips value={grade} onChange={setGrade} /></Field>
        <div style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '12px 14px', borderRadius: 13, background: 'rgba(62,198,62,0.10)', border: '1px solid rgba(62,198,62,0.4)' }}>
          <span style={{ color: '#3EC63E', display: 'flex', flexShrink: 0 }}><R5IcoStack size={20} /></span>
          <span style={{ fontSize: 13, color: 'var(--text)', lineHeight: 1.5 }}>
            Dodat će se <b>{count} brojeva</b> ({from}–{to}{exc.length ? ', bez ' + exc.map(n => '#' + n).join(', ') : ''}).
            {exc.length > 0 && <span style={{ color: 'var(--text2)' }}> Preskočeni idu u <b>Tražim</b>.</span>}
          </span>
        </div>
      </div>
      <div style={{ padding: '0 16px 16px' }}>
        <RedButton onClick={onSave} style={{ width: '100%' }}>DODAJ {count} BROJEVA</RedButton>
      </div>
    </RScreen>
  );
}

// ── POPIS SKENIRANIH — prozor na dnu skenera ────────────────────────────
// 1 sken = samo srednja kartica, 2 = srednja + lijeva, 3+ = lepeza (bez ruke,
// blank kartice s crnim obrubom). Desno gumb "DODAJ X STRIPOVA".
function ScanCardsFan({ n }) {
  const card = (key, rot, dx, dy) => (
    <div key={key} style={{ position: 'absolute', left: '50%', top: '50%', width: 27, height: 37, borderRadius: 5, background: '#F2EDE2', border: '2px solid #131412', boxShadow: '0 2px 6px rgba(0,0,0,0.35)', transform: 'translate(-50%,-50%) translate(' + dx + 'px,' + dy + 'px) rotate(' + rot + 'deg)' }}></div>
  );
  const cards = n <= 1 ? [card('c', 0, 0, 0)]
    : n === 2 ? [card('l', -16, -12, 2), card('c', 4, 3, -1)]
    : [card('l', -26, -16, 4), card('c', 0, 0, -3), card('r', 26, 16, 4)];
  return <div aria-hidden="true" style={{ position: 'relative', width: 68, height: 54, flexShrink: 0 }}>{cards}</div>;
}

function hrStripova(n) {
  const m10 = n % 10, m100 = n % 100;
  if (m10 === 1 && m100 !== 11) return n + ' STRIP';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return n + ' STRIPA';
  return n + ' STRIPOVA';
}

function ScanModeToggle({ mode, setMode }) {
  return (
    <div style={{ display: 'flex', background: 'rgba(0,0,0,0.45)', borderRadius: 999, padding: 3 }}>
      {[['barkod', 'Barkod'], ['naslovnica', 'Naslovnica']].map(([k, lbl]) => (
        <button key={k} onClick={setMode && (() => setMode(k))} style={{ appearance: 'none', border: 'none', cursor: 'pointer', padding: '6px 13px', borderRadius: 999, fontSize: 12.5, fontWeight: 700, fontFamily: "'Roboto', sans-serif", background: mode === k ? 'var(--accent)' : 'transparent', color: mode === k ? '#FFF' : 'rgba(255,255,255,0.75)' }}>{lbl}</button>
      ))}
    </div>
  );
}

function ScanTray({ count, sub, onEdit, onAdd, buttonWord = 'DODAJ' }) {
  return (
    <div style={{ position: 'relative', zIndex: 3, margin: '0 16px 18px', display: 'flex', alignItems: 'center', gap: 10, padding: '10px 14px 10px 8px', borderRadius: 16, background: 'rgba(26,23,18,0.97)', border: '1px solid rgba(255,255,255,0.14)', boxShadow: '0 10px 30px rgba(0,0,0,0.55)' }}>
      <ScanCardsFan n={count} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 13.5, fontWeight: 700, color: '#FFF' }}>{hrStripova(count).toLowerCase()} u popisu</div>
        {sub && <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.6)', marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{sub}{onEdit && <span onClick={onEdit} style={{ color: '#E8C547', fontWeight: 800, cursor: 'pointer' }}> · UREDI</span>}</div>}
      </div>
      <button onClick={onAdd} style={{ appearance: 'none', cursor: onAdd ? 'pointer' : 'default', border: 'none', background: 'none', color: 'var(--accent, #D9514A)', fontSize: 13, fontWeight: 800, fontFamily: "'Roboto', sans-serif", letterSpacing: '0.03em', flexShrink: 0, textAlign: 'right', lineHeight: 1.35, padding: 0 }}>
        {buttonWord}<br />{hrStripova(count)}
      </button>
    </div>
  );
}

Object.assign(window, { RScreenPhotoR, RScreenTradeR, RScreenBatchR, ScanCardsFan, ScanTray, ScanModeToggle, hrStripova });
