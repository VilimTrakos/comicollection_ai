// cc-scan-review.jsx — R31 · Nakon „DODAJ N STRIPA": potvrda STRIP PO STRIP.
// Odgovor na komentare:
//  (1) na vrhu je uvijek vidljivo ŠTO je skener uhvatio (naslovnica u okviru
//      tražila + prepoznati barkod) — jasno je uz koji primjerak se vežu
//      podaci kad se dodaje više stripova odjednom;
//  (2) klik na „DODAJ N STRIPA" vodi ovamo: za svaki strip se potvrdi stanje
//      (M/VF/F/G/P, zadano VF) — ili prečac „ostale su VF — završi odmah".
// Nakon zadnjeg → Polica (svi označeni kao „u kolekciji" u zajedničkom storeu).

const { ISSUES: RV_ISSUES } = window.CC_DATA;
const RV_COND = { P: 1, G: 2, F: 3, VF: 4, M: 5 };

function RScreenScanReview({ t, st, items, onNav, onAdd, onBack, onDone }) {
  const list = (items && items.length) ? items : [RV_ISSUES[24], RV_ISSUES[19], RV_ISSUES[7]];
  const store = useStore(st);
  const [idx, setIdx] = React.useState(0);
  const [grades, setGrades] = React.useState(() => list.map(() => 'VF'));
  const [done, setDone] = React.useState({});
  const it = list[idx];
  const last = idx === list.length - 1;
  const grade = grades[idx];
  const setGrade = g => setGrades(gs => gs.map((x, i) => (i === idx ? g : x)));
  const saveOne = (i, g) => store.patchIssue(list[i].id, { owned: true, condition: RV_COND[g] || 4 });
  const saveNext = () => {
    saveOne(idx, grade);
    setDone(d => ({ ...d, [it.id]: true }));
    if (last) { onDone && onDone(); } else { setIdx(idx + 1); }
  };
  const finishRest = () => {
    for (let i = idx; i < list.length; i++) saveOne(i, grades[i]);
    onDone && onDone();
  };
  const corner = (i) => {
    const top = i < 2, left = i % 2 === 0, c = '#3EC63E';
    return <div key={i} style={{ position: 'absolute', [top ? 'top' : 'bottom']: 0, [left ? 'left' : 'right']: 0, width: 16, height: 16, zIndex: 1,
      borderTop: top ? '3px solid ' + c : 'none', borderBottom: !top ? '3px solid ' + c : 'none',
      borderLeft: left ? '3px solid ' + c : 'none', borderRight: !left ? '3px solid ' + c : 'none',
      borderTopLeftRadius: top && left ? 6 : 0, borderTopRightRadius: top && !left ? 6 : 0,
      borderBottomLeftRadius: !top && left ? 6 : 0, borderBottomRightRadius: !top && !left ? 6 : 0 }}></div>;
  };
  return (
    <RScreen t={t} nav="home" onNav={onNav} onAdd={onAdd} grunge={true}>
      {/* header: back · naslov · brojač */}
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 12px 2px', position: 'relative', zIndex: 2 }}>
        <button onClick={onBack} aria-label="Natrag na skener" style={{ appearance: 'none', background: 'none', border: 'none', cursor: onBack ? 'pointer' : 'default', color: 'var(--text2)', width: 44, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><IcoBack size={22} /></button>
        <div style={{ flex: 1, textAlign: 'center' }}><ComicLogo text="POTVRDI STANJE" size={24} font={t.font} /></div>
        <div style={{ width: 44, display: 'flex', justifyContent: 'flex-end' }}>
          <span style={{ fontSize: 12.5, fontWeight: 800, color: 'var(--accent)' }}>{idx + 1}/{list.length}</span>
        </div>
      </div>
      {/* progres po stripu */}
      <div style={{ display: 'flex', gap: 5, padding: '4px 20px 0', position: 'relative', zIndex: 2 }}>
        {list.map((x, i) => (
          <div key={x.id} style={{ flex: 1, height: 4, borderRadius: 999, background: done[x.id] ? '#3EC63E' : i === idx ? 'var(--accent)' : 'var(--deep)' }}></div>
        ))}
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '14px 20px 16px', position: 'relative', zIndex: 2, display: 'flex', flexDirection: 'column', gap: 18 }}>
        {/* što je skener uhvatio — kontekst za podatke ispod */}
        <div>
          <RSectionHead label={'Sken ' + (idx + 1) + ' — uhvaćeno kamerom'} />
          <div style={{ position: 'relative', borderRadius: 16, overflow: 'hidden', background: 'radial-gradient(120% 100% at 50% 30%, #262827 0%, #101111 60%, #070808 100%)', padding: '14px 14px', display: 'flex', alignItems: 'center', gap: 14 }}>
            <Halftone color="#fff" opacity={0.05} size={5} />
            <div style={{ position: 'relative', width: 92, flexShrink: 0 }}>
              {[0, 1, 2, 3].map(corner)}
              <div style={{ margin: 7, borderRadius: 6, overflow: 'hidden', transform: 'rotate(2deg)', boxShadow: '0 10px 24px rgba(0,0,0,0.55)' }}>
                <div style={{ aspectRatio: '3/4', position: 'relative' }}><CoverArt issue={it} height="100%" /></div>
              </div>
            </div>
            <div style={{ flex: 1, minWidth: 0, position: 'relative', zIndex: 1 }}>
              <div style={{ display: 'inline-flex', alignItems: 'center', gap: 6, padding: '4px 10px', borderRadius: 999, background: 'rgba(62,198,62,0.16)', border: '1px solid rgba(62,198,62,0.5)', color: '#3EC63E', fontSize: 11.5, fontWeight: 700 }}>
                <IcoCheck size={12} sw={3} /> Barkod · 80500{String(it.number).padStart(2, '0')}
              </div>
              <div style={{ color: '#fff', fontWeight: 800, fontSize: 16, marginTop: 8, letterSpacing: '0.02em' }}>Dylan Dog EXTRA</div>
              <div style={{ color: 'rgba(255,255,255,0.88)', fontSize: 13.5, marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>#{it.number} — {it.title}</div>
              <div style={{ color: 'rgba(255,255,255,0.55)', fontSize: 12, marginTop: 4 }}>{it.year} · procjena ~{it.value || 5} €</div>
            </div>
          </div>
        </div>
        {/* svi iz ovog dodavanja — tap za skok */}
        <div>
          <RSectionHead label="U ovom dodavanju" />
          <div style={{ display: 'flex', gap: 8 }}>
            {list.map((x, i) => {
              const state = done[x.id] ? 'done' : i === idx ? 'now' : 'todo';
              return (
                <button key={x.id} onClick={() => setIdx(i)} title={'#' + x.number + ' — ' + x.title} style={{ appearance: 'none', padding: 0, cursor: 'pointer', position: 'relative', width: 46, borderRadius: 9, overflow: 'hidden', background: 'none', border: state === 'now' ? '2px solid var(--accent)' : '2px solid transparent', opacity: state === 'todo' ? 0.5 : 1 }}>
                  <div style={{ aspectRatio: '3/4', position: 'relative' }}><CoverArt issue={x} height="100%" /></div>
                  {state === 'done' && (
                    <div style={{ position: 'absolute', inset: 0, background: 'rgba(6,8,8,0.55)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#3EC63E' }}><IcoCheck size={20} sw={3} /></div>
                  )}
                </button>
              );
            })}
          </div>
        </div>
        {/* stanje ovog primjerka */}
        <div>
          <RSectionHead label="Stanje primjerka" />
          <GradeChips value={grade} onChange={setGrade} />
          <p style={{ margin: '10px 0 0', fontSize: 12.5, color: 'var(--muted)', lineHeight: 1.5 }}>
            M = kao novo · VF = manji tragovi · F = vidljivo korišten · G = oštećen · P = jako oštećen
          </p>
        </div>
      </div>
      {/* akcije */}
      <div style={{ position: 'relative', zIndex: 2, padding: '0 16px 16px', display: 'flex', flexDirection: 'column', gap: 9 }}>
        <RedButton onClick={saveNext} style={{ width: '100%' }}>{last ? 'SPREMI I ZAVRŠI' : 'SPREMI → SLJEDEĆI (' + (idx + 2) + '/' + list.length + ')'}</RedButton>
        {!last && (
          <button onClick={finishRest} style={{ appearance: 'none', cursor: 'pointer', width: '100%', border: '1.5px solid var(--line)', borderRadius: 999, padding: '12px 8px', background: 'transparent', color: 'var(--text2)', fontFamily: "'Roboto', sans-serif", fontWeight: 700, fontSize: 12.5 }}>
            OSTALE SU VF — ZAVRŠI ODMAH
          </button>
        )}
      </div>
    </RScreen>
  );
}

Object.assign(window, { RScreenScanReview });
