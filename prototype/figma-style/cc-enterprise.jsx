// cc-enterprise.jsx — ENTERPRISE verzija (knjižnice / strip dućani):
// E1 pregled inventara, E2 lokacije/police, E3 prijem robe (batch sken),
// E4 posudbe članova. Isti vizualni jezik kao consumer redizajn, vlastiti nav.

const { SERIES: E_SERIES, ISSUES: E_ISSUES } = window.CC_DATA;

const eI = (paths) => ({ size = 22, color = 'currentColor', sw = 2, style }) =>
<svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw}
strokeLinecap="round" strokeLinejoin="round" style={style}>{paths}</svg>;

const EIcoGrid = eI(<g><rect x="4" y="4" width="7" height="7" rx="1.5" /><rect x="13" y="4" width="7" height="7" rx="1.5" /><rect x="4" y="13" width="7" height="7" rx="1.5" /><rect x="13" y="13" width="7" height="7" rx="1.5" /></g>);
const EIcoShelf = eI(<g><path d="M3.5 5h17M3.5 12h17M3.5 19h17" /><path d="M6 5v7M11 5v7M16 12v7M8.5 12v7" /></g>);
const EIcoUsers = eI(<g><circle cx="9" cy="8.5" r="3.2" /><path d="M3.5 19.5a5.5 5.5 0 0 1 11 0" /><circle cx="16.5" cy="9.5" r="2.6" /><path d="M15.5 14.6a4.8 4.8 0 0 1 5 4.9" /></g>);
const EIcoScan = eI(<g><path d="M4 8V5.5A1.5 1.5 0 0 1 5.5 4H8M16 4h2.5A1.5 1.5 0 0 1 20 5.5V8M20 16v2.5a1.5 1.5 0 0 1-1.5 1.5H16M8 20H5.5A1.5 1.5 0 0 1 4 18.5V16" /><path d="M4 12h16" /></g>);
const EIcoBox = eI(<g><path d="M3.5 8 12 3.5 20.5 8v8L12 20.5 3.5 16z" /><path d="M3.5 8 12 12.5 20.5 8M12 12.5v8" /></g>);
const EIcoClockE = eI(<g><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5V12l3 2" /></g>);
const EIcoMove = eI(<g><path d="M5 9l-3 3 3 3M19 9l3 3-3 3M9 5l3-3 3 3M9 19l3 3 3-3M2 12h20M12 2v20" /></g>);

const E_LOCATIONS = [
{ id: 'a1', name: 'Polica A1', zone: 'Bonelli — Dylan Dog', count: 84, cap: 90 },
{ id: 'a2', name: 'Polica A2', zone: 'Bonelli — Tex, Zagor', count: 122, cap: 140 },
{ id: 'b1', name: 'Polica B1', zone: 'Marvel / DC', count: 67, cap: 120 },
{ id: 's3', name: 'Kutija S3', zone: 'Skladište — dupli', count: 41, cap: 60 },
{ id: 's4', name: 'Kutija S4', zone: 'Skladište — otkup, neobrađeno', count: 23, cap: 60 }];


const E_LOANS = [
{ id: 'l1', member: 'Ivana K.', card: '0042', iss: E_ISSUES[3], due: '05. srp', overdue: false },
{ id: 'l2', member: 'Marko P.', card: '0117', iss: E_ISSUES[8], due: '28. lip', overdue: true },
{ id: 'l3', member: 'Ana V.', card: '0009', iss: E_ISSUES[12], due: '30. lip', overdue: true },
{ id: 'l4', member: 'Luka B.', card: '0201', iss: E_ISSUES[19], due: '11. srp', overdue: false },
{ id: 'l5', member: 'Petra M.', card: '0088', iss: E_ISSUES[24], due: '15. srp', overdue: false }];


// ── enterprise nav (Pregled / Inventar / [sken] / Posudbe / Postavke) ──
function ENavBar({ active = 'pregled', onNav, onScan }) {
  const side = (id, Ico, label) =>
  <button key={id} aria-label={label} onClick={onNav ? () => onNav(id) : undefined} style={{
    appearance: 'none', background: 'none', border: 'none', cursor: onNav ? 'pointer' : 'default',
    height: 52, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 3,
    color: active === id ? 'var(--accent)' : 'var(--muted)'
  }}>
      <Ico size={23} sw={active === id ? 2.4 : 2} />
      <span style={{ fontSize: 10.5, fontWeight: active === id ? 700 : 500, fontFamily: "'Roboto', sans-serif" }}>{label}</span>
    </button>;

  return (
    <div style={{ position: 'relative', flexShrink: 0, zIndex: 5 }}>
      <button onClick={onScan} aria-label="Skeniraj" style={{
        appearance: 'none', cursor: onScan ? 'pointer' : 'default',
        position: 'absolute', left: '50%', top: -26, transform: 'translateX(-50%)',
        width: 58, height: 58, borderRadius: '50%', border: '4px solid var(--bg)',
        background: 'linear-gradient(180deg, color-mix(in oklab, var(--accent) 78%, #fff) 0%, var(--accent) 38%, var(--accent-deep) 100%)',
        color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center',
        boxShadow: '0 6px 18px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.4)'
      }}>
        <EIcoScan size={26} sw={2.2} />
      </button>
      <div style={{
        height: 68, background: 'var(--nav)', borderTop: '1px solid var(--line)',
        display: 'grid', gridTemplateColumns: '1fr 1fr 74px 1fr 1fr',
        alignItems: 'center', justifyItems: 'center'
      }}>
        {side('pregled', EIcoGrid, 'Pregled')}
        {side('inventar', EIcoShelf, 'Inventar')}
        <div></div>
        {side('posudbe', EIcoUsers, 'Posudbe')}
        {side('postavke', IcoGear, 'Postavke')}
      </div>
    </div>);

}

function EScreen({ children, t, nav, onNav, onScan }) {
  return (
    <div className="cc-screen" style={{
      ...ccVars(t), width: 393, height: 852, borderRadius: 28, overflow: 'hidden',
      background: 'var(--bg)', boxShadow: '0 0 0 8px #CAC4D0',
      display: 'flex', flexDirection: 'column', position: 'relative',
      fontFamily: "'Roboto', sans-serif", color: 'var(--text)'
    }}>
      <CCStatusBar />
      <div style={{ flex: 1, minHeight: 0, position: 'relative', display: 'flex', flexDirection: 'column' }}>
        {children}
      </div>
      <ENavBar active={nav} onNav={onNav} onScan={onScan} />
    </div>);

}

function EHeader({ t, text, badge = 'ENTERPRISE', onBack }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 2px' }}>
      {onBack ?
      <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text2)', width: 44, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><IcoBack size={22} /></button> :
      <div style={{ width: 44 }}></div>}
      <div style={{ flex: 1, textAlign: 'center' }}>
        <ComicLogo text={text} size={22} font={t.font} />
        <div style={{ marginTop: 4 }}>
          <span style={{ fontSize: 10, fontWeight: 800, letterSpacing: '0.14em', color: 'var(--accent)', border: '1px solid var(--accent)', borderRadius: 999, padding: '2px 9px' }}>{badge}</span>
        </div>
      </div>
      <div style={{ width: 44 }}></div>
    </div>);

}

function EBar({ value, max, warn }) {
  const pct = max > 0 ? Math.min(100, Math.round(value / max * 100)) : 0;
  // kapacitet: zeleno = ima mjesta, žuto = pri vrhu, crveno = puno
  const fill = pct >= 92 ? '#D9514A' : pct >= 75 ? '#E8C547' : '#2E9E2E';
  return (
    <div style={{ height: 7, borderRadius: 999, background: 'var(--deep)', overflow: 'hidden' }}>
      <div style={{ width: pct + '%', height: '100%', borderRadius: 999, background: fill }}></div>
    </div>);

}

// ── E0 · AKTIVACIJA — pristup preko ugovora ────────────────────────
function EScreenActivate({ t, onDone }) {
  const [step, setStep] = React.useState(0);
  const [contract, setContract] = React.useState('CC-2026-0142');
  const [code, setCode] = React.useState('');
  const [mail, setMail] = React.useState('');
  const [loc, setLoc] = React.useState('zg1');
  const LOCS = [
  { id: 'zg1', name: 'Zagreb — Ilica 45', sub: 'glavna poslovnica' },
  { id: 'zg2', name: 'Zagreb — Dubrava 12', sub: 'poslovnica' },
  { id: 'st1', name: 'Split — Riva 8', sub: 'poslovnica' }];

  return (
    <div className="cc-screen" style={{
      ...ccVars(t, 'dark'), width: 393, height: 852, borderRadius: 28, overflow: 'hidden',
      background: 'var(--bg)', boxShadow: '0 0 0 8px #CAC4D0',
      display: 'flex', flexDirection: 'column', position: 'relative',
      fontFamily: "'Roboto', sans-serif", color: 'var(--text)'
    }}>
      <GrungeBg />
      <CCStatusBar />
      <div style={{ position: 'relative', zIndex: 2, flex: 1, minHeight: 0, overflowY: 'auto', padding: '18px 28px 30px', display: 'flex', flexDirection: 'column' }}>
        <div style={{ textAlign: 'center', margin: '14px 0 8px', filter: 'drop-shadow(0 0 14px rgba(198,41,30,0.4))' }}>
          <ComicLogo text="COMICOLLECT" size={30} font={t.font} />
        </div>
        <div style={{ textAlign: 'center', marginBottom: 22 }}>
          <span style={{ fontSize: 10, fontWeight: 800, letterSpacing: '0.14em', color: 'var(--accent)', border: '1px solid var(--accent)', borderRadius: 999, padding: '3px 10px' }}>ENTERPRISE</span>
        </div>
        {step === 0 ?
        <React.Fragment>
            <p style={{ margin: '0 0 18px', fontSize: 13.5, color: 'var(--text2)', lineHeight: 1.6, textAlign: 'center' }}>
              Pristup se otvara <b style={{ color: 'var(--text)' }}>ugovorom</b> — broj ugovora i aktivacijski kod stižu e-mailom nakon potpisa.
            </p>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <Field label="Broj ugovora"><TextField value={contract} onChange={setContract} placeholder="CC-2026-0000" /></Field>
              <Field label="Aktivacijski kod"><TextField value={code} onChange={setCode} placeholder="8 znakova" /></Field>
              <Field label="E-mail voditelja"><TextField value={mail} onChange={setMail} placeholder="voditelj@knjiznica.hr" type="email" /></Field>
              <RedButton onClick={() => setStep(1)} style={{ width: '100%', marginTop: 6 }}>PROVJERI UGOVOR</RedButton>
            </div>
            <p style={{ margin: '16px 0 0', fontSize: 12, color: 'var(--muted)', textAlign: 'center', lineHeight: 1.6 }}>Nemaš ugovor? Javi se na <b>enterprise@comicollect.app</b></p>
          </React.Fragment> :

        <React.Fragment>
            <div style={{ alignSelf: 'center', display: 'inline-flex', alignItems: 'center', gap: 7, padding: '6px 12px', borderRadius: 999, background: 'rgba(62,198,62,0.14)', border: '1px solid rgba(62,198,62,0.5)', color: '#3EC63E', fontSize: 12.5, fontWeight: 700, marginBottom: 16 }}>
              <IcoCheck size={14} sw={3} /> Ugovor {contract} · Strip knjižnica Zagreb
            </div>
            <p style={{ margin: '0 0 14px', fontSize: 13.5, color: 'var(--text2)', lineHeight: 1.6, textAlign: 'center' }}>
              Odaberi svoju <b style={{ color: 'var(--text)' }}>lokaciju</b> (poslovnicu). Pozicije — police i kutije poput A1 — uređuješ kasnije u Inventaru.
            </p>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
              {LOCS.map((l) =>
            <div key={l.id} onClick={() => setLoc(l.id)} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 15px', borderRadius: 14, background: 'var(--surface)', border: '1.5px solid ' + (loc === l.id ? 'var(--accent)' : 'var(--line)'), cursor: 'pointer' }}>
                  <div style={{ width: 20, height: 20, borderRadius: '50%', border: '2px solid ' + (loc === l.id ? 'var(--accent)' : 'var(--muted)'), display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                    {loc === l.id && <div style={{ width: 10, height: 10, borderRadius: '50%', background: 'var(--accent)' }}></div>}
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
                    <span style={{ fontWeight: 700, fontSize: 14.5 }}>{l.name}</span>
                    <span style={{ fontSize: 12, color: 'var(--text2)' }}>{l.sub}</span>
                  </div>
                </div>
            )}
            </div>
            <RedButton onClick={onDone} style={{ width: '100%', marginTop: 16 }}>AKTIVIRAJ POSLOVNICU</RedButton>
          </React.Fragment>
        }
      </div>
    </div>);

}

// ── E1 · PREGLED — dashboard ────────────────────────────────────────────
function EScreenDash({ t, onNav, onScan, onOpenLocations, onOpenLoans, onOpenRes }) {
  const overdue = E_LOANS.filter((l) => l.overdue).length;
  const stat = (label, big, sub, onClick) =>
  <div onClick={onClick} style={{ padding: '12px 14px', borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', display: 'flex', flexDirection: 'column', gap: 2, cursor: onClick ? 'pointer' : 'default' }}>
      <span style={{ fontSize: 11.5, color: 'var(--muted)', letterSpacing: '0.08em', textTransform: 'uppercase', fontWeight: 600 }}>{label}</span>
      <span style={{ fontSize: 23, fontWeight: 800 }}>{big}</span>
      {sub && <span style={{ fontSize: 12, color: 'var(--text2)' }}>{sub}</span>}
    </div>;

  return (
    <EScreen t={t} nav="pregled" onNav={onNav} onScan={onScan}>
      <EHeader t={t} text="STRIP KNJIŽNICA ZAGREB" badge="ENTERPRISE · ILICA 45" />
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '8px 16px 24px', display: 'flex', flexDirection: 'column', gap: 16 }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          {stat('Primjeraka', '337', '214 naslova')}
          {stat('Posuđeno', E_LOANS.length, overdue + ' kasni', onOpenLoans)}
          {stat('Prijem ovaj tjedan', '23', 'kutija S4 čeka obradu', onScan)}
          {stat('Rezervacije', '7', '3 spremne za preuzimanje', onOpenRes)}
        </div>
        <div>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 10 }}>
            <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.1em', textTransform: 'uppercase', fontWeight: 700 }}>Popunjenost pozicija</span>
            <span onClick={onOpenLocations} style={{ fontSize: 12.5, color: 'var(--accent)', fontWeight: 700, cursor: 'pointer' }}>Sve →</span>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
            {E_LOCATIONS.slice(0, 4).map((l) =>
            <div key={l.id} style={{ padding: '10px 13px', borderRadius: 13, background: 'var(--surface)', boxShadow: 'var(--card-shadow)' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 7 }}>
                  <span style={{ fontWeight: 700, fontSize: 13.5 }}>{l.name} <span style={{ fontWeight: 500, color: 'var(--text2)', fontSize: 12 }}>· {l.zone}</span></span>
                  <span style={{ fontSize: 12, color: 'var(--text2)', flexShrink: 0 }}>{l.count}/{l.cap}</span>
                </div>
                <EBar value={l.count} max={l.cap} warn />
              </div>
            )}
          </div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '11px 14px', borderRadius: 13, background: 'rgba(232,197,71,0.10)', border: '1px solid rgba(232,197,71,0.45)' }}>
          <span style={{ color: '#E8C547', display: 'flex', flexShrink: 0 }}><EIcoClockE size={19} /></span>
          <span style={{ fontSize: 13, lineHeight: 1.5 }}><b>{overdue} posudbe kasne</b> — pošalji podsjetnik članovima</span>
          <button style={{ appearance: 'none', cursor: 'pointer', marginLeft: 'auto', flexShrink: 0, background: 'none', border: 'none', color: 'var(--accent)', fontWeight: 700, fontSize: 12.5, fontFamily: "'Roboto', sans-serif" }}>Pošalji</button>
        </div>
        <div>
          <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.1em', textTransform: 'uppercase', fontWeight: 700 }}>Nedavno</span>
          <div style={{ borderRadius: 13, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', overflow: 'hidden', marginTop: 10 }}>
            {[
            { Ico: EIcoUsers, txt: <span>Povrat — <b>Ivana K.</b> vratila Tex #121</span>, when: '9:12' },
            { Ico: EIcoScan, txt: <span>Zaprimljeno <b>23 primjerka</b> → Kutija S4</span>, when: 'jučer' },
            { Ico: EIcoUsers, txt: <span>Nova posudba — <b>Luka B.</b> · Zagor #96</span>, when: 'jučer' },
            { Ico: EIcoBox, txt: <span>Premješteno <b>12 primjeraka</b> S3 → Polica B1</span>, when: '01. srp' }].
            map((a, i) =>
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '11px 13px', borderTop: i > 0 ? '1px solid var(--line)' : 'none' }}>
                <div style={{ width: 32, height: 32, borderRadius: 9, background: 'var(--deep)', color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}><a.Ico size={16} /></div>
                <span style={{ flex: 1, minWidth: 0, fontSize: 12.5, color: 'var(--text2)', lineHeight: 1.45 }}>{a.txt}</span>
                <span style={{ fontSize: 11.5, color: 'var(--muted)', flexShrink: 0 }}>{a.when}</span>
              </div>
            )}
          </div>
        </div>
      </div>
    </EScreen>);

}

// ── E2 · INVENTAR — lokacije i police ───────────────────────────────────
function EScreenLocations({ t, onNav, onScan, onBack, onOpenPos }) {
  const [q, setQ] = React.useState('');
  const list = E_LOCATIONS.filter((l) => (l.name + ' ' + l.zone).toLowerCase().includes(q.trim().toLowerCase()));
  return (
    <EScreen t={t} nav="inventar" onNav={onNav} onScan={onScan}>
      <EHeader t={t} text="POZICIJE" badge="LOKACIJA: ILICA 45" onBack={onBack} />
      <div style={{ display: 'flex', gap: 7, padding: '4px 16px 8px', overflowX: 'auto' }}>
        {['Zagreb — Ilica 45', 'Zagreb — Dubrava 12', 'Split — Riva 8'].map((p, i) =>
        <button key={p} style={{ appearance: 'none', cursor: 'pointer', flexShrink: 0, border: '1px solid ' + (i === 0 ? 'var(--accent)' : 'var(--line)'), borderRadius: 999, padding: '6px 12px', background: i === 0 ? 'var(--accent)' : 'transparent', color: i === 0 ? '#FFF' : 'var(--text2)', fontFamily: "'Roboto', sans-serif", fontWeight: 600, fontSize: 11.5 }}>{p}</button>
        )}
      </div>
      <div style={{ padding: '6px 16px 10px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 14px', borderRadius: 999, background: 'var(--surface)', border: '1px solid var(--line)' }}>
          <span style={{ color: 'var(--muted)', display: 'flex' }}><IcoSearch size={17} /></span>
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Pozicija — polica, kutija, zona…" style={{ flex: 1, minWidth: 0, background: 'none', border: 'none', outline: 'none', fontFamily: "'Roboto', sans-serif", fontSize: 13.5, color: 'var(--text)' }} />
        </div>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '0 16px 24px', display: 'flex', flexDirection: 'column', gap: 9 }}>
        {list.map((l) =>
        <div key={l.id} onClick={onOpenPos && (() => onOpenPos(l))} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 12, borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', cursor: onOpenPos ? 'pointer' : 'default' }}>
            <div style={{ width: 42, height: 42, borderRadius: 11, background: 'var(--deep)', color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
              {l.id.startsWith('s') ? <EIcoBox size={21} /> : <EIcoShelf size={21} />}
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                <span style={{ fontWeight: 800, fontSize: 14.5 }}>{l.name}</span>
                <span style={{ fontSize: 12, color: 'var(--text2)', flexShrink: 0 }}>{l.count}/{l.cap}</span>
              </div>
              <div style={{ fontSize: 12, color: 'var(--text2)', margin: '2px 0 7px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{l.zone}</div>
              <EBar value={l.count} max={l.cap} warn />
            </div>
            <button title="Premjesti sadržaj" style={{ appearance: 'none', cursor: 'pointer', width: 36, height: 36, borderRadius: 10, border: '1px solid var(--line)', background: 'transparent', color: 'var(--muted)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
              <EIcoMove size={17} />
            </button>
          </div>
        )}
        <button style={{ appearance: 'none', cursor: 'pointer', border: '1.5px dashed var(--line)', borderRadius: 14, padding: '13px', background: 'transparent', color: 'var(--text2)', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 13 }}>+ Nova pozicija</button>
      </div>
    </EScreen>);

}

// ── E3 · PRIJEM ROBE — batch sken s lokacijom ──────────────────────────
function EScreenReceiving({ t, onClose, startOpen = false }) {
  const pool = [E_ISSUES[7], E_ISSUES[12], E_ISSUES[19], E_ISSUES[3], E_ISSUES[24]];
  const [list, setList] = React.useState([E_ISSUES[7]]);
  const [mode, setMode] = React.useState('barkod');
  const [flash, setFlash] = React.useState(false);
  const [pos, setPos] = React.useState('Polica A2');
  const [sheet, setSheet] = React.useState(startOpen);
  const scan = () => {setList((l) => [...l, pool[l.length % pool.length]]);setFlash(true);setTimeout(() => setFlash(false), 380);};
  const it = list[list.length - 1];
  return (
    <div className="cc-screen" style={{
      ...ccVars(t, 'dark'), width: 393, height: 852, borderRadius: 28, overflow: 'hidden',
      background: '#0A0B0B', boxShadow: '0 0 0 8px #CAC4D0',
      display: 'flex', flexDirection: 'column', position: 'relative',
      fontFamily: "'Roboto', sans-serif", color: '#fff'
    }}>
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(120% 80% at 50% 38%, #2A2C2B 0%, #111212 55%, #060707 100%)' }}></div>
      <Halftone color="#fff" opacity={0.06} size={5} />
      <div style={{ position: 'absolute', left: '50%', top: '34%', transform: 'translate(-50%,-50%) rotate(2deg)', width: 158, borderRadius: 8, overflow: 'hidden', boxShadow: '0 20px 50px rgba(0,0,0,0.6)', opacity: 0.92 }}>
        <div style={{ aspectRatio: '3/4', position: 'relative' }}><CoverArt issue={it} height="100%" /></div>
      </div>
      <div style={{ position: 'relative', zIndex: 3, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 16px 0' }}>
        <button onClick={onClose} aria-label="Close" style={{ appearance: 'none', width: 44, height: 44, borderRadius: '50%', background: 'rgba(0,0,0,0.45)', border: 'none', color: '#fff', cursor: onClose ? 'pointer' : 'default', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><IcoX size={20} sw={2.4} /></button>
        <ScanModeToggle mode={mode} setMode={setMode} />
        <div style={{ width: 44 }}></div>
      </div>
      <div style={{ position: 'relative', zIndex: 3, textAlign: 'center', marginTop: 10 }}>
        <span style={{ fontSize: 12.5, fontWeight: 600, color: 'rgba(255,255,255,0.75)', background: 'rgba(0,0,0,0.45)', padding: '5px 12px', borderRadius: 999 }}>Prijem robe · Ilica 45</span>
      </div>
      <div onClick={scan} style={{ position: 'relative', zIndex: 3, flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 24, cursor: 'pointer' }}>
        <div style={{ position: 'relative', width: mode === 'barkod' ? 250 : 204, height: mode === 'barkod' ? 140 : 260, transition: 'width .2s, height .2s' }}>
          {[0, 1, 2, 3].map((i) => {
            const top = i < 2,left = i % 2 === 0;
            const c = flash ? '#3EC63E' : 'var(--accent)';
            return <div key={i} style={{ position: 'absolute', [top ? 'top' : 'bottom']: 0, [left ? 'left' : 'right']: 0, width: 34, height: 34,
              borderTop: top ? '4px solid ' + c : 'none', borderBottom: !top ? '4px solid ' + c : 'none',
              borderLeft: left ? '4px solid ' + c : 'none', borderRight: !left ? '4px solid ' + c : 'none',
              borderTopLeftRadius: top && left ? 10 : 0, borderTopRightRadius: top && !left ? 10 : 0,
              borderBottomLeftRadius: !top && left ? 10 : 0, borderBottomRightRadius: !top && !left ? 10 : 0 }}></div>;
          })}
          {flash ?
          <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#3EC63E' }}><IcoCheck size={50} sw={2.6} /></div> :
          mode === 'barkod' && <div style={{ position: 'absolute', left: 12, right: 12, top: '50%', height: 2.5, background: 'var(--accent)', boxShadow: '0 0 14px 2px var(--accent)', borderRadius: 2 }}></div>}
        </div>
        <span style={{ fontSize: 13.5, color: 'rgba(255,255,255,0.85)' }}>{mode === 'barkod' ? 'Skeniraj barkod — primjerak ide u popis' : 'Slikaj naslovnicu — primjerak ide u popis'}</span>
      </div>
      {/* pozicija + popis skeniranih */}
      <div style={{ position: 'relative', zIndex: 3, margin: '0 16px 0', display: 'flex', flexDirection: 'column', gap: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 14px', borderRadius: 13, background: 'rgba(20,21,20,0.96)', border: '1px solid var(--line)', marginBottom: 10 }} data-comment-anchor="fb31e54ef3-div-324-9">
          <span style={{ color: 'var(--accent)', display: 'flex', flexShrink: 0 }}><EIcoShelf size={18} /></span>
          <span style={{ fontSize: 13, fontWeight: 600 }}>Pozicija: <b>{pos}</b> · Ilica 45</span>
          <button onClick={() => setSheet(true)} style={{ appearance: 'none', cursor: 'pointer', marginLeft: 'auto', flexShrink: 0, background: 'none', border: 'none', color: 'var(--accent)', fontWeight: 700, fontSize: 12.5, fontFamily: "'Roboto', sans-serif" }}>Promijeni</button>
        </div>
      </div>
      <ScanTray count={list.length}
      sub={'zadnji: Tex #' + it.number + ' · inv. 2026-0' + (337 + list.length)}
      buttonWord="ZAPRIMI"
      onAdd={onClose} />
      {sheet && <EPositionSheet t={t} current={pos} onClose={() => setSheet(false)} onPick={(p) => { setPos(p); setSheet(false); }} />}
    </div>);

}

// ── E4 · POSUDBE — članovi i rokovi ─────────────────────────────────────
function EScreenLoans({ t, onNav, onScan, onBack, onNew, onMembers, onReservations }) {
  const [tab, setTab] = React.useState('sve');
  const list = E_LOANS.filter((l) => tab === 'sve' || l.overdue);
  return (
    <EScreen t={t} nav="posudbe" onNav={onNav} onScan={onScan}>
      <EHeader t={t} text="POSUDBE" onBack={onBack} />
      <div style={{ display: 'flex', gap: 7, padding: '6px 16px 12px' }}>
        {[['sve', 'Sve · ' + E_LOANS.length], ['kasni', 'Kasne · ' + E_LOANS.filter((l) => l.overdue).length]].map(([k, lbl]) =>
        <button key={k} onClick={() => setTab(k)} style={{
          appearance: 'none', cursor: 'pointer',
          border: '1px solid ' + (tab === k ? 'var(--accent)' : 'var(--line)'),
          background: tab === k ? 'var(--accent)' : 'transparent',
          color: tab === k ? '#FFF' : 'var(--text2)',
          borderRadius: 999, padding: '7px 14px', fontFamily: "'Roboto', sans-serif", fontWeight: 600, fontSize: 12
        }}>{lbl}</button>
        )}
        <div style={{ flex: 1 }}></div>
        <button onClick={onMembers} style={{ appearance: 'none', cursor: onMembers ? 'pointer' : 'default', border: '1px solid var(--line)', background: 'transparent', color: 'var(--text2)', borderRadius: 999, padding: '7px 12px', fontFamily: "'Roboto', sans-serif", fontWeight: 600, fontSize: 12 }}>Članovi</button>
        <button onClick={onReservations} style={{ appearance: 'none', cursor: onReservations ? 'pointer' : 'default', border: '1px solid var(--line)', background: 'transparent', color: 'var(--text2)', borderRadius: 999, padding: '7px 12px', fontFamily: "'Roboto', sans-serif", fontWeight: 600, fontSize: 12 }}>Rezervacije</button>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '0 16px 24px', display: 'flex', flexDirection: 'column', gap: 9 }}>
        {list.map((l) =>
        <div key={l.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 10, borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', border: l.overdue ? '1px solid rgba(198,41,30,0.5)' : '1px solid transparent' }}>
            <div style={{ width: 42, height: 56, borderRadius: 6, overflow: 'hidden', flexShrink: 0 }}><CoverArt issue={l.iss} height="100%" /></div>
            <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
              <span style={{ fontWeight: 700, fontSize: 14, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>#{l.iss.number} — {l.iss.title}</span>
              <span style={{ fontSize: 12, color: 'var(--text2)' }}>{l.member} · član {l.card}</span>
              <span style={{ fontSize: 12, fontWeight: 700, color: l.overdue ? '#D9514A' : 'var(--muted)' }}>
                {l.overdue ? 'Kasni — rok ' + l.due : 'Rok: ' + l.due}
              </span>
            </div>
            <button style={{ appearance: 'none', cursor: 'pointer', flexShrink: 0, border: '1.5px solid var(--accent)', borderRadius: 999, padding: '7px 12px', background: 'transparent', color: 'var(--accent)', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 11.5 }}>VRAĆENO</button>
          </div>
        )}
      </div>
      <div style={{ padding: '0 16px 16px' }}>
        <RedButton small onClick={onNew} style={{ width: '100%' }}>NOVA POSUDBA — SKENIRAJ ČLANSKU</RedButton>
      </div>
    </EScreen>);

}

Object.assign(window, { EScreenActivate, EScreenDash, EScreenLocations, EScreenReceiving, EScreenLoans, ENavBar, EScreen, E_LOCATIONS });
