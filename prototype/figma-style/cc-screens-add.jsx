// cc-screens-add.jsx — the screens that were missing from the Figma file:
// Add flow (hub → scan → confirm → manual form), Edit/loan a copy,
// New-releases pull list, and the empty-collection state.
// Built on the same CCScreen / CoverArt / RedButton vocabulary as the rest.

const { SERIES: A_SERIES, ISSUES: A_ISSUES, FEATURED: A_FEAT } = window.CC_DATA;

// ── local icons (same stroke language as cc-ui) ─────────────────────────
const addI = (paths) => ({ size = 22, color = 'currentColor', sw = 2, style }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw}
    strokeLinecap="round" strokeLinejoin="round" style={style}>{paths}</svg>
);
const IcoBarcode = addI(<g><path d="M4 6v12M7 6v12M10 6v12M13.5 6v12M17 6v12M20 6v12" /></g>);
const IcoPen     = addI(<g><path d="M16.5 4.5 19.5 7.5 9 18l-4 1 1-4z" /><path d="M14.5 6.5 17.5 9.5" /></g>);
const IcoCam     = addI(<g><path d="M3 8.5a2 2 0 0 1 2-2h2l1.4-2h7.2L19 6.5h0a2 2 0 0 1 2 2V18a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" /><circle cx="12" cy="13" r="3.6" /></g>);
const IcoBell    = addI(<g><path d="M6 9a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6z" /><path d="M10 20a2 2 0 0 0 4 0" /></g>);
const IcoCal     = addI(<g><rect x="4" y="5.5" width="16" height="15" rx="2.5" /><path d="M4 9.5h16M8.5 3v4.5M15.5 3v4.5" /></g>);
const IcoPlusBox = addI(<g><rect x="3.5" y="3.5" width="17" height="17" rx="4.5" /><path d="M12 8.5v7M8.5 12h7" /></g>);
const IcoTrash   = addI(<g><path d="M5 7h14M9.5 7V4.5h5V7M6.5 7l1 12.5h9l1-12.5" /></g>);
const IcoLoanOut = addI(<g><rect x="14" y="4" width="6.5" height="16" rx="1.5" /><path d="M10 8l-4 4 4 4M3.5 12H10" /></g>);

// ── reusable form field ─────────────────────────────────────────────────
function Field({ label, children }) {
  return (
    <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      <span style={{ fontSize: 11, color: 'var(--muted)', letterSpacing: '0.08em', textTransform: 'uppercase', fontWeight: 600 }}>{label}</span>
      {children}
    </label>
  );
}

const fieldBox = {
  appearance: 'none', width: '100%', boxSizing: 'border-box',
  background: 'var(--surface)', border: '1px solid var(--line)', borderRadius: 12,
  padding: '12px 14px', color: 'var(--text)',
  fontFamily: "'Roboto', sans-serif", fontSize: 14.5, outline: 'none',
};

function TextField({ value, onChange, placeholder, type = 'text', suffix }) {
  return (
    <div style={{ position: 'relative' }}>
      <input type={type} value={value} onChange={e => onChange && onChange(e.target.value)} placeholder={placeholder}
        style={{ ...fieldBox, paddingRight: suffix ? 44 : 14 }} />
      {suffix && <span style={{ position: 'absolute', right: 14, top: '50%', transform: 'translateY(-50%)', fontSize: 13, color: 'var(--muted)', fontWeight: 600 }}>{suffix}</span>}
    </div>
  );
}

function SelectField({ value, onChange, options }) {
  return (
    <div style={{ position: 'relative' }}>
      <select value={value} onChange={e => onChange && onChange(e.target.value)} style={{ ...fieldBox, paddingRight: 38, cursor: 'pointer' }}>
        {options.map(o => <option key={o} value={o} style={{ color: '#111' }}>{o}</option>)}
      </select>
      <span style={{ position: 'absolute', right: 14, top: '50%', transform: 'translateY(-50%)', pointerEvents: 'none', color: 'var(--muted)' }}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="m6 9 6 6 6-6" /></svg>
      </span>
    </div>
  );
}

// Selectable star rating
function StarPick({ value, onChange, size = 26 }) {
  return (
    <div style={{ display: 'flex', gap: 6 }}>
      {[1, 2, 3, 4, 5].map(i => (
        <button key={i} onClick={onChange && (() => onChange(i))} style={{ appearance: 'none', background: 'none', border: 'none', padding: 0, cursor: onChange ? 'pointer' : 'default', lineHeight: 0 }}>
          <IcoStar size={size} off={i > value} />
        </button>
      ))}
    </div>
  );
}

function Toggle({ on, onChange, label }) {
  return (
    <div onClick={onChange && (() => onChange(!on))} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: '12px 14px', borderRadius: 12, background: 'var(--surface)', border: '1px solid var(--line)', cursor: onChange ? 'pointer' : 'default' }}>
      <span style={{ fontSize: 14, fontWeight: 600 }}>{label}</span>
      <div style={{ width: 44, height: 26, borderRadius: 999, background: on ? 'var(--accent)' : 'var(--deep)', position: 'relative', transition: 'background .15s', flexShrink: 0 }}>
        <div style={{ position: 'absolute', top: 3, left: on ? 21 : 3, width: 20, height: 20, borderRadius: '50%', background: '#fff', transition: 'left .15s', boxShadow: '0 1px 3px rgba(0,0,0,0.4)' }}></div>
      </div>
    </div>
  );
}

// ── ADD HUB ─────────────────────────────────────────────────────────────
function ScreenAdd({ t, onNav, onScan, onManual, onSearch, onBack }) {
  const recent = A_ISSUES.filter(it => it.owned).slice(0, 3);
  const opt = (Ico, label, sub, onClick, primary) => (
    <div onClick={onClick} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: 15, borderRadius: 16, cursor: onClick ? 'pointer' : 'default',
      background: primary ? 'linear-gradient(180deg, color-mix(in oklab, var(--accent) 70%, #fff) 0%, var(--accent) 40%, var(--accent-deep) 100%)' : 'var(--surface)',
      boxShadow: primary ? '0 8px 22px rgba(0,0,0,0.45)' : 'var(--card-shadow)', border: primary ? 'none' : '1px solid var(--line)' }}>
      <div style={{ width: 46, height: 46, borderRadius: 13, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', background: primary ? 'rgba(255,255,255,0.18)' : 'var(--deep)', color: primary ? '#fff' : 'var(--accent)' }}>
        <Ico size={24} />
      </div>
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
        <span style={{ fontWeight: 800, fontSize: 16, letterSpacing: '0.02em', color: primary ? '#fff' : 'var(--text)' }}>{label}</span>
        <span style={{ fontSize: 12, color: primary ? 'rgba(255,255,255,0.85)' : 'var(--text2)' }}>{sub}</span>
      </div>
      <IcoPlay size={15} color={primary ? '#fff' : 'var(--accent)'} style={{ flexShrink: 0 }} />
    </div>
  );
  return (
    <CCScreen t={t} nav="home" onNav={onNav}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 2px' }}>
        <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 40, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <IcoBack size={22} />
        </button>
        <div style={{ flex: 1, textAlign: 'center', paddingRight: 40 }}><ComicLogo text="DODAJ STRIP" size={26} font={t.font} /></div>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '8px 16px 20px', display: 'flex', flexDirection: 'column', gap: 11 }}>
        {opt(IcoBarcode, 'Skeniraj barkod', 'Najbrži način — uperi u stražnju koricu', onScan, true)}
        {opt(IcoSearch, 'Traži po nazivu', 'Pretraži bazu serijala i brojeva', onSearch)}
        {opt(IcoPen, 'Ručni unos', 'Upiši serijal, broj i stanje sam', onManual)}
        <div style={{ marginTop: 8 }}>
          <span style={{ fontSize: 11, color: 'var(--muted)', letterSpacing: '0.1em', textTransform: 'uppercase', fontWeight: 700 }}>Nedavno dodano</span>
          <div style={{ display: 'flex', gap: 10, marginTop: 10 }}>
            {recent.map(it => (
              <div key={it.id} style={{ flex: 1, borderRadius: 10, overflow: 'hidden', boxShadow: 'var(--card-shadow)' }}>
                <div style={{ aspectRatio: '3/4', position: 'relative' }}><CoverArt issue={it} height="100%" /></div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </CCScreen>
  );
}

// ── BARCODE SCANNER ─────────────────────────────────────────────────────
function ScreenScan({ t, onNav, onBack, onDetected, onManual }) {
  return (
    <CCScreen t={t} themeOverride="dark" nav="home" onNav={onNav} statusBar={false}>
      {/* camera viewfinder */}
      <div style={{ position: 'absolute', inset: 0, background: '#0A0B0B', overflow: 'hidden' }}>
        <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(120% 80% at 50% 38%, #2A2C2B 0%, #111212 55%, #060707 100%)' }}></div>
        <Halftone color="#fff" opacity={0.06} size={5} />
        {/* faux comic on the camera bed */}
        <div style={{ position: 'absolute', left: '50%', top: '36%', transform: 'translate(-50%,-50%) rotate(-4deg)', width: 168, borderRadius: 8, overflow: 'hidden', boxShadow: '0 20px 50px rgba(0,0,0,0.6)', opacity: 0.92 }}>
          <div style={{ aspectRatio: '3/4', position: 'relative' }}><CoverArt issue={A_ISSUES[24]} height="100%" /></div>
        </div>
      </div>
      {/* top bar */}
      <div style={{ position: 'relative', zIndex: 3, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 16px 0' }}>
        <button onClick={onBack} aria-label="Close" style={{ appearance: 'none', width: 40, height: 40, borderRadius: '50%', background: 'rgba(0,0,0,0.45)', border: 'none', color: '#fff', cursor: onBack ? 'pointer' : 'default', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <IcoX size={20} sw={2.4} />
        </button>
        <span style={{ fontSize: 13, color: '#fff', fontWeight: 600, background: 'rgba(0,0,0,0.45)', padding: '7px 14px', borderRadius: 999 }}>Skeniranje barkoda</span>
        <div style={{ width: 40 }}></div>
      </div>
      {/* reticle */}
      <div style={{ position: 'relative', zIndex: 3, flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 26 }}>
        <div style={{ position: 'relative', width: 250, height: 150 }}>
          {[['0','0','t','l'],['0','0','t','r'],['0','0','b','l'],['0','0','b','r']].map((_, i) => {
            const top = i < 2, left = i % 2 === 0;
            return <div key={i} style={{ position: 'absolute', [top ? 'top' : 'bottom']: 0, [left ? 'left' : 'right']: 0, width: 34, height: 34,
              borderTop: top ? '4px solid var(--accent)' : 'none', borderBottom: !top ? '4px solid var(--accent)' : 'none',
              borderLeft: left ? '4px solid var(--accent)' : 'none', borderRight: !left ? '4px solid var(--accent)' : 'none',
              borderTopLeftRadius: top && left ? 10 : 0, borderTopRightRadius: top && !left ? 10 : 0,
              borderBottomLeftRadius: !top && left ? 10 : 0, borderBottomRightRadius: !top && !left ? 10 : 0 }}></div>;
          })}
          <div style={{ position: 'absolute', left: 12, right: 12, top: '50%', height: 2.5, background: 'var(--accent)', boxShadow: '0 0 14px 2px var(--accent)', borderRadius: 2 }}></div>
        </div>
        <span style={{ fontSize: 13.5, color: 'rgba(255,255,255,0.85)', fontWeight: 500 }}>Poravnaj barkod unutar okvira</span>
      </div>
      {/* bottom actions */}
      <div style={{ position: 'relative', zIndex: 3, padding: '0 24px 30px', display: 'flex', flexDirection: 'column', gap: 14, alignItems: 'center' }}>
        <button onClick={onDetected} style={{ appearance: 'none', cursor: onDetected ? 'pointer' : 'default', width: 64, height: 64, borderRadius: '50%', border: '4px solid rgba(255,255,255,0.85)', background: 'var(--accent)', color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 6px 20px rgba(0,0,0,0.5)' }}>
          <IcoCam size={28} />
        </button>
        <button onClick={onManual} style={{ appearance: 'none', background: 'none', border: 'none', cursor: onManual ? 'pointer' : 'default', color: 'rgba(255,255,255,0.9)', fontSize: 13.5, fontWeight: 600, fontFamily: "'Roboto', sans-serif" }}>
          Barkod ne radi? Ručni unos →
        </button>
      </div>
    </CCScreen>
  );
}

// ── SCAN RESULT / CONFIRM MATCH ─────────────────────────────────────────
function ScreenScanResult({ t, onNav, onBack, onAdd, onReject }) {
  const it = A_ISSUES[24]; // #25 Morgana
  const [cond, setCond] = React.useState(4);
  const meta = (k, v) => (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '11px 0', borderBottom: '1px solid var(--line)' }}>
      <span style={{ fontSize: 13, color: 'var(--text2)' }}>{k}</span>
      <span style={{ fontSize: 14, fontWeight: 700 }}>{v}</span>
    </div>
  );
  return (
    <CCScreen t={t} nav="home" onNav={onNav} grunge={true}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 2px', position: 'relative', zIndex: 2 }}>
        <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 40, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <IcoBack size={22} />
        </button>
        <div style={{ flex: 1, textAlign: 'center', paddingRight: 40 }}><ComicLogo text="PRONAĐENO" size={26} font={t.font} /></div>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '6px 24px 20px', position: 'relative', zIndex: 2 }}>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 7, padding: '6px 12px', borderRadius: 999, background: 'rgba(46,158,46,0.16)', border: '1px solid rgba(46,158,46,0.5)', color: '#3EC63E', fontSize: 12, fontWeight: 700, marginBottom: 14 }}>
          <IcoCheck size={14} sw={3} /> Barkod prepoznat · 8050024 25
        </div>
        <div style={{ display: 'flex', gap: 14 }}>
          <div style={{ width: 110, flexShrink: 0, borderRadius: 10, overflow: 'hidden', boxShadow: '0 10px 26px rgba(0,0,0,0.5)' }}>
            <div style={{ aspectRatio: '3/4', position: 'relative' }}><CoverArt issue={it} height="100%" /></div>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <h2 style={{ margin: 0, fontSize: 18, fontWeight: 800, letterSpacing: '0.02em' }}>Dylan Dog EXTRA</h2>
            <p style={{ margin: '4px 0 0', fontSize: 15, color: 'var(--text)' }}>#{it.number} — {it.title}</p>
            <div style={{ marginTop: 10, fontSize: 13, color: 'var(--text2)', lineHeight: 1.7 }}>
              <div>Ludens · {it.year}</div>
              <div>Sclavi &amp; Stano</div>
            </div>
            <div style={{ marginTop: 8 }}><Stars value={it.rating} size={15} /></div>
          </div>
        </div>
        <div style={{ marginTop: 18 }}>
          <span style={{ fontSize: 11, color: 'var(--muted)', letterSpacing: '0.08em', textTransform: 'uppercase', fontWeight: 600 }}>Stanje primjerka</span>
          <div style={{ marginTop: 8 }}><StarPick value={cond} onChange={setCond} /></div>
        </div>
        <div style={{ marginTop: 16, padding: '0 2px' }}>
          {meta('Edicija', 'EXTRA')}
          {meta('Izdavač', 'Ludens')}
          {meta('Procijenjena vrijednost', '~' + (it.value || 6) + ' €')}
        </div>
      </div>
      <div style={{ position: 'relative', zIndex: 2, padding: '0 16px 16px', display: 'flex', gap: 10 }}>
        <button onClick={onReject} style={{ appearance: 'none', cursor: onReject ? 'pointer' : 'default', flex: 1, border: '1.5px solid var(--line)', borderRadius: 999, padding: '13px 8px', background: 'transparent', color: 'var(--text2)', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 13.5 }}>Nije ovo</button>
        <RedButton onClick={onAdd} style={{ flex: 2 }}>DODAJ U KOLEKCIJU</RedButton>
      </div>
    </CCScreen>
  );
}

// ── MANUAL ADD FORM ─────────────────────────────────────────────────────
function ScreenManualAdd({ t, onNav, onBack, onSave }) {
  const [series, setSeries] = React.useState('DYLAN DOG');
  const sObj = A_SERIES.find(s => s.name === series) || A_SERIES[0];
  const editions = sObj.editions.map(e => e.name);
  const [edition, setEdition] = React.useState(editions[0]);
  const [num, setNum] = React.useState('');
  const [year, setYear] = React.useState('');
  const [price, setPrice] = React.useState('');
  const [cond, setCond] = React.useState(4);
  const [read, setRead] = React.useState(false);
  const [dupli, setDupli] = React.useState(false);
  React.useEffect(() => { setEdition(editions[0]); }, [series]);
  return (
    <CCScreen t={t} nav="home" onNav={onNav}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 2px' }}>
        <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 40, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <IcoBack size={22} />
        </button>
        <div style={{ flex: 1, textAlign: 'center', paddingRight: 40 }}><ComicLogo text="RUČNI UNOS" size={24} font={t.font} /></div>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '8px 16px 16px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <Field label="Serijal"><SelectField value={series} onChange={setSeries} options={A_SERIES.map(s => s.name)} /></Field>
        <Field label="Edicija"><SelectField value={edition} onChange={setEdition} options={editions} /></Field>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <Field label="Broj"><TextField value={num} onChange={setNum} placeholder="npr. 25" type="number" /></Field>
          <Field label="Godina"><TextField value={year} onChange={setYear} placeholder="1999" type="number" /></Field>
        </div>
        <Field label="Stanje">
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 14px', borderRadius: 12, background: 'var(--surface)', border: '1px solid var(--line)' }}>
            <StarPick value={cond} onChange={setCond} size={24} />
            <span style={{ fontSize: 14, fontWeight: 700, color: 'var(--text2)' }}>{cond}/5</span>
          </div>
        </Field>
        <Field label="Nabavna cijena"><TextField value={price} onChange={setPrice} placeholder="0" type="number" suffix="€" /></Field>
        <Toggle on={read} onChange={setRead} label="Već pročitano" />
        <Toggle on={dupli} onChange={setDupli} label="Dupli primjerak" />
      </div>
      <div style={{ padding: '0 16px 16px' }}>
        <RedButton onClick={onSave} style={{ width: '100%' }}>SPREMI U KOLEKCIJU</RedButton>
      </div>
    </CCScreen>
  );
}

// ── EDIT / LOAN A COPY ──────────────────────────────────────────────────
function ScreenEditCopy({ t, issue, onNav, onBack, onSave }) {
  const it = issue || A_FEAT;
  const [cond, setCond] = React.useState(it.condition || 4);
  const [value, setValue] = React.useState(String(it.value || 6));
  const [dupli, setDupli] = React.useState(!!it.dupli);
  const [loanOn, setLoanOn] = React.useState(!!it.loaned);
  const [loanTo, setLoanTo] = React.useState(it.loaned ? it.loaned.to : '');
  return (
    <CCScreen t={t} nav="home" onNav={onNav}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 2px' }}>
        <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 40, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <IcoBack size={22} />
        </button>
        <div style={{ flex: 1, textAlign: 'center', paddingRight: 40 }}><ComicLogo text="UREDI BROJ" size={24} font={t.font} /></div>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '8px 16px 16px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div style={{ display: 'flex', gap: 14, alignItems: 'center', padding: 12, borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)' }}>
          <div style={{ width: 56, height: 76, borderRadius: 8, overflow: 'hidden', flexShrink: 0 }}><CoverArt issue={it} height="100%" /></div>
          <div style={{ minWidth: 0 }}>
            <span style={{ fontWeight: 800, fontSize: 16 }}>#{it.number} — {it.title}</span>
            <div style={{ fontSize: 12, color: 'var(--text2)', marginTop: 3 }}>Dylan Dog · EXTRA · {it.year}</div>
          </div>
        </div>
        <Field label="Stanje">
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 14px', borderRadius: 12, background: 'var(--surface)', border: '1px solid var(--line)' }}>
            <StarPick value={cond} onChange={setCond} size={24} />
            <span style={{ fontSize: 14, fontWeight: 700, color: 'var(--text2)' }}>{cond}/5</span>
          </div>
        </Field>
        <Field label="Procijenjena vrijednost"><TextField value={value} onChange={setValue} type="number" suffix="€" /></Field>
        <Toggle on={dupli} onChange={setDupli} label="Imam dupli primjerak" />
        <Toggle on={loanOn} onChange={setLoanOn} label="Posuđeno nekome" />
        {loanOn && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12, padding: 14, borderRadius: 14, background: 'rgba(169,26,26,0.10)', border: '1px solid rgba(169,26,26,0.35)' }}>
            <Field label="Kome"><TextField value={loanTo} onChange={setLoanTo} placeholder="Ime" /></Field>
            <Field label="Od kada"><TextField value={it.loaned ? it.loaned.since : ''} placeholder="MM/GGGG" /></Field>
          </div>
        )}
        <button onClick={onSave} style={{ appearance: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, cursor: onSave ? 'pointer' : 'default', border: '1.5px solid rgba(169,26,26,0.5)', background: 'transparent', color: '#D9514A', borderRadius: 12, padding: '12px', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 13.5, marginTop: 2 }}>
          <IcoTrash size={17} /> Ukloni iz kolekcije
        </button>
      </div>
      <div style={{ padding: '0 16px 16px' }}>
        <RedButton onClick={onSave} style={{ width: '100%' }}>SPREMI PROMJENE</RedButton>
      </div>
    </CCScreen>
  );
}

// ── NEW RELEASES / PULL LIST ────────────────────────────────────────────
const A_RELEASES = [
  { id: 'r1', series: 'DYLAN DOG', edition: 'EXTRA', number: 87, title: 'Sjena nad Londonom', date: '28. lip', soon: true,  watch: true,  iss: A_ISSUES[2] },
  { id: 'r2', series: 'TEX',       edition: 'ORIGINAL', number: 121, title: 'Kanjon duhova', date: '05. srp', soon: true,  watch: false, iss: A_ISSUES[7] },
  { id: 'r3', series: 'ZAGOR',     edition: 'ORIGINAL', number: 97, title: 'Darkwood gori', date: '12. srp', soon: false, watch: true,  iss: A_ISSUES[12] },
  { id: 'r4', series: 'DYLAN DOG', edition: 'MAXI', number: 18, title: 'Posljednji vlak', date: '19. srp', soon: false, watch: false, iss: A_ISSUES[19] },
  { id: 'r5', series: 'MARTIN MYSTÈRE', edition: 'ORIGINAL', number: 39, title: 'Atlantida', date: '02. kol', soon: false, watch: false, iss: A_ISSUES[23] },
];

function ScreenReleases({ t, onNav, onBack }) {
  const [watch, setWatch] = React.useState(() => Object.fromEntries(A_RELEASES.map(r => [r.id, r.watch])));
  const groups = [
    { key: 'soon', label: 'Ovaj tjedan', items: A_RELEASES.filter(r => r.soon) },
    { key: 'later', label: 'Uskoro', items: A_RELEASES.filter(r => !r.soon) },
  ];
  return (
    <CCScreen t={t} nav="home" onNav={onNav}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 2px' }}>
        <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 40, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <IcoBack size={22} />
        </button>
        <div style={{ flex: 1, textAlign: 'center', paddingRight: 40 }}><ComicLogo text="U NAJAVI" size={26} font={t.font} /></div>
      </div>
      <p style={{ margin: '0 16px 8px', textAlign: 'center', fontSize: 12.5, color: 'var(--muted)' }}>
        Nadolazeći brojevi — uključi <IcoBell size={13} style={{ verticalAlign: '-2px' }} /> za obavijest
      </p>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '4px 16px 20px', display: 'flex', flexDirection: 'column', gap: 16 }}>
        {groups.map(g => (
          <div key={g.key}>
            <span style={{ fontSize: 11, color: 'var(--muted)', letterSpacing: '0.1em', textTransform: 'uppercase', fontWeight: 700 }}>{g.label}</span>
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
                    <span style={{ fontSize: 11.5, color: 'var(--text2)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.edition} · {r.title}</span>
                  </div>
                  <button onClick={() => setWatch(w => ({ ...w, [r.id]: !w[r.id] }))} aria-label="Obavijesti me" style={{ appearance: 'none', cursor: 'pointer', width: 38, height: 38, borderRadius: 11, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', border: '1px solid ' + (watch[r.id] ? 'var(--accent)' : 'var(--line)'), background: watch[r.id] ? 'var(--accent)' : 'transparent', color: watch[r.id] ? '#fff' : 'var(--muted)' }}>
                    <IcoBell size={19} />
                  </button>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </CCScreen>
  );
}

// ── EMPTY COLLECTION STATE ──────────────────────────────────────────────
function ScreenEmpty({ t, onNav, onAdd }) {
  return (
    <CCScreen t={t} nav="home" onNav={onNav}>
      <CCTitle t={t} text="COMICS COLLECTION" />
      <div style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center', padding: '0 40px 40px', gap: 18 }}>
        <div style={{ position: 'relative', width: 120, height: 120, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div style={{ position: 'absolute', inset: 0, borderRadius: 30, background: 'var(--accent)', opacity: 0.12 }}></div>
          <div style={{ position: 'absolute', inset: 0, borderRadius: 30, border: '2px dashed var(--accent)', opacity: 0.5 }}></div>
          <IcoBook size={56} color="var(--accent)" sw={1.6} />
        </div>
        <div>
          <h2 style={{ margin: 0, fontSize: 22, fontWeight: 800, letterSpacing: '0.02em' }}>Polica je prazna</h2>
          <p style={{ margin: '8px 0 0', fontSize: 14, color: 'var(--text2)', lineHeight: 1.6, maxWidth: 250 }}>
            Skeniraj barkod ili upiši prvi strip i počni graditi svoju kolekciju.
          </p>
        </div>
        <RedButton onClick={onAdd} style={{ marginTop: 4 }}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}><IcoPlusBox size={18} /> DODAJ PRVI STRIP</span>
        </RedButton>
        <button style={{ appearance: 'none', background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text2)', fontSize: 13.5, fontWeight: 600, fontFamily: "'Roboto', sans-serif", marginTop: 2 }}>
          Uvezi iz CSV datoteke
        </button>
      </div>
    </CCScreen>
  );
}

Object.assign(window, {
  ScreenAdd, ScreenScan, ScreenScanResult, ScreenManualAdd, ScreenEditCopy, ScreenReleases, ScreenEmpty,
  Field, TextField, SelectField, Toggle, StarPick,
});
