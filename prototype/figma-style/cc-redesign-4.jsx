// cc-redesign-4.jsx — zadnje rupe: Prijava, Registracija, CSV uvoz
// (mapiranje stupaca), Sync konflikt dijalog. Ista gramatika (RScreen + FAB).

const { SERIES: R4_SERIES, ISSUES: R4_ISSUES } = window.CC_DATA;

const r4I = (paths) => ({ size = 22, color = 'currentColor', sw = 2, style }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw}
    strokeLinecap="round" strokeLinejoin="round" style={style}>{paths}</svg>
);
const R4IcoMail  = r4I(<g><rect x="3.5" y="5.5" width="17" height="13" rx="2" /><path d="m4.5 7 7.5 6 7.5-6" /></g>);
const R4IcoLock  = r4I(<g><rect x="5.5" y="10.5" width="13" height="9.5" rx="2" /><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5" /></g>);
const R4IcoFile  = r4I(<g><path d="M6 3.5h8L19 8.5v12H6z" /><path d="M14 3.5V9h5" /></g>);
const R4IcoCloud = r4I(<g><path d="M7 18a4.5 4.5 0 0 1-.6-8.96 6 6 0 0 1 11.6 1.6A3.7 3.7 0 0 1 17.5 18z" /></g>);
const R4IcoPhone = r4I(<g><rect x="7" y="3" width="10" height="18" rx="2.5" /><path d="M11 17.5h2" /></g>);

// auth ljuska — tamna, logo gore, sadržaj u kartici
function R4AuthShell({ t, title, sub, onBack, children }) {
  return (
    <div className="cc-screen" style={{
      ...ccVars(t, 'dark'), width: 393, height: 852, borderRadius: 28, overflow: 'hidden',
      background: 'var(--bg)', boxShadow: '0 0 0 8px #CAC4D0',
      display: 'flex', flexDirection: 'column', position: 'relative',
      fontFamily: "'Roboto', sans-serif", color: 'var(--text)',
    }}>
      <GrungeBg />
      <CCStatusBar />
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 0', position: 'relative', zIndex: 2 }}>
        <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 44, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <IcoBack size={22} />
        </button>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '4px 28px 30px', position: 'relative', zIndex: 2, display: 'flex', flexDirection: 'column' }}>
        <div style={{ textAlign: 'center', margin: '10px 0 24px', filter: 'drop-shadow(0 0 14px rgba(198,41,30,0.4))' }}>
          <ComicLogo text={title} size={34} font={t.font} />
          {sub && <p style={{ margin: '10px 0 0', fontSize: 14, color: 'var(--text2)', lineHeight: 1.55 }}>{sub}</p>}
        </div>
        {children}
      </div>
    </div>
  );
}

function R4Input({ Ico, value, onChange, placeholder, type = 'text' }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '13px 15px', borderRadius: 13, background: 'var(--surface)', border: '1px solid var(--line)' }}>
      <span style={{ color: 'var(--muted)', display: 'flex', flexShrink: 0 }}><Ico size={19} /></span>
      <input type={type} value={value} onChange={e => onChange && onChange(e.target.value)} placeholder={placeholder} style={{
        flex: 1, minWidth: 0, background: 'none', border: 'none', outline: 'none',
        fontFamily: "'Roboto', sans-serif", fontSize: 14.5, color: 'var(--text)',
      }} />
    </div>
  );
}

// ── R23 · PRIJAVA ───────────────────────────────────────────────────────
function RScreenLoginR({ t, onBack, onLogin, onRegister }) {
  const [email, setEmail] = React.useState('');
  const [pass, setPass] = React.useState('');
  return (
    <R4AuthShell t={t} title="PRIJAVA" sub="Račun čuva kolekciju na serveru — telefon, tablet i web uvijek isto." onBack={onBack}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        <R4Input Ico={R4IcoMail} value={email} onChange={setEmail} placeholder="E-mail" type="email" />
        <R4Input Ico={R4IcoLock} value={pass} onChange={setPass} placeholder="Lozinka" type="password" />
        <button style={{ appearance: 'none', background: 'none', border: 'none', cursor: 'pointer', alignSelf: 'flex-end', color: 'var(--text2)', fontSize: 12.5, fontWeight: 600, fontFamily: "'Roboto', sans-serif", padding: 0 }}>Zaboravljena lozinka?</button>
        <RedButton onClick={onLogin} style={{ width: '100%', marginTop: 6 }}>PRIJAVI SE</RedButton>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, margin: '22px 0' }}>
        <div style={{ flex: 1, height: 1, background: 'var(--line)' }}></div>
        <span style={{ fontSize: 12, color: 'var(--muted)', fontWeight: 600 }}>ILI</span>
        <div style={{ flex: 1, height: 1, background: 'var(--line)' }}></div>
      </div>
      <button onClick={onRegister} style={{ appearance: 'none', cursor: onRegister ? 'pointer' : 'default', width: '100%', border: '1.5px solid var(--accent)', borderRadius: 999, padding: '13px 8px', background: 'transparent', color: 'var(--accent)', fontFamily: "'Roboto', sans-serif", fontWeight: 800, fontSize: 14, letterSpacing: '0.04em' }}>NAPRAVI NOVI RAČUN</button>
      <div style={{ marginTop: 'auto', paddingTop: 24, display: 'flex', justifyContent: 'center' }}>
        <SyncChip state="ok" />
      </div>
    </R4AuthShell>
  );
}

// ── R24 · REGISTRACIJA ──────────────────────────────────────────────────
function RScreenRegisterR({ t, onBack, onDone }) {
  const [name, setName] = React.useState('');
  const [email, setEmail] = React.useState('');
  const [pass, setPass] = React.useState('');
  return (
    <R4AuthShell t={t} title="NOVI RAČUN" sub="Besplatno. Kolekcija se sprema lokalno i sinkronizira sama." onBack={onBack}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        <R4Input Ico={R4IcoPhone} value={name} onChange={setName} placeholder="Nadimak (npr. Kolekcionar)" />
        <R4Input Ico={R4IcoMail} value={email} onChange={setEmail} placeholder="E-mail" type="email" />
        <R4Input Ico={R4IcoLock} value={pass} onChange={setPass} placeholder="Lozinka (min. 8 znakova)" type="password" />
        <RedButton onClick={onDone} style={{ width: '100%', marginTop: 6 }}>REGISTRIRAJ SE</RedButton>
        <p style={{ margin: '4px 0 0', fontSize: 12, color: 'var(--muted)', textAlign: 'center', lineHeight: 1.6 }}>
          Registracijom prihvaćaš uvjete korištenja.<br />Bez računa sve i dalje radi — samo bez sinkronizacije.
        </p>
      </div>
    </R4AuthShell>
  );
}

// ── R25 · CSV UVOZ — mapiranje stupaca ─────────────────────────────────
const R4_MAP_ROWS = [
  { csv: 'serijal',  field: 'Serijal',  ok: true },
  { csv: 'edicija',  field: 'Edicija',  ok: true },
  { csv: 'broj',     field: 'Broj',     ok: true },
  { csv: 'naslov',   field: 'Naslov',   ok: true },
  { csv: 'stanje',   field: 'Stanje (M/VF/F/G/P)', ok: true },
  { csv: 'cijena',   field: '— preskoči —', ok: false },
];

function RScreenImportR({ t, onNav, onAdd, onBack, onDone }) {
  const [step, setStep] = React.useState(0); // 0 = mapiranje, 1 = gotovo
  return (
    <RScreen t={t} nav="polica" onNav={onNav} onAdd={onAdd}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 2px' }}>
        <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 44, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><IcoBack size={22} /></button>
        <div style={{ flex: 1, textAlign: 'center', paddingRight: 44 }}><ComicLogo text="UVOZ IZ CSV" size={24} font={t.font} /></div>
      </div>
      {step === 0 ? (
        <React.Fragment>
          <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '6px 16px 16px', display: 'flex', flexDirection: 'column', gap: 14 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 13, borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)' }}>
              <div style={{ width: 42, height: 42, borderRadius: 11, background: 'var(--deep)', color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}><R4IcoFile size={21} /></div>
              <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                <span style={{ fontWeight: 700, fontSize: 14, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>stara-kolekcija.csv</span>
                <span style={{ fontSize: 12, color: 'var(--text2)' }}>128 redaka · 6 stupaca</span>
              </div>
              <button style={{ appearance: 'none', cursor: 'pointer', background: 'none', border: 'none', color: 'var(--accent)', fontSize: 12.5, fontWeight: 700, fontFamily: "'Roboto', sans-serif", flexShrink: 0 }}>Promijeni</button>
            </div>
            <div>
              <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.1em', textTransform: 'uppercase', fontWeight: 700 }}>Mapiranje stupaca</span>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 7, marginTop: 10 }}>
                {R4_MAP_ROWS.map(r => (
                  <div key={r.csv} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 13px', borderRadius: 12, background: 'var(--surface)', border: '1px solid var(--line)' }}>
                    <code style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 12, color: 'var(--text2)', width: 74, flexShrink: 0 }}>{r.csv}</code>
                    <IcoPlay size={12} color="var(--muted)" style={{ flexShrink: 0 }} />
                    <span style={{ flex: 1, minWidth: 0, fontSize: 13.5, fontWeight: 600, color: r.ok ? 'var(--text)' : 'var(--muted)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.field}</span>
                    {r.ok
                      ? <span style={{ color: '#3EC63E', display: 'flex', flexShrink: 0 }}><IcoCheck size={15} sw={3} /></span>
                      : <span style={{ color: 'var(--muted)', display: 'flex', flexShrink: 0 }}><IcoX size={13} sw={2.6} /></span>}
                  </div>
                ))}
              </div>
            </div>
            <p style={{ margin: 0, fontSize: 12, color: 'var(--muted)', lineHeight: 1.6 }}>
              Duplikati se preskaču automatski. Nakon uvoza sve se sinkronizira na server.
            </p>
          </div>
          <div style={{ padding: '0 16px 16px' }}>
            <RedButton onClick={() => setStep(1)} style={{ width: '100%' }}>UVEZI 128 REDAKA</RedButton>
          </div>
        </React.Fragment>
      ) : (
        <div style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center', padding: '0 40px 30px', gap: 16 }}>
          <div style={{ width: 96, height: 96, borderRadius: '50%', background: 'rgba(46,158,46,0.14)', border: '2px solid #2E9E2E', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#3EC63E' }}>
            <IcoCheck size={44} sw={2.6} />
          </div>
          <div>
            <h2 style={{ margin: 0, fontSize: 21, fontWeight: 800 }}>Uvezeno 126 stripova</h2>
            <p style={{ margin: '8px 0 0', fontSize: 13.5, color: 'var(--text2)', lineHeight: 1.6 }}>2 retka preskočena (duplikati).<br />Sinkronizacija sa serverom u tijeku…</p>
          </div>
          <RedButton onClick={onDone} style={{ marginTop: 6 }}>POGLEDAJ POLICU</RedButton>
        </div>
      )}
    </RScreen>
  );
}

// ── R26 · SYNC KONFLIKT ─────────────────────────────────────────────────
function RScreenConflictR({ t, onKeepLocal, onKeepServer }) {
  const it = R4_ISSUES[24];
  const side = (label, sub, grade, onPick) => (
    <div onClick={onPick} style={{ flex: 1, padding: '12px 12px 14px', borderRadius: 13, border: '1.5px solid var(--line)', background: 'var(--deep)', cursor: onPick ? 'pointer' : 'default', display: 'flex', flexDirection: 'column', gap: 6, textAlign: 'center' }}>
      <span style={{ fontSize: 11.5, color: 'var(--muted)', letterSpacing: '0.08em', textTransform: 'uppercase', fontWeight: 700 }}>{label}</span>
      <span style={{ fontSize: 22, fontWeight: 800, color: 'var(--accent)' }}>{grade}</span>
      <span style={{ fontSize: 12, color: 'var(--text2)' }}>{sub}</span>
    </div>
  );
  return (
    <div style={{ position: 'relative', width: 393, height: 852 }}>
      <div style={{ position: 'absolute', inset: 0, isolation: 'isolate' }}><RScreenSettingsR t={t} setTweak={() => {}} /></div>
      <div style={{ position: 'absolute', inset: 0, zIndex: 10, borderRadius: 28, overflow: 'hidden', background: 'rgba(6,8,8,0.65)', backdropFilter: 'blur(2px)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
        <div style={{ width: '100%', borderRadius: 20, background: 'var(--surface)', ...ccVars(t), padding: '18px 18px 16px', boxShadow: '0 20px 60px rgba(0,0,0,0.7)', fontFamily: "'Roboto', sans-serif", color: 'var(--text)', display: 'flex', flexDirection: 'column', gap: 13 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{ color: '#E8C547', display: 'flex' }}><R4IcoCloud size={22} /></span>
            <span style={{ fontWeight: 800, fontSize: 16, letterSpacing: '0.02em' }}>Sukob sinkronizacije</span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 11, padding: 10, borderRadius: 12, background: 'var(--deep)' }}>
            <div style={{ width: 38, height: 50, borderRadius: 6, overflow: 'hidden', flexShrink: 0 }}><CoverArt issue={it} height="100%" /></div>
            <div style={{ minWidth: 0 }}>
              <div style={{ fontSize: 13.5, fontWeight: 700 }}>#{it.number} — {it.title}</div>
              <div style={{ fontSize: 12, color: 'var(--text2)', marginTop: 2 }}>Stanje promijenjeno na 2 mjesta</div>
            </div>
          </div>
          <div style={{ display: 'flex', gap: 9 }}>
            {side('Na telefonu', 'danas 9:12', 'VF', onKeepLocal)}
            {side('Na serveru', 'jučer 21:40', 'F', onKeepServer)}
          </div>
          <p style={{ margin: 0, fontSize: 11.5, color: 'var(--muted)', textAlign: 'center' }}>Dodirni verziju koju želiš zadržati — druga se prepisuje.</p>
        </div>
      </div>
    </div>
  );
}

// ── R30 · ODABIR NAČINA — osobno ili enterprise ─────────────────────
function RScreenModePick({ t, onBack, onPersonal, onEnterprise }) {
  const card = (label, sub, Ico, onClick, primary) => (
    <div onClick={onClick} style={{
      display: 'flex', flexDirection: 'column', gap: 10, padding: '20px 18px', borderRadius: 18, cursor: onClick ? 'pointer' : 'default',
      background: primary ? 'linear-gradient(180deg, color-mix(in oklab, var(--accent) 70%, #fff) 0%, var(--accent) 40%, var(--accent-deep) 100%)' : 'var(--surface)',
      border: primary ? 'none' : '1px solid var(--line)',
      boxShadow: primary ? '0 10px 26px rgba(0,0,0,0.5)' : 'var(--card-shadow)',
    }}>
      <div style={{ width: 48, height: 48, borderRadius: 14, display: 'flex', alignItems: 'center', justifyContent: 'center', background: primary ? 'rgba(255,255,255,0.18)' : 'var(--deep)', color: primary ? '#fff' : 'var(--accent)' }}>
        <Ico size={26} />
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        <span style={{ fontWeight: 800, fontSize: 17, letterSpacing: '0.02em', color: primary ? '#fff' : 'var(--text)' }}>{label}</span>
        <span style={{ fontSize: 12.5, lineHeight: 1.55, color: primary ? 'rgba(255,255,255,0.88)' : 'var(--text2)' }}>{sub}</span>
      </div>
      <span style={{ marginTop: 2, fontSize: 12.5, fontWeight: 800, letterSpacing: '0.04em', color: primary ? '#fff' : 'var(--accent)', display: 'inline-flex', alignItems: 'center', gap: 6 }}>NASTAVI <IcoPlay size={12} color={primary ? '#fff' : 'var(--accent)'} /></span>
    </div>
  );
  const IcoPersonal = r4I(<g><path d="M12 6.2C10 4.3 6.5 4.5 5 6.8c-1.6 2.4-.6 5.4 2 7.6l5 4.1 5-4.1c2.6-2.2 3.6-5.2 2-7.6-1.5-2.3-5-2.5-7-.6z" /></g>);
  const IcoBiz = r4I(<g><rect x="3.5" y="8" width="17" height="12.5" rx="2" /><path d="M9 8V6a1.5 1.5 0 0 1 1.5-1.5h3A1.5 1.5 0 0 1 15 6v2M3.5 12.5h17M12 11v3" /></g>);
  return (
    <R4AuthShell t={t} title="TKO SI?" sub="Odaberi način rada — možeš ga promijeniti odjavom." onBack={onBack}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        {card('Osobna kolekcija', 'Tvoja polica — skeniranje, čitanje, tražim, zamjene i sinkronizacija na svim uređajima.', IcoPersonal, onPersonal, true)}
        {card('Enterprise — poslovnica', 'Za knjižnice i strip dućane. Aktivacija preko ugovora, inventar po pozicijama, posudbe članova.', IcoBiz, onEnterprise)}
      </div>
      <p style={{ margin: '18px 0 0', fontSize: 12, color: 'var(--muted)', textAlign: 'center', lineHeight: 1.6 }}>Enterprise pristup zahtijeva broj ugovora i aktivacijski kod.</p>
    </R4AuthShell>
  );
}

Object.assign(window, { RScreenLoginR, RScreenRegisterR, RScreenImportR, RScreenConflictR, RScreenModePick });
