// cc-enterprise-2.jsx — ostatak enterprise aplikacije:
// E5 pozicija (primjerci), E6 detalj primjerka, E7 članovi, E8 član,
// E9 nova posudba (sken članske → sken primjerka), E10 rezervacije, E11 postavke.

const { ISSUES: E2_ISSUES } = window.CC_DATA;

const e2I = (paths) => ({ size = 22, color = 'currentColor', sw = 2, style }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={sw}
    strokeLinecap="round" strokeLinejoin="round" style={style}>{paths}</svg>
);
const E2IcoCard  = e2I(<g><rect x="3" y="5.5" width="18" height="13" rx="2" /><path d="M3 10h18M6.5 14.5h5" /></g>);
const E2IcoShelf = e2I(<g><path d="M3.5 5h17M3.5 12h17M3.5 19h17" /><path d="M6 5v7M11 5v7M16 12v7M8.5 12v7" /></g>);
const E2IcoBox   = e2I(<g><path d="M3.5 8 12 3.5 20.5 8v8L12 20.5 3.5 16z" /><path d="M3.5 8 12 12.5 20.5 8M12 12.5v8" /></g>);
const E2IcoCloud = e2I(<g><path d="M7 18a4.5 4.5 0 0 1-.6-8.96 6 6 0 0 1 11.6 1.6A3.7 3.7 0 0 1 17.5 18z" /></g>);
const E2IcoCsv   = e2I(<g><path d="M12 3.5V15M7.5 10.5 12 15l4.5-4.5" /><path d="M4 20.5h16" /></g>);
const E2IcoOut   = e2I(<g><path d="M9 4H5.5A1.5 1.5 0 0 0 4 5.5v13A1.5 1.5 0 0 0 5.5 20H9" /><path d="M15 8l4 4-4 4M8.5 12H19" /></g>);
const E2IcoMoveTo= e2I(<g><path d="M4 17V7a2 2 0 0 1 2-2h5" /><path d="M14 3.5 18 7l-4 3.5M8 7h10" transform="translate(0 1)" /><rect x="4" y="17" width="16" height="4" rx="1.5" /></g>);

const E2_MEMBERS = [
  { id: 'm1', name: 'Ivana K.', card: '0042', mail: 'ivana.k@email.com', phone: '091 234 5678', active: 1, total: 23, joined: '2023.', overdue: 0 },
  { id: 'm2', name: 'Marko P.', card: '0117', mail: 'marko.p@email.com', phone: '098 111 2233', active: 1, total: 41, joined: '2021.', overdue: 1 },
  { id: 'm3', name: 'Ana V.',   card: '0009', mail: 'ana.v@email.com',   phone: '095 555 8901', active: 1, total: 64, joined: '2019.', overdue: 1 },
  { id: 'm4', name: 'Luka B.',  card: '0201', mail: 'luka.b@email.com',  phone: '099 320 4455', active: 1, total: 8,  joined: '2025.', overdue: 0 },
  { id: 'm5', name: 'Petra M.', card: '0088', mail: 'petra.m@email.com', phone: '092 776 1100', active: 1, total: 31, joined: '2022.', overdue: 0 },
];

const E2_STATUS = {
  dostupno:    { label: 'Dostupno',    color: '#3EC63E', bg: 'rgba(62,198,62,0.14)',  border: 'rgba(62,198,62,0.5)' },
  posudeno:    { label: 'Posuđeno',    color: '#E8C547', bg: 'rgba(232,197,71,0.12)', border: 'rgba(232,197,71,0.5)' },
  rezervirano: { label: 'Rezervirano', color: '#D9514A', bg: 'rgba(198,41,30,0.14)',  border: 'rgba(198,41,30,0.5)' },
};

const E2_ITEMS = [
  { inv: '2026-0331', iss: E2_ISSUES[2],  status: 'dostupno' },
  { inv: '2026-0298', iss: E2_ISSUES[5],  status: 'posudeno', who: 'Ivana K.' },
  { inv: '2026-0214', iss: E2_ISSUES[12], status: 'dostupno' },
  { inv: '2025-0871', iss: E2_ISSUES[19], status: 'rezervirano', who: 'Petra M.' },
  { inv: '2025-0644', iss: E2_ISSUES[24], status: 'dostupno' },
  { inv: '2024-0102', iss: E2_ISSUES[7],  status: 'posudeno', who: 'Ana V.' },
];

const E2_RES = [
  { id: 'r1', member: 'Petra M.', card: '0088', iss: E2_ISSUES[19], until: '05. srp', ready: true },
  { id: 'r2', member: 'Luka B.',  card: '0201', iss: E2_ISSUES[3],  until: '06. srp', ready: true },
  { id: 'r3', member: 'Ivana K.', card: '0042', iss: E2_ISSUES[9],  until: '08. srp', ready: true },
  { id: 'r4', member: 'Marko P.', card: '0117', iss: E2_ISSUES[15], until: '—', ready: false },
  { id: 'r5', member: 'Ana V.',   card: '0009', iss: E2_ISSUES[21], until: '—', ready: false },
];

function E2StatusChip({ s }) {
  const c = E2_STATUS[s] || E2_STATUS.dostupno;
  return <span style={{ flexShrink: 0, fontSize: 11, fontWeight: 800, letterSpacing: '0.04em', color: c.color, background: c.bg, border: '1px solid ' + c.border, borderRadius: 999, padding: '4px 10px' }}>{c.label}</span>;
}

function E2Avatar({ name, size = 40 }) {
  return <div style={{ width: size, height: size, borderRadius: '50%', background: 'var(--deep)', border: '1.5px solid var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 800, fontSize: size * 0.38, color: 'var(--accent)', flexShrink: 0 }}>{name[0]}</div>;
}

// ── POPUP · PROMJENA POZICIJE — donji list ──────────────────────────
// Koristi se kod prijema robe ("Promijeni") i na primjerku ("Premjesti").
function EPositionSheet({ t, current, onClose, onPick, title = 'PROMIJENI POZICIJU' }) {
  const locs = window.E_LOCATIONS || [];
  const [sel, setSel] = React.useState(current || (locs[0] && locs[0].name));
  const [adding, setAdding] = React.useState(false);
  const [npName, setNpName] = React.useState('');
  const [npZone, setNpZone] = React.useState('');
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 30, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
      <div onClick={onClose} style={{ position: 'absolute', inset: 0, background: 'rgba(6,8,8,0.62)', backdropFilter: 'blur(2px)', cursor: 'pointer' }}></div>
      <div style={{ position: 'relative', borderRadius: '24px 24px 0 0', background: 'var(--surface)', ...ccVars(t), padding: '10px 16px 18px', display: 'flex', flexDirection: 'column', gap: 10, boxShadow: '0 -12px 40px rgba(0,0,0,0.6)', fontFamily: "'Roboto', sans-serif", color: 'var(--text)' }}>
        <div style={{ width: 40, height: 4, borderRadius: 999, background: 'var(--line)', margin: '0 auto 2px' }}></div>
        <div style={{ textAlign: 'center' }}>
          <span style={{ fontWeight: 800, fontSize: 15, letterSpacing: '0.04em' }}>{title}</span>
          <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 3 }}>Lokacija: Zagreb — Ilica 45</div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 7, maxHeight: 340, overflowY: 'auto' }}>
          {locs.map(l => {
            const on = sel === l.name;
            return (
              <div key={l.id} onClick={() => setSel(l.name)} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '10px 13px', borderRadius: 13, background: 'var(--deep)', border: '1.5px solid ' + (on ? 'var(--accent)' : 'var(--line)'), cursor: 'pointer' }}>
                <div style={{ width: 36, height: 36, borderRadius: 10, background: 'var(--surface)', color: on ? 'var(--accent)' : 'var(--muted)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  {l.id.startsWith('s') ? <E2IcoBox size={19} /> : <E2IcoShelf size={19} />}
                </div>
                <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 1 }}>
                  <span style={{ fontWeight: 700, fontSize: 13.5 }}>{l.name}</span>
                  <span style={{ fontSize: 11.5, color: 'var(--text2)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{l.zone}</span>
                </div>
                <span style={{ fontSize: 11.5, color: l.count >= l.cap ? '#D9514A' : 'var(--muted)', fontWeight: 600, flexShrink: 0 }}>{l.count}/{l.cap}</span>
                <div style={{ width: 19, height: 19, borderRadius: '50%', border: '2px solid ' + (on ? 'var(--accent)' : 'var(--muted)'), display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  {on && <div style={{ width: 9, height: 9, borderRadius: '50%', background: 'var(--accent)' }}></div>}
                </div>
              </div>
            );
          })}
          <button onClick={() => setAdding(true)} style={{ appearance: 'none', cursor: 'pointer', border: '1.5px dashed var(--line)', borderRadius: 13, padding: '11px', background: 'transparent', color: 'var(--text2)', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 12.5 }}>+ Nova pozicija</button>
        </div>
        {adding && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 9, padding: 12, borderRadius: 13, background: 'var(--deep)', border: '1px solid var(--line)' }}>
            <Field label="Naziv pozicije"><TextField value={npName} onChange={setNpName} placeholder="npr. Polica C1" /></Field>
            <Field label="Zona / sadržaj"><TextField value={npZone} onChange={setNpZone} placeholder="npr. Manga" /></Field>
            <button onClick={() => setAdding(false)} style={{ appearance: 'none', cursor: 'pointer', border: '1.5px solid var(--accent)', borderRadius: 999, padding: '10px', background: 'transparent', color: 'var(--accent)', fontFamily: "'Roboto', sans-serif", fontWeight: 800, fontSize: 12.5 }}>DODAJ POZICIJU</button>
          </div>
        )}
        <RedButton onClick={() => onPick && onPick(sel)} style={{ width: '100%' }}>SPREMI — {(sel || '').toUpperCase()}</RedButton>
      </div>
    </div>
  );
}

// ── E5 · POZICIJA — primjerci na polici ────────────────────────────────
function EScreenPosition({ t, pos, onNav, onScan, onBack, onOpenItem }) {
  const p = pos || { name: 'Polica A1', zone: 'Bonelli — Dylan Dog', count: 84, cap: 90 };
  const [q, setQ] = React.useState('');
  const list = E2_ITEMS.filter(x => ('#' + x.iss.number + ' ' + x.iss.title + ' ' + x.inv).toLowerCase().includes(q.trim().toLowerCase()));
  return (
    <EScreen t={t} nav="inventar" onNav={onNav} onScan={onScan}>
      <EHeader t={t} text={p.name.toUpperCase()} badge={'LOKACIJA: ILICA 45'} onBack={onBack} />
      <p style={{ margin: '2px 16px 10px', textAlign: 'center', fontSize: 12.5, color: 'var(--muted)' }}>{p.zone} · {p.count}/{p.cap} primjeraka</p>
      <div style={{ padding: '0 16px 10px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 14px', borderRadius: 999, background: 'var(--surface)', border: '1px solid var(--line)' }}>
          <span style={{ color: 'var(--muted)', display: 'flex' }}><IcoSearch size={17} /></span>
          <input value={q} onChange={e => setQ(e.target.value)} placeholder="Naslov, broj ili inventarni broj…" style={{ flex: 1, minWidth: 0, background: 'none', border: 'none', outline: 'none', fontFamily: "'Roboto', sans-serif", fontSize: 13.5, color: 'var(--text)' }} />
        </div>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '0 16px 24px', display: 'flex', flexDirection: 'column', gap: 8 }}>
        {list.map(x => (
          <div key={x.inv} onClick={onOpenItem && (() => onOpenItem(x))} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 9, borderRadius: 13, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', cursor: onOpenItem ? 'pointer' : 'default' }}>
            <div style={{ width: 40, height: 54, borderRadius: 6, overflow: 'hidden', flexShrink: 0 }}><CoverArt issue={x.iss} height="100%" /></div>
            <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
              <span style={{ fontWeight: 700, fontSize: 13.5, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>#{x.iss.number} — {x.iss.title}</span>
              <span style={{ fontSize: 11.5, color: 'var(--text2)', fontFamily: "'JetBrains Mono', monospace" }}>inv. {x.inv}{x.who ? ' · ' + x.who : ''}</span>
            </div>
            <E2StatusChip s={x.status} />
          </div>
        ))}
      </div>
    </EScreen>
  );
}

// ── E6 · DETALJ PRIMJERKA ───────────────────────────────────────────────
function EScreenItem({ t, item, onNav, onScan, onBack, onLoan, startWriteOff = false }) {
  const x = item || E2_ITEMS[0];
  const [pos, setPos] = React.useState('Polica A1');
  const [sheet, setSheet] = React.useState(false);
  const [woff, setWoff] = React.useState(startWriteOff);
  const [woffReason, setWoffReason] = React.useState('Oštećeno');
  const hist = [
    { who: 'Ana V. · 0009', when: '03/2026 — 04/2026' },
    { who: 'Luka B. · 0201', when: '11/2025 — 12/2025' },
    { who: 'Ivana K. · 0042', when: '06/2025 — 07/2025' },
  ];
  return (
    <EScreen t={t} nav="inventar" onNav={onNav} onScan={onScan}>
      <EHeader t={t} text="PRIMJERAK" badge={'INV. ' + x.inv} onBack={onBack} />
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '6px 20px 20px' }}>
        <div style={{ display: 'flex', gap: 14 }}>
          <div style={{ width: 110, flexShrink: 0, borderRadius: 10, overflow: 'hidden', boxShadow: '0 10px 26px rgba(0,0,0,0.5)' }}>
            <div style={{ aspectRatio: '3/4', position: 'relative' }}><CoverArt issue={x.iss} height="100%" /></div>
          </div>
          <div style={{ flex: 1, minWidth: 0, paddingTop: 2 }}>
            <h2 style={{ margin: 0, fontSize: 17, fontWeight: 800 }}>#{x.iss.number} — {x.iss.title}</h2>
            <p style={{ margin: '4px 0 0', fontSize: 13, color: 'var(--text2)' }}>Dylan Dog · EXTRA · {x.iss.year}</p>
            <div style={{ marginTop: 10 }}><E2StatusChip s={x.status} /></div>
            {x.who && <p style={{ margin: '8px 0 0', fontSize: 12.5, color: 'var(--text2)' }}>kod: <b style={{ color: 'var(--text)' }}>{x.who}</b></p>}
          </div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '11px 14px', borderRadius: 13, background: 'var(--surface)', border: '1px solid var(--line)', marginTop: 16 }}>
          <span style={{ color: 'var(--accent)', display: 'flex', flexShrink: 0 }}><E2IcoShelf size={18} /></span>
          <span style={{ fontSize: 13, fontWeight: 600 }}>Pozicija: <b>{pos}</b> · Ilica 45</span>
          <button onClick={() => setSheet(true)} style={{ appearance: 'none', cursor: 'pointer', marginLeft: 'auto', flexShrink: 0, background: 'none', border: 'none', color: 'var(--accent)', fontWeight: 700, fontSize: 12.5, fontFamily: "'Roboto', sans-serif", display: 'flex', alignItems: 'center', gap: 5 }}><E2IcoMoveTo size={15} /> Premjesti</button>
        </div>
        <div style={{ marginTop: 18 }}>
          <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.1em', textTransform: 'uppercase', fontWeight: 700 }}>Povijest posudbi</span>
          <div style={{ display: 'flex', flexDirection: 'column', marginTop: 8 }}>
            {hist.map((h, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '10px 2px', borderBottom: '1px solid var(--line)' }}>
                <span style={{ fontSize: 13, fontWeight: 600 }}>{h.who}</span>
                <span style={{ fontSize: 12, color: 'var(--muted)' }}>{h.when}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
      <div style={{ padding: '0 16px 16px', display: 'flex', gap: 10 }}>
        <button onClick={() => setWoff(true)} style={{ appearance: 'none', cursor: 'pointer', flex: 1, border: '1.5px solid var(--line)', borderRadius: 999, padding: '13px 8px', background: 'transparent', color: 'var(--text2)', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 13 }}>Otpiši</button>
        <RedButton onClick={onLoan} style={{ flex: 2 }}>{x.status === 'posudeno' ? 'ZAPRIMI POVRAT' : 'POSUDI ČLANU'}</RedButton>
      </div>
      {sheet && <EPositionSheet t={t} title="PREMJESTI PRIMJERAK" current={pos} onClose={() => setSheet(false)} onPick={p => { setPos(p); setSheet(false); }} />}
      {woff && (
        <div style={{ position: 'absolute', inset: 0, zIndex: 30, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
          <div onClick={() => setWoff(false)} style={{ position: 'absolute', inset: 0, background: 'rgba(6,8,8,0.62)', backdropFilter: 'blur(2px)', cursor: 'pointer' }}></div>
          <div style={{ position: 'relative', width: '100%', borderRadius: 18, background: 'var(--surface)', padding: '16px 16px 14px', boxShadow: '0 20px 60px rgba(0,0,0,0.7)', display: 'flex', flexDirection: 'column', gap: 12 }}>
            <span style={{ fontWeight: 800, fontSize: 15.5, letterSpacing: '0.02em' }}>Otpis primjerka</span>
            <span style={{ fontSize: 13, color: 'var(--text2)', lineHeight: 1.55 }}>#{x.iss.number} — {x.iss.title} · inv. {x.inv}<br />Primjerak se uklanja iz inventara, zapis ostaje u povijesti.</span>
            <Field label="Razlog"><SelectField value={woffReason} onChange={setWoffReason} options={['Oštećeno', 'Izgubljeno', 'Prodano', 'Doniranno'.replace('nn','n'), 'Ostalo']} /></Field>
            <div style={{ display: 'flex', gap: 9 }}>
              <button onClick={() => setWoff(false)} style={{ appearance: 'none', cursor: 'pointer', flex: 1, border: '1.5px solid var(--line)', borderRadius: 999, padding: '11px 8px', background: 'transparent', color: 'var(--text2)', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 12.5 }}>Odustani</button>
              <button onClick={() => setWoff(false)} style={{ appearance: 'none', cursor: 'pointer', flex: 1, border: 'none', borderRadius: 999, padding: '11px 8px', background: '#A91A1A', color: '#FFF', fontFamily: "'Roboto', sans-serif", fontWeight: 800, fontSize: 12.5 }}>OTPIŠI</button>
            </div>
          </div>
        </div>
      )}
    </EScreen>
  );
}

// ── E7 · ČLANOVI ────────────────────────────────────────────────────────
function EScreenMembers({ t, onNav, onScan, onBack, onOpenMember, onNewMember }) {
  const [q, setQ] = React.useState('');
  const list = E2_MEMBERS.filter(m => (m.name + ' ' + m.card).toLowerCase().includes(q.trim().toLowerCase()));
  return (
    <EScreen t={t} nav="posudbe" onNav={onNav} onScan={onScan}>
      <EHeader t={t} text="ČLANOVI" badge="ILICA 45 · 214 ČLANOVA" onBack={onBack} />
      <div style={{ padding: '6px 16px 10px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 14px', borderRadius: 999, background: 'var(--surface)', border: '1px solid var(--line)' }}>
          <span style={{ color: 'var(--muted)', display: 'flex' }}><IcoSearch size={17} /></span>
          <input value={q} onChange={e => setQ(e.target.value)} placeholder="Ime ili broj iskaznice…" style={{ flex: 1, minWidth: 0, background: 'none', border: 'none', outline: 'none', fontFamily: "'Roboto', sans-serif", fontSize: 13.5, color: 'var(--text)' }} />
        </div>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '0 16px 12px', display: 'flex', flexDirection: 'column', gap: 8 }}>
        {list.map(m => (
          <div key={m.id} onClick={onOpenMember && (() => onOpenMember(m))} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '11px 13px', borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', cursor: onOpenMember ? 'pointer' : 'default' }}>
            <E2Avatar name={m.name} />
            <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
              <span style={{ fontWeight: 700, fontSize: 14.5 }}>{m.name}</span>
              <span style={{ fontSize: 12, color: 'var(--text2)' }}>iskaznica {m.card} · član od {m.joined}</span>
            </div>
            {m.overdue > 0
              ? <span style={{ flexShrink: 0, fontSize: 11, fontWeight: 800, color: '#D9514A', background: 'rgba(198,41,30,0.14)', border: '1px solid rgba(198,41,30,0.5)', borderRadius: 999, padding: '4px 10px' }}>KASNI {m.overdue}</span>
              : <span style={{ flexShrink: 0, fontSize: 12, color: 'var(--muted)', fontWeight: 600 }}>{m.active} aktivna</span>}
          </div>
        ))}
      </div>
      <div style={{ padding: '0 16px 16px' }}>
        <RedButton small onClick={onNewMember} style={{ width: '100%' }}>+ NOVI ČLAN</RedButton>
      </div>
    </EScreen>
  );
}

// ── E8 · ČLAN — detalj ──────────────────────────────────────────────────
function EScreenMember({ t, member, onNav, onScan, onBack, onNew }) {
  const m = member || E2_MEMBERS[2];
  const loans = [
    { iss: E2_ISSUES[12], due: '30. lip', overdue: m.overdue > 0 },
  ];
  const stat = (label, big, warn) => (
    <div style={{ flex: 1, padding: '10px 8px', borderRadius: 13, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', textAlign: 'center' }}>
      <div style={{ fontSize: 20, fontWeight: 800, color: warn ? '#D9514A' : 'var(--text)' }}>{big}</div>
      <div style={{ fontSize: 11, color: 'var(--muted)', marginTop: 2, textTransform: 'uppercase', letterSpacing: '0.06em', fontWeight: 600 }}>{label}</div>
    </div>
  );
  return (
    <EScreen t={t} nav="posudbe" onNav={onNav} onScan={onScan}>
      <EHeader t={t} text="ČLAN" badge={'ISKAZNICA ' + m.card} onBack={onBack} />
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '6px 16px 16px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: 14, borderRadius: 16, background: 'var(--surface)', boxShadow: 'var(--card-shadow)' }}>
          <E2Avatar name={m.name} size={54} />
          <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 3 }}>
            <span style={{ fontWeight: 800, fontSize: 17 }}>{m.name}</span>
            <span style={{ fontSize: 12.5, color: 'var(--text2)' }}>{m.mail}</span>
            <span style={{ fontSize: 12.5, color: 'var(--text2)' }}>{m.phone}</span>
          </div>
          <span style={{ color: 'var(--muted)', display: 'flex', flexShrink: 0 }}><E2IcoCard size={22} /></span>
        </div>
        <div style={{ display: 'flex', gap: 9 }}>
          {stat('Aktivne', m.active)}
          {stat('Ukupno', m.total)}
          {stat('Kasni', m.overdue, m.overdue > 0)}
        </div>
        <div>
          <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.1em', textTransform: 'uppercase', fontWeight: 700 }}>Aktivne posudbe</span>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 9 }}>
            {loans.map((l, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 10, borderRadius: 13, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', border: l.overdue ? '1px solid rgba(198,41,30,0.5)' : '1px solid transparent' }}>
                <div style={{ width: 40, height: 54, borderRadius: 6, overflow: 'hidden', flexShrink: 0 }}><CoverArt issue={l.iss} height="100%" /></div>
                <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                  <span style={{ fontWeight: 700, fontSize: 13.5 }}>#{l.iss.number} — {l.iss.title}</span>
                  <span style={{ fontSize: 12, fontWeight: 700, color: l.overdue ? '#D9514A' : 'var(--muted)' }}>{l.overdue ? 'Kasni — rok ' + l.due : 'Rok: ' + l.due}</span>
                </div>
                <button style={{ appearance: 'none', cursor: 'pointer', flexShrink: 0, border: '1.5px solid var(--accent)', borderRadius: 999, padding: '7px 12px', background: 'transparent', color: 'var(--accent)', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 11.5 }}>VRAĆENO</button>
              </div>
            ))}
          </div>
        </div>
        {m.overdue > 0 && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '11px 14px', borderRadius: 13, background: 'rgba(232,197,71,0.10)', border: '1px solid rgba(232,197,71,0.45)' }}>
            <span style={{ fontSize: 13, lineHeight: 1.5 }}>Posudba kasni — pošalji podsjetnik</span>
            <button style={{ appearance: 'none', cursor: 'pointer', marginLeft: 'auto', flexShrink: 0, background: 'none', border: 'none', color: 'var(--accent)', fontWeight: 700, fontSize: 12.5, fontFamily: "'Roboto', sans-serif" }}>Pošalji</button>
          </div>
        )}
      </div>
      <div style={{ padding: '0 16px 16px' }}>
        <RedButton onClick={onNew} style={{ width: '100%' }}>NOVA POSUDBA</RedButton>
      </div>
    </EScreen>
  );
}

// ── E9 · NOVA POSUDBA — sken članske → sken primjerka → potvrda ────────
function EScreenNewLoan({ t, onClose, onDone }) {
  const [step, setStep] = React.useState(0);
  const m = E2_MEMBERS[0];
  const x = E2_ITEMS[2];
  const scanTap = () => setStep(s => Math.min(2, s + 1));
  const captions = ['Skeniraj člansku iskaznicu', 'Skeniraj primjerak — barkod ili naslovnica', 'Provjeri i potvrdi'];
  return (
    <div className="cc-screen" style={{
      ...ccVars(t, 'dark'), width: 393, height: 852, borderRadius: 28, overflow: 'hidden',
      background: '#0A0B0B', boxShadow: '0 0 0 8px #CAC4D0',
      display: 'flex', flexDirection: 'column', position: 'relative',
      fontFamily: "'Roboto', sans-serif", color: '#fff',
    }}>
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(120% 80% at 50% 34%, #2A2C2B 0%, #111212 55%, #060707 100%)' }}></div>
      <Halftone color="#fff" opacity={0.06} size={5} />
      <div style={{ position: 'relative', zIndex: 3, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 16px 0' }}>
        <button onClick={onClose} aria-label="Close" style={{ appearance: 'none', width: 44, height: 44, borderRadius: '50%', background: 'rgba(0,0,0,0.45)', border: 'none', color: '#fff', cursor: onClose ? 'pointer' : 'default', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><IcoX size={20} sw={2.4} /></button>
        <span style={{ fontSize: 13, fontWeight: 600, background: 'rgba(0,0,0,0.45)', padding: '7px 14px', borderRadius: 999 }}>Nova posudba · korak {step + 1}/3</span>
        <div style={{ width: 44 }}></div>
      </div>
      <div onClick={step < 2 ? scanTap : undefined} style={{ position: 'relative', zIndex: 3, flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 20, cursor: step < 2 ? 'pointer' : 'default' }}>
        {step < 2 ? (
          <div style={{ position: 'relative', width: step === 0 ? 260 : 250, height: step === 0 ? 164 : 150 }}>
            {[0, 1, 2, 3].map(i => {
              const top = i < 2, left = i % 2 === 0;
              return <div key={i} style={{ position: 'absolute', [top ? 'top' : 'bottom']: 0, [left ? 'left' : 'right']: 0, width: 34, height: 34,
                borderTop: top ? '4px solid var(--accent)' : 'none', borderBottom: !top ? '4px solid var(--accent)' : 'none',
                borderLeft: left ? '4px solid var(--accent)' : 'none', borderRight: !left ? '4px solid var(--accent)' : 'none',
                borderTopLeftRadius: top && left ? 10 : 0, borderTopRightRadius: top && !left ? 10 : 0,
                borderBottomLeftRadius: !top && left ? 10 : 0, borderBottomRightRadius: !top && !left ? 10 : 0 }}></div>;
            })}
            {step === 0
              ? <div style={{ position: 'absolute', inset: 20, borderRadius: 10, border: '1.5px dashed rgba(255,255,255,0.35)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'rgba(255,255,255,0.5)' }}><E2IcoCard size={44} sw={1.6} /></div>
              : <div style={{ position: 'absolute', left: 12, right: 12, top: '50%', height: 2.5, background: 'var(--accent)', boxShadow: '0 0 14px 2px var(--accent)', borderRadius: 2 }}></div>}
          </div>
        ) : (
          <div style={{ color: '#3EC63E' }}><IcoCheck size={64} sw={2.4} /></div>
        )}
        <span style={{ fontSize: 13.5, color: 'rgba(255,255,255,0.85)', fontWeight: 500 }}>{captions[step]}</span>
      </div>
      {/* progresivni popis na dnu */}
      <div style={{ position: 'relative', zIndex: 3, margin: '0 16px 18px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {step >= 1 && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 14px', borderRadius: 14, background: 'rgba(26,23,18,0.97)', border: '1px solid rgba(62,198,62,0.4)' }}>
            <E2Avatar name={m.name} size={38} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 13.5, fontWeight: 700 }}>{m.name} · iskaznica {m.card}</div>
              <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.6)', marginTop: 2 }}>{m.active} aktivna · 0 kasni</div>
            </div>
            <span style={{ color: '#3EC63E', display: 'flex', flexShrink: 0 }}><IcoCheck size={17} sw={3} /></span>
          </div>
        )}
        {step >= 2 && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 14px', borderRadius: 14, background: 'rgba(26,23,18,0.97)', border: '1px solid rgba(62,198,62,0.4)' }}>
            <div style={{ width: 38, height: 50, borderRadius: 6, overflow: 'hidden', flexShrink: 0 }}><CoverArt issue={x.iss} height="100%" /></div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 13.5, fontWeight: 700, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>#{x.iss.number} — {x.iss.title}</div>
              <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.6)', marginTop: 2, fontFamily: "'JetBrains Mono', monospace" }}>inv. {x.inv}</div>
            </div>
            <span style={{ color: '#3EC63E', display: 'flex', flexShrink: 0 }}><IcoCheck size={17} sw={3} /></span>
          </div>
        )}
        {step === 2
          ? <RedButton onClick={onDone} style={{ width: '100%' }}>POTVRDI — ROK VRAĆANJA 24. SRP</RedButton>
          : <span style={{ textAlign: 'center', fontSize: 12, color: 'rgba(255,255,255,0.45)' }}>{step === 0 ? 'Prisloni iskaznicu u okvir' : 'Rok posudbe: 21 dan (Postavke)'}</span>}
      </div>
    </div>
  );
}

// ── E10 · REZERVACIJE ───────────────────────────────────────────────────
function EScreenReservations({ t, onNav, onScan, onBack }) {
  const [tab, setTab] = React.useState('spremne');
  const list = E2_RES.filter(r => tab === 'sve' || r.ready);
  return (
    <EScreen t={t} nav="posudbe" onNav={onNav} onScan={onScan}>
      <EHeader t={t} text="REZERVACIJE" badge="ILICA 45" onBack={onBack} />
      <div style={{ display: 'flex', gap: 7, padding: '6px 16px 12px' }}>
        {[['spremne', 'Spremne · ' + E2_RES.filter(r => r.ready).length], ['sve', 'Sve · ' + E2_RES.length]].map(([k, lbl]) => (
          <button key={k} onClick={() => setTab(k)} style={{
            appearance: 'none', cursor: 'pointer',
            border: '1px solid ' + (tab === k ? 'var(--accent)' : 'var(--line)'),
            background: tab === k ? 'var(--accent)' : 'transparent',
            color: tab === k ? '#FFF' : 'var(--text2)',
            borderRadius: 999, padding: '7px 14px', fontFamily: "'Roboto', sans-serif", fontWeight: 600, fontSize: 12,
          }}>{lbl}</button>
        ))}
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '0 16px 24px', display: 'flex', flexDirection: 'column', gap: 9 }}>
        {list.map(r => (
          <div key={r.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 10, borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', border: r.ready ? '1px solid rgba(62,198,62,0.45)' : '1px solid transparent' }}>
            <div style={{ width: 42, height: 56, borderRadius: 6, overflow: 'hidden', flexShrink: 0 }}><CoverArt issue={r.iss} height="100%" /></div>
            <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
              <span style={{ fontWeight: 700, fontSize: 13.5, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>#{r.iss.number} — {r.iss.title}</span>
              <span style={{ fontSize: 12, color: 'var(--text2)' }}>{r.member} · iskaznica {r.card}</span>
              <span style={{ fontSize: 12, fontWeight: 700, color: r.ready ? '#3EC63E' : 'var(--muted)' }}>{r.ready ? 'Spremno · čuvamo do ' + r.until : 'Na listi čekanja'}</span>
            </div>
            {r.ready
              ? <button style={{ appearance: 'none', cursor: 'pointer', flexShrink: 0, border: 'none', borderRadius: 999, padding: '8px 13px', background: 'var(--accent)', color: '#FFF', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 11.5 }}>PREUZETO</button>
              : <button style={{ appearance: 'none', cursor: 'pointer', flexShrink: 0, border: '1px solid var(--line)', borderRadius: 999, padding: '8px 13px', background: 'transparent', color: 'var(--muted)', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 11.5 }}>OTKAŽI</button>}
          </div>
        ))}
      </div>
    </EScreen>
  );
}

// ── E11 · POSTAVKE (enterprise) ─────────────────────────────────────────
function EScreenSettingsE({ t, onNav, onScan }) {
  const [autoSync, setAutoSync] = React.useState(true);
  const staff = [
    { name: 'Karlo N.', role: 'Voditelj' },
    { name: 'Maja S.', role: 'Djelatnik' },
    { name: 'Filip R.', role: 'Djelatnik' },
  ];
  const toggle = (on, set) => (
    <div onClick={() => set(!on)} style={{ width: 44, height: 26, borderRadius: 999, background: on ? 'var(--accent)' : 'var(--deep)', position: 'relative', cursor: 'pointer', transition: 'background .15s', flexShrink: 0 }}>
      <div style={{ position: 'absolute', top: 3, left: on ? 21 : 3, width: 20, height: 20, borderRadius: '50%', background: '#fff', transition: 'left .15s', boxShadow: '0 1px 3px rgba(0,0,0,0.4)' }}></div>
    </div>
  );
  const section = (label) => (
    <span style={{ fontSize: 12, color: 'var(--muted)', letterSpacing: '0.1em', textTransform: 'uppercase', fontWeight: 700, margin: '6px 4px 0' }}>{label}</span>
  );
  return (
    <EScreen t={t} nav="postavke" onNav={onNav} onScan={onScan}>
      <EHeader t={t} text="POSTAVKE" badge="UGOVOR CC-2026-0142" />
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '4px 16px 24px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {section('Poslovnica')}
        <div style={{ padding: '13px 16px', borderRadius: 14, background: 'var(--surface)', display: 'flex', flexDirection: 'column', gap: 3 }}>
          <span style={{ fontSize: 14.5, fontWeight: 800 }}>Strip knjižnica Zagreb</span>
          <span style={{ fontSize: 12.5, color: 'var(--text2)' }}>Lokacija: Zagreb — Ilica 45 · glavna poslovnica</span>
          <span style={{ fontSize: 12.5, color: 'var(--text2)' }}>Ugovor vrijedi do 12/2026 · 3 lokacije</span>
        </div>
        {section('Osoblje')}
        <div style={{ borderRadius: 14, background: 'var(--surface)', overflow: 'hidden' }}>
          {staff.map((s, i) => (
            <div key={s.name} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '11px 16px', borderTop: i > 0 ? '1px solid var(--line)' : 'none' }}>
              <E2Avatar name={s.name} size={34} />
              <span style={{ flex: 1, fontSize: 14, fontWeight: 600 }}>{s.name}</span>
              <span style={{ fontSize: 12, color: s.role === 'Voditelj' ? 'var(--accent)' : 'var(--muted)', fontWeight: 700 }}>{s.role}</span>
            </div>
          ))}
          <div style={{ padding: '10px 16px', borderTop: '1px solid var(--line)' }}>
            <button style={{ appearance: 'none', cursor: 'pointer', background: 'none', border: 'none', color: 'var(--accent)', fontSize: 12.5, fontWeight: 700, fontFamily: "'Roboto', sans-serif", padding: 0 }}>+ Dodaj djelatnika</button>
          </div>
        </div>
        {section('Pravila posudbe')}
        <div style={{ borderRadius: 14, background: 'var(--surface)', overflow: 'hidden' }}>
          {[['Rok posudbe', '21 dan'], ['Najviše posudbi po članu', '5'], ['Rezervacija se čuva', '3 dana']].map(([k, v], i) => (
            <div key={k} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 16px', borderTop: i > 0 ? '1px solid var(--line)' : 'none' }}>
              <span style={{ fontSize: 14, fontWeight: 600 }}>{k}</span>
              <span style={{ fontSize: 13.5, fontWeight: 700, color: 'var(--accent)' }}>{v}</span>
            </div>
          ))}
        </div>
        {section('Sinkronizacija i izvještaji')}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: '13px 16px', borderRadius: 14, background: 'var(--surface)' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
            <span style={{ fontSize: 14, fontWeight: 600 }}>Automatska sinkronizacija</span>
            <span style={{ fontSize: 12, color: 'var(--text2)', display: 'inline-flex', alignItems: 'center', gap: 6 }}><span style={{ color: '#3EC63E', display: 'flex' }}><E2IcoCloud size={14} /></span> sve lokacije · zadnja danas 9:28</span>
          </div>
          {toggle(autoSync, setAutoSync)}
        </div>
        <div style={{ display: 'flex', gap: 9 }}>
          {['Inventar CSV', 'Posudbe CSV'].map(lbl => (
            <button key={lbl} style={{ appearance: 'none', cursor: 'pointer', flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7, border: '1px solid var(--line)', borderRadius: 12, padding: '11px 8px', background: 'var(--surface)', color: 'var(--text)', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 12.5 }}>
              <E2IcoCsv size={16} /> {lbl}
            </button>
          ))}
        </div>
        <button style={{ appearance: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, border: '1px solid var(--line)', borderRadius: 12, padding: '12px', background: 'transparent', color: 'var(--text2)', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 13, marginTop: 4 }}>
          <E2IcoOut size={16} /> Odjava
        </button>
      </div>
    </EScreen>
  );
}

// ── E12 · NOVI ČLAN ──────────────────────────────────────────────────
function EScreenNewMember({ t, onNav, onScan, onBack, onSave }) {
  const [name, setName] = React.useState('');
  const [mail, setMail] = React.useState('');
  const [phone, setPhone] = React.useState('');
  return (
    <EScreen t={t} nav="posudbe" onNav={onNav} onScan={onScan}>
      <EHeader t={t} text="NOVI ČLAN" badge="ISKAZNICA 0215 — AUTOMATSKI" onBack={onBack} />
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '6px 16px 16px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <Field label="Ime i prezime"><TextField value={name} onChange={setName} placeholder="npr. Iva Novak" /></Field>
        <Field label="E-mail"><TextField value={mail} onChange={setMail} placeholder="iva@email.com" type="email" /></Field>
        <Field label="Telefon"><TextField value={phone} onChange={setPhone} placeholder="09x xxx xxxx" /></Field>
        <div style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '12px 14px', borderRadius: 13, background: 'var(--surface)', border: '1px solid var(--line)' }}>
          <span style={{ color: 'var(--accent)', display: 'flex', flexShrink: 0 }}><E2IcoCard size={20} /></span>
          <span style={{ fontSize: 13, lineHeight: 1.5, color: 'var(--text2)' }}>Nova iskaznica <b style={{ color: 'var(--text)' }}>0215</b> — ispiši naljepnicu s barkodom nakon spremanja.</span>
        </div>
        <p style={{ margin: 0, fontSize: 12, color: 'var(--muted)', lineHeight: 1.6 }}>Član potpisuje pristupnicu u poslovnici. Podaci se sinkroniziraju na sve lokacije.</p>
      </div>
      <div style={{ padding: '0 16px 16px' }}>
        <RedButton onClick={onSave} style={{ width: '100%' }}>SPREMI ČLANA</RedButton>
      </div>
    </EScreen>
  );
}

Object.assign(window, {
  EScreenPosition, EScreenItem, EScreenMembers, EScreenMember,
  EScreenNewLoan, EScreenReservations, EScreenSettingsE, EPositionSheet, EScreenNewMember,
});
