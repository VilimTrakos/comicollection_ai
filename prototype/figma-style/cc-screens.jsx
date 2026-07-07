// cc-screens.jsx — screens for the Figma-style Comics Collection design

const { SERIES, HOUSES, ISSUES, FEATURED, UNREAD } = window.CC_DATA;

// Shared issue-state store (read/owned/dupli/loaned overrides). Falls back
// to a local store when a screen is rendered standalone on the canvas.
function useStore(st) {
  const [ov, setOv] = React.useState({});
  const local = {
    getIssue: it => ({ ...it, ...(ov[it.id] || {}) }),
    patchIssue: (id, p) => setOv(o => ({ ...o, [id]: { ...(o[id] || {}), ...p } })),
  };
  return st || local;
}

// ── Home grid cards ─────────────────────────────────────────────────────
function CCSeriesCard({ s, t, onClick, variant = 'footer' }) {
  const showStats = t.showStats !== false;
  const stats = showStats && (
    <React.Fragment>
      <StatLine icon={<IcoBook size={15} sw={2} />}>{s.owned}/{s.total} owned</StatLine>
      <StatLine icon={<IcoEye size={15} sw={2} />}>{s.read} read</StatLine>
    </React.Fragment>
  );
  if (variant === 'overlay') {
    return (
      <div onClick={onClick} style={{ position: 'relative', borderRadius: 19, overflow: 'hidden', cursor: onClick ? 'pointer' : 'default', boxShadow: 'var(--card-shadow)', aspectRatio: '167/238' }}>
        <CoverArt series={s} height="100%" />
        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, padding: '26px 12px 10px', display: 'flex', flexDirection: 'column', gap: 3, background: 'linear-gradient(0deg, rgba(6,8,8,0.92) 0%, rgba(6,8,8,0.55) 55%, transparent 100%)' }}>
          {stats}
        </div>
      </div>
    );
  }
  if (variant === 'frame') {
    return (
      <div onClick={onClick} style={{ position: 'relative', cursor: onClick ? 'pointer' : 'default', background: 'var(--deep)', border: '3px solid #060808', boxShadow: '6px 6px 0 var(--accent-deep)', overflow: 'hidden' }}>
        <div style={{ aspectRatio: '167/200', position: 'relative' }}>
          <CoverArt series={s} height="100%" />
        </div>
        <div style={{ padding: '8px 10px 10px', display: 'flex', flexDirection: 'column', gap: 3, borderTop: '3px solid #060808', position: 'relative' }}>
          <Halftone color="#fff" opacity={0.05} size={5} />
          {stats}
        </div>
      </div>
    );
  }
  // default: figma card — rounded cover + deep stats footer
  return (
    <div onClick={onClick} style={{ borderRadius: 19, overflow: 'hidden', cursor: onClick ? 'pointer' : 'default', background: 'var(--deep)', boxShadow: 'var(--card-shadow)' }}>
      <div style={{ aspectRatio: '167/200', position: 'relative' }}>
        <CoverArt series={s} height="100%" />
      </div>
      {showStats && (
        <div style={{ padding: '9px 12px 11px', display: 'flex', flexDirection: 'column', gap: 4 }}>
          {stats}
        </div>
      )}
    </div>
  );
}

function CCSeriesRow({ s, t, onClick }) {
  return (
    <div onClick={onClick} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: 10, borderRadius: 16, background: 'var(--surface)', cursor: onClick ? 'pointer' : 'default', boxShadow: 'var(--card-shadow)' }}>
      <div style={{ width: 62, height: 82, borderRadius: 10, overflow: 'hidden', flexShrink: 0 }}>
        <CoverArt series={s} height="100%" />
      </div>
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 4 }}>
        <span style={{ fontWeight: 700, fontSize: 17, letterSpacing: '0.02em' }}>{s.name}</span>
        {t.showStats !== false && (
          <div style={{ display: 'flex', gap: 14 }}>
            <StatLine icon={<IcoBook size={14} sw={2} />} size={12}>{s.owned}/{s.total}</StatLine>
            <StatLine icon={<IcoEye size={14} sw={2} />} size={12}>{s.read} read</StatLine>
          </div>
        )}
      </div>
      <IcoPlay size={16} color="var(--accent)" style={{ flexShrink: 0, marginRight: 6 }} />
    </div>
  );
}

function CCCoverTile({ s, onClick }) {
  return (
    <div onClick={onClick} style={{ position: 'relative', borderRadius: 12, overflow: 'hidden', cursor: onClick ? 'pointer' : 'default', boxShadow: 'var(--card-shadow)', aspectRatio: '3/4' }}>
      <CoverArt series={s} height="100%" />
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, padding: '18px 8px 6px', background: 'linear-gradient(0deg, rgba(6,8,8,0.9) 0%, transparent 100%)', textAlign: 'center' }}>
        <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.04em', color: '#FEF7FF' }}>{s.name}</span>
      </div>
    </div>
  );
}

// ── Screens ─────────────────────────────────────────────────────────────
function ScreenMenu({ t, onEnter }) {
  return (
    <CCScreen t={t} themeOverride="dark" grunge={true}>
      <div style={{ position: 'absolute', inset: 0 }}>
        <img src="figma-style/assets/menu-hero.png" alt="" style={{ width: '100%', height: '52%', objectFit: 'cover', objectPosition: 'top', display: 'block' }} />
        <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: '54%', background: 'linear-gradient(0deg, #131412 2%, rgba(19,20,18,0.25) 45%, rgba(19,20,18,0.35) 100%)' }}></div>
      </div>
      <div style={{ position: 'relative', zIndex: 2, flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'flex-end', padding: '0 32px 64px', textAlign: 'center' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2, filter: 'drop-shadow(0 0 18px rgba(198,41,30,0.55))' }}>
          <ComicLogo text="COMICS" size={44} font={t.font} />
          <ComicLogo text="COLLECTION" size={44} font={t.font} />
        </div>
        <p style={{ margin: '18px 0 0', fontSize: 15, color: 'var(--text2)', lineHeight: 1.5 }}>
          Manage your comic library, track issues, and never miss a release.
        </p>
        <RedButton onClick={onEnter} style={{ marginTop: 30, width: '100%' }}>ENTER COLLECTION</RedButton>
        <button onClick={onEnter} style={{ appearance: 'none', background: 'none', border: 'none', cursor: 'pointer', marginTop: 20, fontFamily: "'Roboto', sans-serif", fontSize: 14, color: 'var(--text)' }}>Continue as Guest</button>
        <div style={{ marginTop: 18, display: 'flex', alignItems: 'center', gap: 7, color: 'var(--muted)', fontSize: 13 }}>
          <IcoGear size={16} /> Settings
        </div>
      </div>
    </CCScreen>
  );
}

function ScreenHome({ t, layout, onOpenSeries, onNav, scroll = false, themeOverride }) {
  const lay = layout || t.layout || '2col';
  const cols = Math.round(t.cols || 2);
  const [q, setQ] = React.useState('');
  const [sort, setSort] = React.useState('az'); // az | owned | complete

  const sortFn = {
    az:       (a, b) => a.name.localeCompare(b.name),
    owned:    (a, b) => b.owned - a.owned,
    complete: (a, b) => (b.owned / b.total) - (a.owned / a.total),
  }[sort];
  const query = q.trim().toLowerCase();
  const match = s => !query || s.name.toLowerCase().includes(query) || (s.house || '').toLowerCase().includes(query);

  const renderGroup = (list) => {
    if (lay === 'list') {
      return (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {list.map(s => <CCSeriesRow key={s.id} s={s} t={t} onClick={onOpenSeries && (() => onOpenSeries(s))} />)}
        </div>
      );
    }
    if (lay === 'covers') {
      return (
        <div style={{ display: 'grid', gridTemplateColumns: `repeat(${cols + 1}, 1fr)`, gap: 10 }}>
          {list.map(s => <CCCoverTile key={s.id} s={s} onClick={onOpenSeries && (() => onOpenSeries(s))} />)}
        </div>
      );
    }
    return (
      <div style={{ display: 'grid', gridTemplateColumns: `repeat(${cols}, 1fr)`, gap: 14 }}>
        {list.map(s => <CCSeriesCard key={s.id} s={s} t={t} variant={t.cardStyle || 'footer'} onClick={onOpenSeries && (() => onOpenSeries(s))} />)}
      </div>
    );
  };

  // Group by publisher house; sort + filter within each group.
  const groups = HOUSES
    .map(h => ({ house: h, items: SERIES.filter(s => (s.house || 'Bonelli') === h && match(s)).sort(sortFn) }))
    .filter(g => g.items.length > 0);

  const sortChip = (id, label) => (
    <button key={id} onClick={() => setSort(id)} style={{
      appearance: 'none', cursor: 'pointer', flexShrink: 0,
      border: '1px solid ' + (sort === id ? 'var(--accent)' : 'var(--line)'),
      background: sort === id ? 'var(--accent)' : 'transparent',
      color: sort === id ? '#FFF' : 'var(--text2)',
      borderRadius: 999, padding: '6px 12px', fontFamily: "'Roboto', sans-serif",
      fontWeight: 600, fontSize: 12, letterSpacing: '0.02em',
    }}>{label}</button>
  );

  return (
    <CCScreen t={t} themeOverride={themeOverride} nav="home" onNav={onNav}>
      <CCTitle t={t} text="COMICS COLLECTION" />
      <div style={{ padding: '0 16px 10px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 14px', borderRadius: 999, background: 'var(--surface)', border: '1px solid var(--line)' }}>
          <span style={{ color: 'var(--muted)', display: 'flex' }}><IcoSearch size={17} /></span>
          <input value={q} onChange={e => setQ(e.target.value)} placeholder="Traži serijal ili izdavača…" style={{
            flex: 1, background: 'none', border: 'none', outline: 'none', minWidth: 0,
            fontFamily: "'Roboto', sans-serif", fontSize: 13.5, color: 'var(--text)',
          }} />
          {q && <button onClick={() => setQ('')} aria-label="Clear" style={{ appearance: 'none', background: 'none', border: 'none', cursor: 'pointer', color: 'var(--muted)', display: 'flex', padding: 0 }}><IcoX size={15} sw={2.4} /></button>}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
          <span style={{ fontSize: 10.5, color: 'var(--muted)', letterSpacing: '0.08em', textTransform: 'uppercase', marginRight: 1 }}>Sort</span>
          {sortChip('az', 'A–Z')}
          {sortChip('owned', 'Najviše')}
          {sortChip('complete', 'Kompletnost')}
        </div>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: scroll ? 'auto' : 'hidden' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 18, padding: '4px 16px 20px' }}>
          {groups.map(g => (
            <div key={g.house}>
              <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', margin: '0 4px 10px' }}>
                <span style={{ fontFamily: "'Roboto', sans-serif", fontWeight: 800, fontSize: 13, letterSpacing: '0.12em', textTransform: 'uppercase', color: 'var(--text)' }}>{g.house}</span>
                <span style={{ fontSize: 11, color: 'var(--muted)' }}>{g.items.length} {g.items.length === 1 ? 'serijal' : 'serijala'}</span>
              </div>
              {renderGroup(g.items)}
            </div>
          ))}
          {groups.length === 0 && <p style={{ textAlign: 'center', color: 'var(--muted)', fontSize: 13, marginTop: 30 }}>Nema rezultata za „{q}"</p>}
        </div>
      </div>
    </CCScreen>
  );
}

function ScreenSeries({ t, series, onOpenEdition, onBack, onNav, scroll = false }) {
  const s = series || SERIES[0];
  return (
    <CCScreen t={t} nav="home" onNav={onNav} grunge={true}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 8px', position: 'relative', zIndex: 2 }}>
        <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 40, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <IcoBack size={22} />
        </button>
        <div style={{ flex: 1, textAlign: 'center', paddingRight: 40 }}>
          <ComicLogo text={s.name} size={30} font={t.font} />
        </div>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: scroll ? 'auto' : 'hidden', display: 'flex', flexDirection: 'column', gap: 12, padding: '8px 16px 20px', position: 'relative', zIndex: 2 }}>
        {s.editions.map(e => (
          <div key={e.id} onClick={onOpenEdition && (() => onOpenEdition(e))} style={{
            display: 'flex', alignItems: 'center', gap: 14, padding: 12, borderRadius: 16,
            background: 'var(--surface)', boxShadow: 'var(--card-shadow)',
            cursor: onOpenEdition ? 'pointer' : 'default',
          }}>
            <div style={{ width: 58, height: 78, borderRadius: 8, overflow: 'hidden', flexShrink: 0 }}>
              <CoverArt series={s} height="100%" />
            </div>
            <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 3 }}>
              <span style={{ fontSize: 12, color: 'var(--text2)' }}>{e.publisher}</span>
              <span style={{ fontWeight: 800, fontSize: 20, letterSpacing: '0.03em' }}>{e.name}</span>
              {t.showStats !== false && (
                <div style={{ display: 'flex', gap: 12, marginTop: 2 }}>
                  <StatLine icon={<IcoBook size={13} sw={2} />} size={11.5}>{e.owned}/{e.total} owned</StatLine>
                  <StatLine icon={<IcoEye size={13} sw={2} />} size={11.5}>{e.read} read</StatLine>
                </div>
              )}
            </div>
            <IcoPlay size={18} color="var(--accent)" style={{ flexShrink: 0, marginRight: 4 }} />
          </div>
        ))}
      </div>
    </CCScreen>
  );
}

function ScreenIssues({ t, st, series, tab = 'EXTRA', onOpenIssue, onTab, onBack, onNav, scroll = false, count = 12 }) {
  const store = useStore(st);
  const title = (series && series.name) || 'DYLAN DOG';
  const tabs = (series && series.editions ? series.editions.map(e => e.name) : ['ORIGINAL', 'EXTRA', 'MAXI', 'GIGANT', 'SPECIAL']);
  const issues = ISSUES.slice(0, scroll ? ISSUES.length : count).map(store.getIssue);
  const toggle = (it, kind) => store.patchIssue(it.id, { [kind]: !it[kind] });
  return (
    <CCScreen t={t} nav="home" onNav={onNav}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 4px' }}>
        <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 40, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <IcoBack size={22} />
        </button>
        <div style={{ flex: 1, textAlign: 'center', paddingRight: 40 }}>
          <ComicLogo text={title} size={30} font={t.font} />
        </div>
      </div>
      <div style={{ display: 'flex', gap: 6, padding: '6px 16px 12px', overflowX: 'hidden' }}>
        {tabs.map(name => (
          <button key={name} onClick={onTab && (() => onTab(name))} style={{
            appearance: 'none', cursor: onTab ? 'pointer' : 'default',
            border: '1px solid ' + (name === tab ? 'var(--accent)' : 'var(--line)'),
            borderRadius: 999, padding: '6px 13px',
            background: name === tab ? 'var(--accent)' : 'transparent',
            color: name === tab ? '#FFF' : 'var(--text2)',
            fontFamily: "'Roboto', sans-serif", fontWeight: 600, fontSize: 12, letterSpacing: '0.03em',
          }}>{name}</button>
        ))}
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: scroll ? 'auto' : 'hidden' }}>
        <div style={{ display: 'grid', gridTemplateColumns: `repeat(${Math.round(t.cols || 2)}, 1fr)`, gap: 12, padding: '0 16px 20px' }}>
          {issues.map(it => (
            <div key={it.id} onClick={onOpenIssue && (() => onOpenIssue(it))} style={{ borderRadius: 12, overflow: 'hidden', background: 'var(--deep)', boxShadow: 'var(--card-shadow)', cursor: onOpenIssue ? 'pointer' : 'default', position: 'relative' }}>
              <div style={{ aspectRatio: '3/4', position: 'relative' }}>
                <CoverArt issue={it} height="100%" />
                <IssueBadges issue={it} onToggle={kind => toggle(it, kind)} />
              </div>
              <div style={{ padding: '7px 9px', background: '#060808' }}>
                <span style={{ fontSize: 12, fontWeight: 600, color: '#FEF7FF', display: 'block', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                  #{it.number} - {it.title}
                </span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </CCScreen>
  );
}

function ScreenIssue({ t, issue, st, onBack, onNav, onStep, scroll = false }) {
  const store = useStore(st);
  const it = store.getIssue(issue || FEATURED);
  const read = !!it.read;
  const owned = it.owned !== false;
  const setRead = v => store.patchIssue(it.id, { read: v });
  const setOwned = v => store.patchIssue(it.id, { owned: v });
  const prev = ISSUES[it.number - 2];
  const next = ISSUES[it.number];
  const chip = (label, target, dir) => (
    <div style={{ flex: 1, minWidth: 0 }}>
      <span style={{ fontSize: 11.5, color: 'var(--muted)', display: 'block', marginBottom: 6 }}>{label}</span>
      {target ? (
        <button onClick={onStep && (() => onStep(target))} style={{
          appearance: 'none', cursor: onStep ? 'pointer' : 'default', width: '100%',
          border: '1px solid var(--line)', borderRadius: 10, padding: '8px 10px',
          background: 'var(--surface)', color: 'var(--text)', textAlign: dir === 'next' ? 'right' : 'left',
          fontFamily: "'Roboto', sans-serif", fontWeight: 600, fontSize: 12,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        }}>#{target.number} {target.title}</button>
      ) : (
        <div style={{ border: '1px dashed var(--line)', borderRadius: 10, padding: '8px 10px', color: 'var(--muted)', fontSize: 12 }}>—</div>
      )}
    </div>
  );
  return (
    <CCScreen t={t} nav="home" onNav={onNav} grunge={true}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 4px', position: 'relative', zIndex: 2 }}>
        <button onClick={onBack} aria-label="Back" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 40, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <IcoBack size={22} />
        </button>
        <div style={{ flex: 1, textAlign: 'center', paddingRight: 40 }}>
          <ComicLogo text={(it.seriesName) || 'DYLAN DOG'} size={28} font={t.font} />
        </div>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: scroll ? 'auto' : 'hidden', padding: '4px 24px 20px', position: 'relative', zIndex: 2 }}>
        <div style={{ width: 218, margin: '6px auto 16px', borderRadius: 12, overflow: 'hidden', boxShadow: '0 14px 34px rgba(0,0,0,0.6)' }}>
          <div style={{ aspectRatio: '3/4', position: 'relative' }}>
            <CoverArt issue={it} height="100%" />
          </div>
        </div>
        <h2 style={{ margin: 0, fontSize: 19, fontWeight: 700, letterSpacing: '0.01em' }}>{((it.seriesName) || 'Dylan Dog')} {it.edition || 'EXTRA'}</h2>
        <p style={{ margin: '3px 0 0', fontSize: 16, color: 'var(--text)', fontWeight: 500 }}>#{it.number} - {it.title}</p>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 9, color: 'var(--text2)', fontSize: 13 }}>
          <span>{it.year}</span>
          <span style={{ color: 'var(--line)' }}>/</span>
          <Stars value={it.rating} size={14} />
          <span style={{ color: 'var(--line)' }}>/</span>
          <span>{(it.writer || 'Sclavi').split(' ').pop()} &amp; {(it.artist || 'Stano').split(' ').pop()}</span>
        </div>
        {owned && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 8, fontSize: 12.5, color: 'var(--text2)' }}>
            <span>Stanje <b style={{ color: 'var(--text)' }}>{it.condition || 4}/5</b></span>
            <span style={{ color: 'var(--line)' }}>·</span>
            <span>Vrijednost <b style={{ color: 'var(--text)' }}>~{it.value || 5} €</b></span>
            {it.dupli && <React.Fragment><span style={{ color: 'var(--line)' }}>·</span><span style={{ color: 'var(--accent)', fontWeight: 700 }}>DUPLI ×2</span></React.Fragment>}
          </div>
        )}
        {!owned && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 8, fontSize: 12.5, color: 'var(--text2)' }}>
            <span style={{ color: 'var(--accent)', fontWeight: 700 }}>TRAŽIM</span>
            <span style={{ color: 'var(--line)' }}>·</span>
            <span>tržišna cijena <b style={{ color: 'var(--text)' }}>~{it.value || 5} €</b></span>
          </div>
        )}
        {owned && it.loaned && (
          <div style={{ marginTop: 10, padding: '8px 12px', borderRadius: 10, background: 'rgba(169,26,26,0.14)', border: '1px solid rgba(169,26,26,0.45)', fontSize: 12.5, color: 'var(--text)' }}>
            Posuđeno: <b>{it.loaned.to}</b> · od {it.loaned.since}
          </div>
        )}
        <p style={{ margin: '12px 0 0', fontSize: 13.5, lineHeight: 1.55, color: 'var(--text2)' }}>
          {it.description || 'The iconic Italian horror comic features the paranormal detective Dylan Dog and his mystery solving adventures.'}
        </p>
        <div style={{ display: 'flex', gap: 12, marginTop: 16 }}>
          {chip('Previous number', prev, 'prev')}
          {chip('Next number', next, 'next')}
        </div>
        <div style={{ display: 'flex', gap: 10, marginTop: 18 }}>
          {read ? (
            <button onClick={() => setRead(false)} style={{
              appearance: 'none', cursor: 'pointer', flex: 1, whiteSpace: 'nowrap',
              border: '1.5px solid #2E9E2E', borderRadius: 999, padding: '12px 8px',
              background: 'rgba(46,158,46,0.14)', color: '#3EC63E',
              fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 12.5, letterSpacing: '0.02em',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7,
            }}><IcoEye size={15} sw={2.4} /> PROČITANO</button>
          ) : (
            <button onClick={() => setRead(true)} style={{
              appearance: 'none', cursor: 'pointer', flex: 1, whiteSpace: 'nowrap',
              border: 'none', borderRadius: 999, padding: '12px 8px',
              background: 'linear-gradient(180deg, color-mix(in oklab, var(--accent) 78%, #fff) 0%, var(--accent) 38%, var(--accent-deep) 100%)',
              boxShadow: '0 4px 14px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,255,255,0.4), inset 0 -2px 4px rgba(0,0,0,0.3)',
              color: '#FFF',
              fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 12.5, letterSpacing: '0.02em',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7,
            }}><IcoEye size={15} sw={2.4} /> NIJE ČITANO</button>
          )}
          {owned ? (
            <button onClick={() => setOwned(false)} style={{
              appearance: 'none', cursor: 'pointer', flex: 1, whiteSpace: 'nowrap',
              border: '1.5px solid #2E9E2E', borderRadius: 999, padding: '12px 8px',
              background: 'rgba(46,158,46,0.14)', color: '#3EC63E',
              fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 12.5, letterSpacing: '0.02em',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7,
            }}><IcoCheck size={14} sw={3} /> U KOLEKCIJI</button>
          ) : (
            <button onClick={() => setOwned(true)} style={{
              appearance: 'none', cursor: 'pointer', flex: 1, whiteSpace: 'nowrap',
              border: '1.5px solid var(--accent)', borderRadius: 999, padding: '12px 8px',
              background: 'transparent', color: 'var(--accent)',
              fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 12.5, letterSpacing: '0.02em',
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7,
            }}>+ DODAJ</button>
          )}
        </div>
      </div>
    </CCScreen>
  );
}

function ScreenUnread({ t, st, onOpenIssue, onNav, scroll = false, count = 7 }) {
  const store = useStore(st);
  const unread = ISSUES.map(store.getIssue).filter(it => it.owned && !it.read);
  const list = unread.slice(0, scroll ? unread.length : count);
  const markRead = it => store.patchIssue(it.id, { read: true });
  return (
    <CCScreen t={t} nav="unread" onNav={onNav}>
      <div style={{ padding: '14px 20px 4px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10 }}>
        <span style={{ color: '#A91A1A', display: 'flex' }}><IcoEye size={26} sw={2.4} /></span>
        <ComicLogo text="NIJE ČITANO" size={28} font={t.font} />
      </div>
      <p style={{ margin: '0 0 10px', textAlign: 'center', fontSize: 12.5, color: 'var(--muted)' }}>
        {unread.length} stripova čeka — dodirni za <b style={{ color: 'var(--text2)' }}>pročitano</b>
      </p>
      <div style={{ flex: 1, minHeight: 0, overflowY: scroll ? 'auto' : 'hidden', display: 'flex', flexDirection: 'column', gap: 9, padding: '0 16px 20px' }}>
        {list.map(it => (
          <div key={it.id} onClick={() => markRead(it)} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 9, borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', cursor: 'pointer' }}>
            <div style={{ width: 46, height: 62, borderRadius: 7, overflow: 'hidden', flexShrink: 0 }}>
              <CoverArt issue={it} height="100%" />
            </div>
            <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
              <span style={{ fontWeight: 700, fontSize: 14.5, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>#{it.number} - {it.title}</span>
              <span style={{ fontSize: 11.5, color: 'var(--text2)' }}>Dylan Dog · EXTRA · {it.year}</span>
            </div>
            <div title="Označi kao pročitano" style={{ width: 34, height: 34, borderRadius: 9, background: '#A91A1A', color: '#FFF', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, boxShadow: '0 2px 6px rgba(0,0,0,0.4)' }}>
              <IcoEye size={18} sw={2.4} />
            </div>
          </div>
        ))}
        {list.length === 0 && <p style={{ textAlign: 'center', color: 'var(--muted)', fontSize: 13, marginTop: 30 }}>Sve pročitano! 🎉</p>}
      </div>
    </CCScreen>
  );
}

function ScreenSettings({ t, setTweak, onNav }) {
  const row = (label, control) => (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: '14px 16px', borderRadius: 14, background: 'var(--surface)' }}>
      <span style={{ fontSize: 14, fontWeight: 600 }}>{label}</span>
      {control}
    </div>
  );
  const seg = (key, options, labels) => (
    <div style={{ display: 'flex', gap: 6 }}>
      {options.map((o, i) => (
        <button key={o} onClick={setTweak && (() => setTweak(key, o))} style={{
          appearance: 'none', cursor: 'pointer', border: '1px solid ' + (t[key] === o ? 'var(--accent)' : 'var(--line)'),
          background: t[key] === o ? 'var(--accent)' : 'transparent',
          color: t[key] === o ? '#FFF' : 'var(--text2)',
          borderRadius: 999, padding: '6px 13px', fontSize: 12, fontWeight: 600, fontFamily: "'Roboto', sans-serif",
        }}>{(labels || options)[i]}</button>
      ))}
    </div>
  );
  return (
    <CCScreen t={t} nav="settings" onNav={onNav}>
      <CCTitle t={t} text="SETTINGS" size={26} />
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, padding: '4px 16px' }}>
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
      </div>
      <p style={{ margin: '14px 20px', fontSize: 12, color: 'var(--muted)', lineHeight: 1.5 }}>
        Postavke mijenjaju izgled svih ekrana — isto kao Tweaks panel.
      </p>
    </CCScreen>
  );
}

function ScreenSearch({ t, onOpenSeries, onOpenIssue, onNav }) {
  const [q, setQ] = React.useState('');
  const hits = SERIES.filter(s => s.name.toLowerCase().includes(q.toLowerCase()));
  const ihits = q.trim().length >= 2
    ? ISSUES.filter(it => ('#' + it.number + ' ' + it.title).toLowerCase().includes(q.trim().toLowerCase())).slice(0, 8)
    : [];
  return (
    <CCScreen t={t} nav="search" onNav={onNav}>
      <CCTitle t={t} text="SEARCH" size={26} />
      <div style={{ padding: '0 16px 14px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '11px 14px', borderRadius: 999, background: 'var(--surface)', border: '1px solid var(--line)' }}>
          <span style={{ color: 'var(--muted)', display: 'flex' }}><IcoSearch size={18} /></span>
          <input value={q} onChange={e => setQ(e.target.value)} placeholder="Naziv serijala, broj…" style={{
            flex: 1, background: 'none', border: 'none', outline: 'none',
            fontFamily: "'Roboto', sans-serif", fontSize: 14, color: 'var(--text)',
          }} />
        </div>
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 10, padding: '0 16px 20px' }}>
        {hits.map(s => <CCSeriesRow key={s.id} s={s} t={t} onClick={onOpenSeries && (() => onOpenSeries(s))} />)}
        {ihits.length > 0 && (
          <span style={{ fontSize: 11, color: 'var(--muted)', letterSpacing: '0.08em', margin: '6px 2px 0', textTransform: 'uppercase' }}>Brojevi — Dylan Dog EXTRA</span>
        )}
        {ihits.map(it => (
          <div key={it.id} onClick={onOpenIssue && (() => onOpenIssue(it))} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 9, borderRadius: 14, background: 'var(--surface)', boxShadow: 'var(--card-shadow)', cursor: onOpenIssue ? 'pointer' : 'default' }}>
            <div style={{ width: 40, height: 54, borderRadius: 6, overflow: 'hidden', flexShrink: 0 }}>
              <CoverArt issue={it} height="100%" />
            </div>
            <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
              <span style={{ fontWeight: 700, fontSize: 14, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>#{it.number} - {it.title}</span>
              <span style={{ fontSize: 11.5, color: 'var(--text2)' }}>{it.year} · {it.owned ? 'u kolekciji' : 'nedostaje'}</span>
            </div>
          </div>
        ))}
        {hits.length === 0 && ihits.length === 0 && <p style={{ textAlign: 'center', color: 'var(--muted)', fontSize: 13, marginTop: 30 }}>Nema rezultata za „{q}"</p>}
      </div>
    </CCScreen>
  );
}

// ── Interactive prototype ───────────────────────────────────────────────
function CCApp({ t, setTweak }) {
  const [route, setRoute] = React.useState({ name: 'menu' });
  const st = useStore(); // shared collection state across all screens
  const nav = id => setRoute({ name: id === 'unread' ? 'library' : id });
  const openIssue = (it, edition, from) => setRoute({ name: 'issue', issue: { ...it, edition, seriesName: it.seriesName || (from && from.series && from.series.name) }, from });
  const backToLib = () => setRoute({ name: 'library' });
  const common = { t, onNav: nav, scroll: true, st };
  switch (route.name) {
    case 'menu':
      return <ScreenMenu t={t} onEnter={() => setRoute({ name: 'home' })} />;
    case 'home':
      return <ScreenHome {...common} onOpenSeries={s => setRoute({ name: 'series', series: s })} />;
    case 'series':
      return <ScreenSeries {...common} series={route.series}
        onBack={() => setRoute({ name: 'home' })}
        onOpenEdition={e => setRoute({ name: 'issues', series: route.series, tab: e.name })} />;
    case 'issues':
      return <ScreenIssues {...common} tab={route.tab} series={route.series}
        onTab={tab => setRoute({ ...route, tab })}
        onBack={() => setRoute({ name: 'series', series: route.series })}
        onOpenIssue={it => openIssue(it, route.tab, route)} />;
    case 'issue':
      return <ScreenIssue {...common} st={st} issue={route.issue}
        onBack={() => setRoute(route.from || { name: 'home' })}
        onStep={it => setRoute({ ...route, issue: { ...it, edition: route.issue.edition } })} />;
    case 'library':
      return <ScreenLibrary t={t} st={st} onNav={nav}
        onGo={name => setRoute({ name, from: { name: 'library' } })} />;
    case 'unread':
      return <ScreenUnread {...common} st={st} onOpenIssue={it => openIssue(it, 'EXTRA', route)} />;
    case 'stats':
      return <ScreenStats t={t} st={st} onNav={nav} onBack={backToLib} />;
    case 'trazim':
      return <ScreenTrazim t={t} st={st} onNav={nav} onBack={backToLib}
        onOpenIssue={it => openIssue(it, 'EXTRA', route)} />;
    case 'dupli':
      return <ScreenDupli t={t} st={st} onNav={nav} onBack={backToLib}
        onOpenIssue={it => openIssue(it, 'EXTRA', route)} />;
    case 'posudeno':
      return <ScreenPosudeno t={t} st={st} onNav={nav} onBack={backToLib}
        onOpenIssue={it => openIssue(it, 'EXTRA', route)} />;
    case 'export':
      return <ScreenExport t={t} st={st} onNav={nav} onBack={backToLib} />;
    case 'settings':
      return <ScreenSettings t={t} setTweak={setTweak} onNav={nav} />;
    case 'search':
      return <ScreenSearch t={t} onNav={nav} onOpenSeries={s => setRoute({ name: 'series', series: s })}
        onOpenIssue={it => openIssue(it, 'EXTRA', { name: 'search' })} />;
    default:
      return <ScreenHome {...common} />;
  }
}

Object.assign(window, {
  useStore, CCSeriesCard, CCSeriesRow, CCCoverTile,
  ScreenMenu, ScreenHome, ScreenSeries, ScreenIssues, ScreenIssue, ScreenUnread, ScreenSettings, ScreenSearch,
  CCApp,
});
