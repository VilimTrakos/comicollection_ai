// cc-screens-redesign.jsx — REDIZAJN prijedlozi (usporedi s postojećim ekranima)
// R1 Home kao dashboard + FAB nav, R2 Polica s FAB navom, R3 kompaktna lista
// s A–Z scrollerom, R4 potvrda s ocjenama stanja (M/VF/F/G/P), R5 ručni unos
// s ocjenama, R6 brzo skeniranje sa snackbarom.
// Promjene: Dodaj (+) kao centralni FAB; Home = dashboard, Polica = kolekcija;
// stanje kao grade chipovi umjesto zvjezdica; min. tekst 12px; sync indikator.

const { SERIES: R_SERIES, ISSUES: R_ISSUES, FEATURED: R_FEAT, UNREAD: R_UNREAD } = window.CC_DATA;

// ── icons ───────────────────────────────────────────────────────────────
const rI = (paths) => ({ size = 22, color = 'currentColor', sw = 2, style }) =>
<svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw}
strokeLinecap="round" strokeLinejoin="round" style={style}>{paths}</svg>;

const RIcoPlus = rI(<path d="M12 5v14M5 12h14" />);
const RIcoBell = rI(<g><path d="M6 9a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6z" /><path d="M10 20a2 2 0 0 0 4 0" /></g>);
const RIcoCloud = rI(<g><path d="M7 18a4.5 4.5 0 0 1-.6-8.96 6 6 0 0 1 11.6 1.6A3.7 3.7 0 0 1 17.5 18z" /><path d="m9.5 13.5 2 2 3.5-3.5" /></g>);
const RIcoCam = rI(<g><path d="M3 8.5a2 2 0 0 1 2-2h2l1.4-2h7.2L17 6.5h2a2 2 0 0 1 2 2V18a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" /><circle cx="12" cy="13" r="3.6" /></g>);

// ── grade chips (M/VF/F/G/P) — replaces star-based condition ────────────
const R_GRADES = [
{ g: 'M', hr: 'Novo' }, { g: 'VF', hr: 'Vrlo dobro' }, { g: 'F', hr: 'Dobro' },
{ g: 'G', hr: 'Solidno' }, { g: 'P', hr: 'Loše' }];

function GradeChips({ value, onChange }) {
  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: 7 }}>
      {R_GRADES.map(({ g, hr }) => {
        const on = value === g;
        return (
          <button key={g} onClick={onChange && (() => onChange(g))} style={{
            appearance: 'none', cursor: onChange ? 'pointer' : 'default',
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3,
            padding: '10px 2px 8px', borderRadius: 12,
            border: on ? '1.5px solid var(--accent)' : '1px solid var(--line)',
            background: on ? 'color-mix(in oklab, var(--accent) 22%, var(--surface))' : 'var(--surface)',
            color: 'var(--text)', fontFamily: "'Roboto', sans-serif"
          }}>
            <span style={{ fontSize: 17, fontWeight: 800, color: on ? 'var(--accent)' : 'var(--text)' }}>{g}</span>
            <span style={{ fontSize: 10.5, color: on ? 'var(--text)' : 'var(--muted)', fontWeight: 600 }}>{hr}</span>
          </button>);

      })}
    </div>);

}

// ── redesigned nav: 5 slots with center FAB ─────────────────────────────
function RNavBar({ active = 'home', onNav, onAdd }) {
  const side = (id, Ico, label) =>
  <button key={id} aria-label={label} onClick={onNav ? () => onNav(id) : undefined} style={{
    appearance: 'none', background: 'none', border: 'none', cursor: onNav ? 'pointer' : 'default',
    height: 52, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 3,
    color: active === id ? 'var(--accent)' : 'var(--muted)'
  }}>
      <Ico size={24} sw={active === id ? 2.4 : 2} />
      <span style={{ fontSize: 10.5, fontWeight: active === id ? 700 : 500, fontFamily: "'Roboto', sans-serif" }}>{label}</span>
    </button>;

  return (
    <div style={{ position: 'relative', flexShrink: 0, zIndex: 5 }}>
      {/* FAB */}
      <button onClick={onAdd} aria-label="Dodaj strip" style={{
        appearance: 'none', cursor: onAdd ? 'pointer' : 'default',
        position: 'absolute', left: '50%', top: -26, transform: 'translateX(-50%)',
        width: 58, height: 58, borderRadius: '50%', border: '4px solid var(--bg)',
        background: 'linear-gradient(180deg, color-mix(in oklab, var(--accent) 78%, #fff) 0%, var(--accent) 38%, var(--accent-deep) 100%)',
        color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center',
        boxShadow: '0 6px 18px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.4)'
      }}>
        <RIcoPlus size={26} sw={2.6} />
      </button>
      <div style={{
        height: 68, background: 'var(--nav)', borderTop: '1px solid var(--line)',
        display: 'grid', gridTemplateColumns: '1fr 1fr 74px 1fr 1fr',
        alignItems: 'center', justifyItems: 'center'
      }}>
        {side('home', IcoHome, 'Home')}
        {side('polica', IcoBook, 'Polica')}
        <div></div>
        {side('search', IcoSearch, 'Traži')}
        {side('settings', IcoGear, 'Postavke')}
      </div>
    </div>);

}

// Screen shell variant using the FAB nav
function RScreen({ children, t, nav, onNav, onAdd, grunge = false }) {
  return (
    <div className="cc-screen" style={{
      ...ccVars(t), width: 393, height: 852, borderRadius: 28, overflow: 'hidden',
      background: 'var(--bg)', boxShadow: '0 0 0 8px #CAC4D0',
      display: 'flex', flexDirection: 'column', position: 'relative',
      fontFamily: "'Roboto', sans-serif", color: 'var(--text)'
    }}>
      {grunge && <GrungeBg />}
      <CCStatusBar />
      <div style={{ flex: 1, minHeight: 0, position: 'relative', display: 'flex', flexDirection: 'column' }}>
        {children}
      </div>
      <RNavBar active={nav} onNav={onNav} onAdd={onAdd} />
    </div>);

}

// sync status chip (lokalna pohrana + stalna sinkronizacija)
function SyncChip({ state = 'ok' }) {
  const ok = state === 'ok';
  return (
    <div title={ok ? 'Sinkronizirano sa serverom' : 'Offline — promjene spremljene lokalno'} style={{
      display: 'inline-flex', alignItems: 'center', gap: 6, padding: '5px 11px', borderRadius: 999,
      background: ok ? 'rgba(62,198,62,0.13)' : 'rgba(232,197,71,0.13)',
      border: '1px solid ' + (ok ? 'rgba(62,198,62,0.45)' : 'rgba(232,197,71,0.5)'),
      color: ok ? '#3EC63E' : '#E8C547', fontSize: 12, fontWeight: 700
    }}>
      <RIcoCloud size={15} sw={2.2} /> {ok ? 'Sinkronizirano' : 'Offline'}
    </div>);

}

function RSectionHead({ label, action, onAction }) {
  return (
    <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 10 }}>
      <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.1em', textTransform: 'uppercase', fontWeight: 700 }}>{label}</span>
      {action && <span onClick={onAction} style={{ fontSize: 12.5, color: 'var(--accent)', fontWeight: 700, cursor: 'pointer' }}>{action} →</span>}
    </div>);

}

// ── R1 · HOME AS DASHBOARD ──────────────────────────────────────────────
function RScreenHome({ t, onNav, onAdd, onOpenReleases, onOpenReading, onOpenTrazim, onOpenSeries }) {
  const releases = [
  { d: '28', m: 'lip', s: 'DYLAN DOG', n: 87, iss: R_ISSUES[2] },
  { d: '05', m: 'srp', s: 'TEX', n: 121, iss: R_ISSUES[7] },
  { d: '12', m: 'srp', s: 'ZAGOR', n: 97, iss: R_ISSUES[12] }];

  const closest = [...R_SERIES].sort((a, b) => b.owned / b.total - a.owned / a.total).filter((s) => s.owned < s.total).slice(0, 2);
  const reading = R_UNREAD[0] || R_ISSUES[3];
  const totalOwned = R_SERIES.reduce((n, s) => n + s.owned, 0);
  return (
    <RScreen t={t} nav="home" onNav={onNav} onAdd={onAdd} grunge={true}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 20px 4px', position: 'relative', zIndex: 2 }}>
        <div>
          <ComicLogo text="COMICS COLLECTION" size={22} font={t.font} />
          <div style={{ fontSize: 13, color: 'var(--text2)', marginTop: 3 }}>{totalOwned} stripova · ~412 €</div>
        </div>
        <SyncChip state="ok" />
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '10px 20px 24px', position: 'relative', zIndex: 2, display: 'flex', flexDirection: 'column', gap: 20 }}>
        {/* U najavi */}
        <div>
          <RSectionHead label="U najavi" action="Sve" onAction={onOpenReleases} />
          <div style={{ display: 'flex', gap: 10 }}>
            {releases.map((r, i) =>
            <div key={i} onClick={onOpenReleases} style={{ flex: 1, borderRadius: 14, overflow: 'hidden', background: 'var(--surface)', boxShadow: 'var(--card-shadow)', cursor: onOpenReleases ? 'pointer' : 'default' }}>
                <div style={{ aspectRatio: '3/3.6', position: 'relative' }}>
                  <CoverArt issue={r.iss} height="100%" />
                  <div style={{ position: 'absolute', top: 6, left: 6, borderRadius: 8, background: 'rgba(6,8,8,0.85)', padding: '4px 8px', textAlign: 'center', lineHeight: 1.1 }}>
                    <div style={{ fontSize: 14, fontWeight: 800, color: 'var(--accent)' }}>{r.d}</div>
                    <div style={{ fontSize: 9.5, color: '#B7A88F', textTransform: 'uppercase' }}>{r.m}</div>
                  </div>
                </div>
                <div style={{ padding: '7px 9px 9px' }}>
                  <div style={{ fontSize: 12, fontWeight: 700, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.s} #{r.n}</div>
                </div>
              </div>
            )}
          </div>
        </div>
        {/* Nastavi čitati */}
        <div>
          <RSectionHead label="Nastavi čitati" />
          <div onClick={onOpenReading} style={{ display: 'flex', alignItems: 'center', gap: 13, padding: 11, borderRadius: 16, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', cursor: onOpenReading ? 'pointer' : 'default' }}>
            <div style={{ width: 54, height: 72, borderRadius: 8, overflow: 'hidden', flexShrink: 0 }}><CoverArt issue={reading} height="100%" /></div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 15, fontWeight: 700 }}>#{reading.number} — {reading.title}</div>
              <div style={{ fontSize: 12.5, color: 'var(--text2)', marginTop: 3 }}>Dylan Dog · nepročitano</div>
            </div>
            <RedButton small onClick={onOpenReading}>ČITAJ</RedButton>
          </div>
        </div>
        {/* Tražim — najbliže kompletiranju */}
        <div>
          <RSectionHead label="Najbliže kompletiranju" action="Tražim" onAction={onOpenTrazim} />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
            {closest.map((s) => {
              const pct = Math.round(s.owned / s.total * 100);
              return (
                <div key={s.id} onClick={onOpenSeries && (() => onOpenSeries(s))} style={{ display: 'flex', alignItems: 'center', gap: 13, padding: 11, borderRadius: 16, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', cursor: onOpenSeries ? 'pointer' : 'default' }}>
                  <div style={{ width: 46, height: 62, borderRadius: 7, overflow: 'hidden', flexShrink: 0 }}><CoverArt series={s} height="100%" /></div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                      <span style={{ fontSize: 14.5, fontWeight: 700 }}>{s.name}</span>
                      <span style={{ fontSize: 12.5, color: 'var(--text2)', fontWeight: 600 }}>{s.owned}/{s.total}</span>
                    </div>
                    <div style={{ marginTop: 8, height: 7, borderRadius: 999, background: 'var(--deep)', overflow: 'hidden' }}>
                      <div style={{ width: pct + '%', height: '100%', borderRadius: 999, background: 'linear-gradient(90deg, var(--accent-deep), var(--accent))' }}></div>
                    </div>
                    <div style={{ marginTop: 5, fontSize: 11.5, color: 'var(--muted)' }}>još {s.total - s.owned} do kompleta</div>
                  </div>
                </div>);

            })}
          </div>
        </div>
      </div>
    </RScreen>);

}

// ── R2 · POLICA (shelf, old Home) with FAB nav ─────────────────────────
function RScreenShelf({ t, onNav, onAdd, onOpenSeries, onHub }) {
  const hubChips = onHub && [
  ['hub', 'Kolekcija ▦'], ['stats', 'Statistika'], ['unread', 'Nije čitano'], ['trazim', 'Tražim'],
  ['dupli', 'Dupli'], ['posudeno', 'Posuđeno'], ['releases', 'U najavi'], ['export', 'CSV']];

  return (
    <RScreen t={t} nav="polica" onNav={onNav} onAdd={onAdd}>
      <div style={{ padding: '12px 20px 10px', textAlign: 'center' }}>
        <ComicLogo text="MOJA POLICA" size={26} font={t.font} />
      </div>
      {hubChips &&
      <div style={{ display: 'flex', gap: 7, padding: '0 20px 12px', overflowX: 'auto' }}>
          {hubChips.map(([id, label]) =>
        <button key={id} onClick={() => onHub(id)} style={{ appearance: 'none', cursor: 'pointer', flexShrink: 0, border: '1px solid var(--line)', borderRadius: 999, padding: '7px 13px', background: 'var(--surface)', color: 'var(--text2)', fontFamily: "'Roboto', sans-serif", fontWeight: 600, fontSize: 12 }}>{label}</button>
        )}
        </div>
      }
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '2px 20px 24px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>
          {R_SERIES.map((s) => <CCSeriesCard key={s.id} s={s} t={t} onClick={onOpenSeries && (() => onOpenSeries(s))} />)}
        </div>
      </div>
    </RScreen>);

}

// ── R3 · COMPACT LIST + A–Z FAST SCROLLER ──────────────────────────────
function RScreenCompact({ t, onNav, onAdd, startDense = true, title = 'DYLAN DOG · EXTRA', st, onBack, onOpenIssue }) {
  const [dense, setDense] = React.useState(startDense);
  const store = st ? st : null;
  const rows = [...R_ISSUES].slice(0, 30).map((it) => store ? store.getIssue(it) : it);
  const letters = ['#', 'A', 'D', 'K', 'M', 'N', 'O', 'P', 'S', 'T', 'V', 'Z'];
  return (
    <RScreen t={t} nav="polica" onNav={onNav} onAdd={onAdd}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 20px 8px', gap: 8 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 2, minWidth: 0 }}>
          {onBack &&
          <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text2)', width: 34, height: 34, marginLeft: -8, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}><IcoBack size={20} /></button>
          }
          <ComicLogo text={title} size={20} font={t.font} />
        </div>
        <div style={{ display: 'flex', borderRadius: 999, border: '1px solid var(--line)', overflow: 'hidden' }}>
          {[['comfy', 'Udobno'], ['dense', 'Zbito']].map(([k, lbl]) =>
          <button key={k} onClick={() => setDense(k === 'dense')} style={{
            appearance: 'none', border: 'none', cursor: 'pointer', padding: '6px 13px',
            fontSize: 12, fontWeight: 700, fontFamily: "'Roboto', sans-serif",
            background: k === 'dense' === dense ? 'var(--accent)' : 'transparent',
            color: k === 'dense' === dense ? '#fff' : 'var(--text2)'
          }}>{lbl}</button>
          )}
        </div>
      </div>
      <div style={{ flex: 1, minHeight: 0, position: 'relative' }}>
        <div style={{ position: 'absolute', inset: 0, overflowY: 'auto', padding: '2px 34px 20px 20px', display: 'flex', flexDirection: 'column', gap: dense ? 4 : 10 }}>
          {rows.map((it) => dense ?
          <div key={it.id} onClick={onOpenIssue && (() => onOpenIssue(it))} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '7px 10px', borderRadius: 10, background: 'var(--surface)', cursor: onOpenIssue ? 'pointer' : 'default' }}>
              <span style={{ width: 34, fontSize: 13, fontWeight: 800, color: 'var(--accent)', flexShrink: 0 }}>#{it.number}</span>
              <span style={{ flex: 1, minWidth: 0, fontSize: 13.5, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{it.title}</span>
              <span style={{ fontSize: 11.5, color: 'var(--muted)', flexShrink: 0 }}>{it.year}</span>
              <div style={{ display: 'flex', gap: 4, flexShrink: 0 }}>
                <div style={{ width: 17, height: 17, borderRadius: 5, background: it.read ? '#2E9E2E' : '#A91A1A', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff' }}><IcoEye size={11} sw={2.6} /></div>
                <div style={{ width: 17, height: 17, borderRadius: 5, background: it.owned ? '#2E9E2E' : '#A91A1A', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff' }}>{it.owned ? <IcoCheck size={10} sw={3.4} /> : <IcoX size={10} sw={3.4} />}</div>
              </div>
            </div> :

          <div key={it.id} onClick={onOpenIssue && (() => onOpenIssue(it))} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 9, borderRadius: 13, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', cursor: onOpenIssue ? 'pointer' : 'default' }}>
              <div style={{ width: 42, height: 56, borderRadius: 6, overflow: 'hidden', flexShrink: 0 }}><CoverArt issue={it} height="100%" /></div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 14, fontWeight: 700, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>#{it.number} — {it.title}</div>
                <div style={{ fontSize: 12, color: 'var(--text2)', marginTop: 2 }}>{it.year}</div>
              </div>
              <div style={{ display: 'flex', gap: 5, flexShrink: 0 }}>
                <div style={{ width: 22, height: 22, borderRadius: 6, background: it.read ? '#2E9E2E' : '#A91A1A', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff' }}><IcoEye size={13} sw={2.4} /></div>
                <div style={{ width: 22, height: 22, borderRadius: 6, background: it.owned ? '#2E9E2E' : '#A91A1A', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff' }}>{it.owned ? <IcoCheck size={12} sw={3} /> : <IcoX size={12} sw={3} />}</div>
              </div>
            </div>
          )}
        </div>
        {/* A–Z fast scroller */}
        <div style={{ position: 'absolute', right: 6, top: '50%', transform: 'translateY(-50%)', display: 'flex', flexDirection: 'column', gap: 3, alignItems: 'center', padding: '8px 4px', borderRadius: 999, background: 'var(--deep)' }}>
          {letters.map((l, i) =>
          <span key={l} style={{ fontSize: 9.5, fontWeight: 700, color: i === 2 ? 'var(--accent)' : 'var(--muted)', lineHeight: 1.4 }}>{l}</span>
          )}
        </div>
      </div>
    </RScreen>);

}

// ── R4 · SCAN CONFIRM with grade chips ──────────────────────────────────
function RScreenConfirm({ t, onNav, onAdd, onBack, onSave }) {
  const it = R_ISSUES[24];
  const [grade, setGrade] = React.useState('VF');
  return (
    <RScreen t={t} nav="home" onNav={onNav} onAdd={onAdd} grunge={true}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 2px', position: 'relative', zIndex: 2 }}>
        <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 44, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><IcoBack size={22} /></button>
        <div style={{ flex: 1, textAlign: 'center', paddingRight: 44 }}><ComicLogo text="PRONAĐENO" size={26} font={t.font} /></div>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '6px 24px 20px', position: 'relative', zIndex: 2 }}>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 7, padding: '6px 12px', borderRadius: 999, background: 'rgba(62,198,62,0.14)', border: '1px solid rgba(62,198,62,0.5)', color: '#3EC63E', fontSize: 12.5, fontWeight: 700, marginBottom: 14 }}>
          <IcoCheck size={14} sw={3} /> Barkod prepoznat · 8050024 25
        </div>
        <div style={{ display: 'flex', gap: 14 }}>
          <div style={{ width: 110, flexShrink: 0, borderRadius: 10, overflow: 'hidden', boxShadow: '0 10px 26px rgba(0,0,0,0.5)' }}>
            <div style={{ aspectRatio: '3/4', position: 'relative' }}><CoverArt issue={it} height="100%" /></div>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <h2 style={{ margin: 0, fontSize: 19, fontWeight: 800, letterSpacing: '0.02em' }}>Dylan Dog EXTRA</h2>
            <p style={{ margin: '4px 0 0', fontSize: 15.5 }}>#{it.number} — {it.title}</p>
            <div style={{ marginTop: 10, fontSize: 13.5, color: 'var(--text2)', lineHeight: 1.7 }}>
              <div>Ludens · {it.year}</div>
              <div>Sclavi &amp; Stano</div>
              <div style={{ marginTop: 4, color: 'var(--text)' }}>Procjena: <b>~{it.value || 6} €</b></div>
            </div>
          </div>
        </div>
        <div style={{ marginTop: 20 }}>
          <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.08em', textTransform: 'uppercase', fontWeight: 700 }}>Stanje primjerka</span>
          <div style={{ marginTop: 10 }}><GradeChips value={grade} onChange={setGrade} /></div>
          <p style={{ margin: '10px 0 0', fontSize: 12.5, color: 'var(--muted)', lineHeight: 1.5 }}>
            M = kao novo · VF = manji tragovi · F = vidljivo korišten · G = oštećen · P = jako oštećen
          </p>
        </div>
      </div>
      <div style={{ position: 'relative', zIndex: 2, padding: '0 16px 16px', display: 'flex', gap: 10 }}>
        <button onClick={onBack} style={{ appearance: 'none', cursor: onBack ? 'pointer' : 'default', flex: 1, border: '1.5px solid var(--line)', borderRadius: 999, padding: '13px 8px', background: 'transparent', color: 'var(--text2)', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 13.5 }}>Pogrešan strip → traži ručno</button>
        <RedButton onClick={onSave} style={{ flex: 2 }}>DODAJ U KOLEKCIJU</RedButton>
      </div>
    </RScreen>);

}

// ── R5 · MANUAL ADD with grade chips + larger type ─────────────────────
function RScreenManual({ t, onNav, onAdd, onBack, onSave }) {
  const [series, setSeries] = React.useState('DYLAN DOG');
  const sObj = R_SERIES.find((s) => s.name === series) || R_SERIES[0];
  const editions = sObj.editions.map((e) => e.name);
  const [edition, setEdition] = React.useState(editions[0]);
  // auto-fill: next missing number in the chosen edition + its publish year
  const [num, setNum] = React.useState('26');
  const [year, setYear] = React.useState('1999');
  const [price, setPrice] = React.useState('');
  const [grade, setGrade] = React.useState('VF');
  const [read, setRead] = React.useState(false);
  React.useEffect(() => {setEdition(editions[0]);}, [series]);
  return (
    <RScreen t={t} nav="home" onNav={onNav} onAdd={onAdd}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 2px' }}>
        <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 44, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><IcoBack size={22} /></button>
        <div style={{ flex: 1, textAlign: 'center', paddingRight: 44 }}><ComicLogo text="RUČNI UNOS" size={24} font={t.font} /></div>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '8px 16px 16px', display: 'flex', flexDirection: 'column', gap: 15 }} data-comment-anchor="8061837bbc-div-365-7">
        {/* pregled na vrhu — vidi se uz koji broj se vežu podaci ispod */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 10, borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)' }}>
          <div style={{ width: 46, height: 62, borderRadius: 7, overflow: 'hidden', flexShrink: 0 }}><CoverArt series={sObj} height="100%" /></div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 13.5, fontWeight: 800, letterSpacing: '0.02em', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{series} · {edition} <span style={{ color: 'var(--accent)' }}>#{num || '—'}</span></div>
            <div style={{ fontSize: 11.5, color: 'var(--muted)', marginTop: 3, lineHeight: 1.45 }}>Podaci ispod vežu se uz ovaj broj — nakon spremanja forma se puni za sljedeći.</div>
          </div>
        </div>
        <Field label="Serijal"><SelectField value={series} onChange={setSeries} options={R_SERIES.map((s) => s.name)} /></Field>
        <Field label="Edicija"><SelectField value={edition} onChange={setEdition} options={editions} /></Field>
        <div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            <Field label="Broj"><TextField value={num} onChange={setNum} placeholder="npr. 25" type="number" /></Field>
            <Field label="Godina"><TextField value={year} onChange={setYear} placeholder="1999" type="number" /></Field>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 7, color: '#3EC63E', fontSize: 12, fontWeight: 600 }}>
            <IcoCheck size={13} sw={3} /> Automatski popunjeno — sljedeći broj koji nemaš u ediciji {edition}
          </div>
        </div>
        <Field label="Stanje"><GradeChips value={grade} onChange={setGrade} /></Field>
        <Field label="Nabavna cijena"><TextField value={price} onChange={setPrice} placeholder="0" type="number" suffix="€" /></Field>
        <Toggle on={read} onChange={setRead} label="Već pročitano" />
      </div>
      <div style={{ padding: '0 16px 16px' }}>
        <RedButton onClick={onSave} style={{ width: '100%' }}>SPREMI U KOLEKCIJU</RedButton>
      </div>
    </RScreen>);

}

// ── R6 · FAST SCAN with optimistic snackbar ────────────────────────────
function RScreenFastScan({ t, onBack, onEdit, onDone }) {
  // svaki sken (barkod ili naslovnica) ide u popis — popis je u prozoru na dnu
  const pool = [R_ISSUES[24], R_ISSUES[19], R_ISSUES[7], R_ISSUES[12], R_ISSUES[3]];
  const [list, setList] = React.useState([R_ISSUES[24]]);
  const [mode, setMode] = React.useState('barkod');
  const [flash, setFlash] = React.useState(false);
  const scan = () => {
    setList((l) => [...l, pool[l.length % pool.length]]);
    setFlash(true);
    setTimeout(() => setFlash(false), 380);
  };
  const last = list[list.length - 1];
  return (
    <div className="cc-screen" style={{
      ...ccVars(t, 'dark'), width: 393, height: 852, borderRadius: 28, overflow: 'hidden',
      background: '#0A0B0B', boxShadow: '0 0 0 8px #CAC4D0',
      display: 'flex', flexDirection: 'column', position: 'relative',
      fontFamily: "'Roboto', sans-serif", color: '#fff'
    }}>
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(120% 80% at 50% 38%, #2A2C2B 0%, #111212 55%, #060707 100%)' }}></div>
      <Halftone color="#fff" opacity={0.06} size={5} />
      <div style={{ position: 'absolute', left: '50%', top: '35%', transform: 'translate(-50%,-50%) rotate(3deg)', width: 168, borderRadius: 8, overflow: 'hidden', boxShadow: '0 20px 50px rgba(0,0,0,0.6)', opacity: 0.92 }}>
        <div style={{ aspectRatio: '3/4', position: 'relative' }}><CoverArt issue={last} height="100%" /></div>
      </div>
      <div style={{ position: 'relative', zIndex: 3, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 16px 0' }}>
        <button onClick={onBack} aria-label="Close" style={{ appearance: 'none', width: 44, height: 44, borderRadius: '50%', background: 'rgba(0,0,0,0.45)', border: 'none', color: '#fff', cursor: onBack ? 'pointer' : 'default', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><IcoX size={20} sw={2.4} /></button>
        <ScanModeToggle mode={mode} setMode={setMode} />
        <div style={{ width: 44 }}></div>
      </div>
      <div onClick={scan} style={{ position: 'relative', zIndex: 3, flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 22, cursor: 'pointer' }}>
        <div style={{ position: 'relative', width: mode === 'barkod' ? 250 : 204, height: mode === 'barkod' ? 150 : 268, transition: 'width .2s, height .2s' }}>
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
          <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#3EC63E' }}><IcoCheck size={54} sw={2.6} /></div> :
          mode === 'barkod' && <div style={{ position: 'absolute', left: 12, right: 12, top: '50%', height: 2.5, background: 'var(--accent)', boxShadow: '0 0 14px 2px var(--accent)', borderRadius: 2 }}></div>}
        </div>
        <span style={{ fontSize: 13.5, color: 'rgba(255,255,255,0.85)', fontWeight: 500 }}>{mode === 'barkod' ? 'Uperi u barkod — svaki sken ide u popis' : 'Slikaj naslovnicu — prepoznajemo strip'}</span>
      </div>
      {/* popis skeniranih — prozor na dnu (kao "posudbe kasne") */}
      {list.length > 0 &&
      <ScanTray count={list.length}
      sub={'zadnji: Dylan Dog #' + last.number + ' — ' + last.title}
      onEdit={onEdit}
      onAdd={onDone ? () => onDone(list) : undefined} />
      }
    </div>);

}

Object.assign(window, {
  RScreenHome, RScreenShelf, RScreenCompact, RScreenConfirm, RScreenManual, RScreenFastScan,
  RNavBar, GradeChips, RScreen, SyncChip, RSectionHead, R_GRADES
});
