// cc-redesign-2.jsx — redizajn: Welcome, Serijal, Detalj broja, Pretraga, Add sheet.
// Ista vizualna gramatika kao cc-screens-redesign.jsx (RScreen + FAB nav).

const { SERIES: R2_SERIES, ISSUES: R2_ISSUES, FEATURED: R2_FEAT } = window.CC_DATA;

const r2I = (paths) => ({ size = 22, color = 'currentColor', sw = 2, style }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw}
    strokeLinecap="round" strokeLinejoin="round" style={style}>{paths}</svg>
);
const R2IcoBarcode = r2I(<g><path d="M4 6v12M7 6v12M10 6v12M13.5 6v12M17 6v12M20 6v12" /></g>);
const R2IcoPen     = r2I(<g><path d="M16.5 4.5 19.5 7.5 9 18l-4 1 1-4z" /><path d="M14.5 6.5 17.5 9.5" /></g>);
const R2IcoClock   = r2I(<g><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5V12l3 2" /></g>);

// condition number (1-5) → grade letter
const R2_GRADE_OF = ['', 'P', 'G', 'F', 'VF', 'M'];

function R2Header({ t, text, onBack, size = 26 }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 2px', position: 'relative', zIndex: 2 }}>
      <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 44, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <IcoBack size={22} />
      </button>
      <div style={{ flex: 1, textAlign: 'center', paddingRight: 44 }}><ComicLogo text={text} size={size} font={t.font} /></div>
    </div>
  );
}

// ── R7 · WELCOME (redizajn main menu) ──────────────────────────────────
function RScreenWelcome({ t, onEnter, onGuest }) {
  return (
    <div className="cc-screen" style={{
      ...ccVars(t, 'dark'), width: 393, height: 852, borderRadius: 28, overflow: 'hidden',
      background: 'var(--bg)', boxShadow: '0 0 0 8px #CAC4D0',
      display: 'flex', flexDirection: 'column', position: 'relative',
      fontFamily: "'Roboto', sans-serif", color: 'var(--text)',
    }}>
      <GrungeBg />
      <div style={{ position: 'absolute', inset: 0 }}>
        <img src="figma-style/assets/menu-hero.png" alt="" style={{ width: '100%', height: '56%', objectFit: 'cover', objectPosition: 'top', display: 'block' }} />
        <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: '58%', background: 'linear-gradient(0deg, #131412 2%, rgba(19,20,18,0.2) 50%, rgba(19,20,18,0.3) 100%)' }}></div>
      </div>
      <CCStatusBar />
      <div style={{ position: 'relative', zIndex: 2, flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'flex-end', padding: '0 32px 46px', textAlign: 'center' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2, filter: 'drop-shadow(0 0 18px rgba(198,41,30,0.55))' }}>
          <ComicLogo text="COMICS" size={44} font={t.font} />
          <ComicLogo text="COLLECTION" size={44} font={t.font} />
        </div>
        <p style={{ margin: '16px 0 0', fontSize: 15, color: 'var(--text2)', lineHeight: 1.55 }}>
          Tvoja kolekcija — uvijek uz tebe.<br />Radi i bez interneta, sinkronizira se sama.
        </p>
        <RedButton onClick={onEnter} style={{ marginTop: 26, width: '100%' }}>UĐI U KOLEKCIJU</RedButton>
        <button onClick={onGuest || onEnter} style={{ appearance: 'none', background: 'none', border: 'none', cursor: 'pointer', marginTop: 18, fontFamily: "'Roboto', sans-serif", fontSize: 14, fontWeight: 600, color: 'var(--text)' }}>Nastavi kao gost</button>
        <div style={{ marginTop: 20, display: 'flex', alignItems: 'center', gap: 7, color: 'var(--muted)', fontSize: 12.5 }}>
          <SyncChip state="ok" />
        </div>
      </div>
    </div>
  );
}

// ── R8 · SERIJAL — edicije s progresom ─────────────────────────────────
function RScreenSeriesR({ t, series, onNav, onAdd, onBack, onOpenEdition }) {
  const s = series || R2_SERIES[0];
  return (
    <RScreen t={t} nav="polica" onNav={onNav} onAdd={onAdd} grunge={true}>
      <R2Header t={t} text={s.name} onBack={onBack} size={30} />
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 12, padding: '8px 16px 24px', position: 'relative', zIndex: 2 }}>
        {s.editions.map(e => {
          const pct = Math.round((e.owned / e.total) * 100);
          return (
            <div key={e.id} onClick={onOpenEdition && (() => onOpenEdition(e))} style={{
              display: 'flex', alignItems: 'center', gap: 14, padding: 12, borderRadius: 16,
              background: 'var(--surface)', boxShadow: 'var(--card-shadow)',
              cursor: onOpenEdition ? 'pointer' : 'default',
            }}>
              <div style={{ width: 58, height: 78, borderRadius: 8, overflow: 'hidden', flexShrink: 0 }}>
                <CoverArt series={s} height="100%" />
              </div>
              <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 4 }}>
                <span style={{ fontSize: 12, color: 'var(--text2)' }}>{e.publisher}</span>
                <span style={{ fontWeight: 800, fontSize: 19, letterSpacing: '0.03em' }}>{e.name}</span>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 2 }}>
                  <div style={{ flex: 1, height: 6, borderRadius: 999, background: 'var(--deep)', overflow: 'hidden' }}>
                    <div style={{ width: pct + '%', height: '100%', borderRadius: 999, background: 'linear-gradient(90deg, var(--accent-deep), var(--accent))' }}></div>
                  </div>
                  <span style={{ fontSize: 12, color: 'var(--text2)', fontWeight: 600, flexShrink: 0 }}>{e.owned}/{e.total}</span>
                </div>
              </div>
              <IcoPlay size={16} color="var(--accent)" style={{ flexShrink: 0, marginRight: 2 }} />
            </div>
          );
        })}
      </div>
    </RScreen>
  );
}

// ── R9 · DETALJ BROJA — grade umjesto zvjezdica stanja ─────────────────
function RScreenIssueR({ t, issue, st, onNav, onAdd, onBack, onEdit, onStep }) {
  const store = useStore(st);
  const it = store.getIssue(issue || R2_FEAT);
  const read = !!it.read;
  const owned = it.owned !== false;
  const grade = R2_GRADE_OF[it.condition || 4];
  const prev = R2_ISSUES[it.number - 2];
  const next = R2_ISSUES[it.number];
  const chip = (label, target, dir) => (
    <div style={{ flex: 1, minWidth: 0 }}>
      <span style={{ fontSize: 12, color: 'var(--muted)', display: 'block', marginBottom: 6 }}>{label}</span>
      {target ? (
        <button onClick={onStep && (() => onStep(target))} style={{
          appearance: 'none', cursor: onStep ? 'pointer' : 'default', width: '100%',
          border: '1px solid var(--line)', borderRadius: 10, padding: '8px 10px',
          background: 'var(--surface)', color: 'var(--text)', textAlign: dir === 'next' ? 'right' : 'left',
          fontFamily: "'Roboto', sans-serif", fontWeight: 600, fontSize: 12.5,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        }}>#{target.number} {target.title}</button>
      ) : (
        <div style={{ border: '1px dashed var(--line)', borderRadius: 10, padding: '8px 10px', color: 'var(--muted)', fontSize: 12.5 }}>—</div>
      )}
    </div>
  );
  const actBtn = (active, activeStyle, onClick, icon, label) => (
    <button onClick={onClick} style={{
      appearance: 'none', cursor: 'pointer', flex: 1, whiteSpace: 'nowrap',
      borderRadius: 999, padding: '12px 8px',
      fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 12.5, letterSpacing: '0.02em',
      display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7,
      ...activeStyle,
    }}>{icon} {label}</button>
  );
  return (
    <RScreen t={t} nav="polica" onNav={onNav} onAdd={onAdd} grunge={true}>
      <R2Header t={t} text={it.seriesName || 'DYLAN DOG'} onBack={onBack} size={28} />
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '2px 24px 24px', position: 'relative', zIndex: 2 }}>
        <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start' }}>
          <div style={{ width: 150, flexShrink: 0, borderRadius: 12, overflow: 'hidden', boxShadow: '0 14px 34px rgba(0,0,0,0.6)' }}>
            <div style={{ aspectRatio: '3/4', position: 'relative' }}><CoverArt issue={it} height="100%" /></div>
          </div>
          <div style={{ flex: 1, minWidth: 0, paddingTop: 4 }}>
            <h2 style={{ margin: 0, fontSize: 17, fontWeight: 700 }}>{(it.seriesName || 'Dylan Dog')} {it.edition || 'EXTRA'}</h2>
            <p style={{ margin: '4px 0 0', fontSize: 15.5, fontWeight: 500 }}>#{it.number} - {it.title}</p>
            <div style={{ marginTop: 8, fontSize: 13, color: 'var(--text2)', lineHeight: 1.7 }}>
              <div>{it.year} · {(it.writer || 'Sclavi').split(' ').pop()} &amp; {(it.artist || 'Stano').split(' ').pop()}</div>
              <div style={{ marginTop: 4 }}><Stars value={it.rating} size={14} /></div>
            </div>
            {owned ? (
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 10 }}>
                <span title={'Stanje: ' + grade} style={{ width: 34, height: 34, borderRadius: 9, background: 'var(--deep)', border: '1.5px solid var(--accent)', color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 14, fontWeight: 800 }}>{grade}</span>
                <span style={{ fontSize: 12.5, color: 'var(--text2)' }}>~{it.value || 5} €{it.dupli ? ' · ' : ''}{it.dupli && <b style={{ color: 'var(--accent)' }}>×2</b>}</span>
              </div>
            ) : (
              <div style={{ marginTop: 10, fontSize: 12.5, color: 'var(--text2)' }}>
                <span style={{ color: 'var(--accent)', fontWeight: 700 }}>TRAŽIM</span> · ~{it.value || 5} €
              </div>
            )}
          </div>
        </div>
        {owned && it.loaned && (
          <div style={{ marginTop: 14, padding: '9px 12px', borderRadius: 10, background: 'rgba(169,26,26,0.14)', border: '1px solid rgba(169,26,26,0.45)', fontSize: 12.5 }}>
            Posuđeno: <b>{it.loaned.to}</b> · od {it.loaned.since}
          </div>
        )}
        <p style={{ margin: '14px 0 0', fontSize: 13.5, lineHeight: 1.55, color: 'var(--text2)' }}>
          {it.description || 'The iconic Italian horror comic features the paranormal detective Dylan Dog and his mystery solving adventures.'}
        </p>
        <div style={{ display: 'flex', gap: 12, marginTop: 16 }}>
          {chip('Prethodni broj', prev, 'prev')}
          {chip('Sljedeći broj', next, 'next')}
        </div>
        <div style={{ display: 'flex', gap: 10, marginTop: 18 }}>
          {read
            ? actBtn(true, { border: '1.5px solid #2E9E2E', background: 'rgba(46,158,46,0.14)', color: '#3EC63E' }, () => store.patchIssue(it.id, { read: false }), <IcoEye size={15} sw={2.4} />, 'PROČITANO')
            : actBtn(false, { border: 'none', background: 'linear-gradient(180deg, color-mix(in oklab, var(--accent) 78%, #fff) 0%, var(--accent) 38%, var(--accent-deep) 100%)', boxShadow: '0 4px 14px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,255,255,0.4)', color: '#FFF' }, () => store.patchIssue(it.id, { read: true }), <IcoEye size={15} sw={2.4} />, 'NIJE ČITANO')}
          {owned
            ? actBtn(true, { border: '1.5px solid #2E9E2E', background: 'rgba(46,158,46,0.14)', color: '#3EC63E' }, () => store.patchIssue(it.id, { owned: false }), <IcoCheck size={14} sw={3} />, 'U KOLEKCIJI')
            : actBtn(false, { border: '1.5px solid var(--accent)', background: 'transparent', color: 'var(--accent)' }, () => store.patchIssue(it.id, { owned: true }), null, '+ DODAJ')}
        </div>
        <button onClick={onEdit} style={{ appearance: 'none', cursor: onEdit ? 'pointer' : 'default', width: '100%', marginTop: 10, border: '1px solid var(--line)', borderRadius: 999, padding: '11px 8px', background: 'transparent', color: 'var(--text2)', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 12.5, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}>
          <R2IcoPen size={15} /> {owned ? 'UREDI PRIMJERAK — stanje, posudba, vrijednost' : 'UREDI — bilješke i ciljna cijena'}
        </button>
        <div style={{ marginTop: 18 }}>
          <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.1em', textTransform: 'uppercase', fontWeight: 700 }}>Detalji izdanja</span>
          <div style={{ marginTop: 10, borderRadius: 16, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', padding: '4px 16px 8px', display: 'grid', gridTemplateColumns: '1fr 1fr', columnGap: 16 }}>
            {[
              ['Izdavač', it.publisher || 'Ludens'],
              ['Edicija', (it.edition || 'EXTRA') + ' #' + it.number],
              ['Godina', it.year],
              ['Stranice', it.pages || 98],
              ['Scenarij', it.writer || 'Tiziano Sclavi'],
              ['Crtež', it.artist || 'Angelo Stano'],
            ].map(([k, v], i) => (
              <div key={k} style={{ padding: '9px 0', borderTop: i < 2 ? 'none' : '1px solid var(--line)', display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
                <span style={{ fontSize: 11.5, color: 'var(--muted)' }}>{k}</span>
                <span style={{ fontSize: 13.5, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{v}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </RScreen>
  );
}

// ── R10 · PRETRAGA — opseg + nedavno ───────────────────────────────────
function RScreenSearchR({ t, onNav, onAdd, onOpenSeries, onOpenIssue }) {
  const [q, setQ] = React.useState('');
  const [scope, setScope] = React.useState('sve');
  const query = q.trim().toLowerCase();
  const shits = (scope !== 'brojevi') ? R2_SERIES.filter(s => s.name.toLowerCase().includes(query)) : [];
  const ihits = (scope !== 'serijali' && query.length >= 2)
    ? R2_ISSUES.filter(it => ('#' + it.number + ' ' + it.title).toLowerCase().includes(query)).slice(0, 8)
    : [];
  const recent = ['morgana', 'tex #100', 'zagor'];
  const scopeChip = (id, label) => (
    <button key={id} onClick={() => setScope(id)} style={{
      appearance: 'none', cursor: 'pointer',
      border: '1px solid ' + (scope === id ? 'var(--accent)' : 'var(--line)'),
      background: scope === id ? 'var(--accent)' : 'transparent',
      color: scope === id ? '#FFF' : 'var(--text2)',
      borderRadius: 999, padding: '6px 14px', fontFamily: "'Roboto', sans-serif", fontWeight: 600, fontSize: 12,
    }}>{label}</button>
  );
  return (
    <RScreen t={t} nav="search" onNav={onNav} onAdd={onAdd}>
      <div style={{ padding: '14px 20px 10px', textAlign: 'center' }}><ComicLogo text="TRAŽI" size={26} font={t.font} /></div>
      <div style={{ padding: '0 16px 10px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '11px 14px', borderRadius: 999, background: 'var(--surface)', border: '1px solid var(--line)' }}>
          <span style={{ color: 'var(--muted)', display: 'flex' }}><IcoSearch size={18} /></span>
          <input value={q} onChange={e => setQ(e.target.value)} placeholder="Serijal, broj ili naslov…" style={{
            flex: 1, background: 'none', border: 'none', outline: 'none', minWidth: 0,
            fontFamily: "'Roboto', sans-serif", fontSize: 14, color: 'var(--text)',
          }} />
          {q && <button onClick={() => setQ('')} aria-label="Clear" style={{ appearance: 'none', background: 'none', border: 'none', cursor: 'pointer', color: 'var(--muted)', display: 'flex', padding: 0 }}><IcoX size={15} sw={2.4} /></button>}
        </div>
        <div style={{ display: 'flex', gap: 7 }}>
          {scopeChip('sve', 'Sve')}{scopeChip('serijali', 'Serijali')}{scopeChip('brojevi', 'Brojevi')}
        </div>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 10, padding: '2px 16px 24px' }}>
        {!query && (
          <div>
            <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.1em', textTransform: 'uppercase', fontWeight: 700 }}>Nedavno traženo</span>
            <div style={{ display: 'flex', gap: 7, marginTop: 10, flexWrap: 'wrap' }}>
              {recent.map(r => (
                <button key={r} onClick={() => setQ(r)} style={{ appearance: 'none', cursor: 'pointer', border: '1px solid var(--line)', borderRadius: 999, padding: '7px 13px', background: 'var(--surface)', color: 'var(--text2)', fontFamily: "'Roboto', sans-serif", fontSize: 12.5, display: 'inline-flex', alignItems: 'center', gap: 6 }}>
                  <R2IcoClock size={13} /> {r}
                </button>
              ))}
            </div>
          </div>
        )}
        {query && shits.map(s => <CCSeriesRow key={s.id} s={s} t={t} onClick={onOpenSeries && (() => onOpenSeries(s))} />)}
        {ihits.length > 0 && (
          <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.08em', margin: '4px 2px 0', textTransform: 'uppercase', fontWeight: 700 }}>Brojevi — Dylan Dog EXTRA</span>
        )}
        {ihits.map(it => (
          <div key={it.id} onClick={onOpenIssue && (() => onOpenIssue(it))} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 9, borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', cursor: onOpenIssue ? 'pointer' : 'default' }}>
          <div style={{ width: 40, height: 54, borderRadius: 6, overflow: 'hidden', flexShrink: 0 }}><CoverArt issue={it} height="100%" /></div>
            <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
              <span style={{ fontWeight: 700, fontSize: 14, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>#{it.number} - {it.title}</span>
              <span style={{ fontSize: 12, color: 'var(--text2)' }}>{it.year} · {it.owned ? 'u kolekciji' : 'nedostaje'}</span>
            </div>
          </div>
        ))}
        {query && shits.length === 0 && ihits.length === 0 && <p style={{ textAlign: 'center', color: 'var(--muted)', fontSize: 13, marginTop: 30 }}>Nema rezultata za „{q}"</p>}
      </div>
    </RScreen>
  );
}

// ── R11 · ADD SHEET — FAB otvara donji list ─────────────────────────────
function RAddSheet({ t, onClose, onScan, onManual, onSearch, onBatch }) {
  const opt = (Ico, label, sub, onClick, primary) => (
    <div onClick={onClick} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: 14, borderRadius: 16, cursor: onClick ? 'pointer' : 'default',
      background: primary ? 'linear-gradient(180deg, color-mix(in oklab, var(--accent) 70%, #fff) 0%, var(--accent) 40%, var(--accent-deep) 100%)' : 'var(--deep)',
      border: primary ? 'none' : '1px solid var(--line)' }}>
      <div style={{ width: 44, height: 44, borderRadius: 12, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', background: primary ? 'rgba(255,255,255,0.18)' : 'var(--surface)', color: primary ? '#fff' : 'var(--accent)' }}>
        <Ico size={23} />
      </div>
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
        <span style={{ fontWeight: 800, fontSize: 15.5, color: primary ? '#fff' : 'var(--text)' }}>{label}</span>
        <span style={{ fontSize: 12, color: primary ? 'rgba(255,255,255,0.85)' : 'var(--text2)' }}>{sub}</span>
      </div>
      <IcoPlay size={14} color={primary ? '#fff' : 'var(--accent)'} style={{ flexShrink: 0 }} />
    </div>
  );
  return (
    <div style={{ position: 'relative', width: 393, height: 852 }}>
      <div style={{ position: 'absolute', inset: 0, isolation: 'isolate' }}><RScreenHome t={t} /></div>
      <div onClick={onClose} style={{ position: 'absolute', inset: 0, zIndex: 10, borderRadius: 28, overflow: 'hidden', background: 'rgba(6,8,8,0.6)', backdropFilter: 'blur(2px)', cursor: onClose ? 'pointer' : 'default' }}></div>
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 11, borderRadius: '24px 24px 28px 28px', background: 'var(--surface)', ...ccVars(t), padding: '10px 16px 20px', display: 'flex', flexDirection: 'column', gap: 10, boxShadow: '0 -12px 40px rgba(0,0,0,0.6)', fontFamily: "'Roboto', sans-serif", color: 'var(--text)' }}>
        <div style={{ width: 40, height: 4, borderRadius: 999, background: 'var(--line)', margin: '0 auto 4px' }}></div>
        <span style={{ textAlign: 'center', fontWeight: 800, fontSize: 15, letterSpacing: '0.04em' }}>DODAJ STRIP</span>
        {opt(R2IcoBarcode, 'Skeniraj barkod', 'Najbrži način — uperi u stražnju koricu', onScan, true)}
        {opt(IcoSearch, 'Traži po nazivu', 'Pretraži bazu serijala i brojeva', onSearch)}
        {opt(R2IcoPen, 'Ručni unos', 'Upiši serijal, broj i stanje sam', onManual)}
        {opt(R2IcoClock, 'Unos raspona', 'Cijela kolekcija odjednom — npr. 1–50', onBatch)}
      </div>
    </div>
  );
}

Object.assign(window, {
  RScreenWelcome, RScreenSeriesR, RScreenIssueR, RScreenSearchR, RAddSheet, R2_GRADE_OF,
});
