// cc-ui.jsx — building blocks for the Figma-style Comics Collection design
// Palette lifted from the user's Figma: near-black #131412, red #C6291E /
// #BC221B, tan #B7A88F, light surfaces #FEF7FF / #ECE6F0, green #3EC63E.

const CC_ACCENTS = {
  crvena: { accent: '#C6291E', accentDeep: '#8E1410' },
  oker:   { accent: '#B7892E', accentDeep: '#7C5A18' },
  plava:  { accent: '#2A5FA8', accentDeep: '#173E74' },
};

function ccVars(t, themeOverride) {
  const theme = themeOverride || (t && t.theme) || 'dark';
  const acc = CC_ACCENTS[(t && t.accent) || 'crvena'] || CC_ACCENTS.crvena;
  const dark = theme === 'dark';
  return {
    '--bg':      dark ? '#131412' : '#FEF7FF',
    '--bg2':     dark ? '#0C0D0E' : '#F3EDF7',
    '--surface': dark ? '#1C1D1B' : '#ECE6F0',
    '--deep':    dark ? '#060808' : '#E2DCE6',
    '--nav':     dark ? '#121211' : '#ECE6F0',
    '--text':    dark ? '#FEF7FF' : '#1D1B20',
    '--text2':   dark ? '#B7A88F' : '#49454F',
    '--muted':   dark ? '#7C7C7C' : '#7C7B7D',
    '--line':    dark ? 'rgba(183,168,143,0.16)' : '#CAC4D0',
    '--accent':  acc.accent,
    '--accent-deep': acc.accentDeep,
    '--green':   '#3EC63E',
    '--card-shadow': dark ? '0 6px 18px rgba(0,0,0,0.5)' : '0 4px 14px rgba(29,27,32,0.14)',
    colorScheme: dark ? 'dark' : 'light',
  };
}

// ── Icons (simple geometric strokes) ────────────────────────────────────
const ccI = (paths, vb = '0 0 24 24') => ({ size = 22, color = 'currentColor', fill = 'none', sw = 2, style }) => (
  <svg width={size} height={size} viewBox={vb} fill={fill} stroke={color} strokeWidth={sw}
    strokeLinecap="round" strokeLinejoin="round" style={style}>{paths}</svg>
);

const IcoHome   = ccI(<path d="M3.5 10.5 12 3.5l8.5 7V20a1 1 0 0 1-1 1h-5v-6h-5v6h-5a1 1 0 0 1-1-1z" />);
const IcoBook   = ccI(<g><path d="M12 6.2C10.2 4.9 7.3 4.7 4.5 5.5V19c2.8-.8 5.7-.6 7.5.7 1.8-1.3 4.7-1.5 7.5-.7V5.5c-2.8-.8-5.7-.6-7.5.7z" /><path d="M12 6.2v13.5" /></g>);
const IcoGear   = ccI(<g><circle cx="12" cy="12" r="3.2" /><path d="M12 2.8v2.6M12 18.6v2.6M2.8 12h2.6M18.6 12h2.6M5.5 5.5l1.8 1.8M16.7 16.7l1.8 1.8M18.5 5.5l-1.8 1.8M7.3 16.7l-1.8 1.8" /></g>);
const IcoSearch = ccI(<g><circle cx="10.5" cy="10.5" r="6" /><path d="m15.2 15.2 5 5" /></g>);
const IcoEye    = ccI(<g><path d="M2.5 12C4.4 7.8 8 5.2 12 5.2S19.6 7.8 21.5 12c-1.9 4.2-5.5 6.8-9.5 6.8S4.4 16.2 2.5 12z" /><circle cx="12" cy="12" r="2.8" /></g>);
const IcoCheck  = ccI(<path d="m4.5 12.5 5 5L19.5 7" />, '0 0 24 24');
const IcoX      = ccI(<path d="M6 6l12 12M18 6 6 18" />);
const IcoPlay   = ({ size = 20, color = 'currentColor', style }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill={color} style={style}><path d="M7 4.5 19 12 7 19.5z" /></svg>
);
const IcoBack   = ccI(<path d="M14.5 5 8 12l6.5 7" sw="2.4" />);
const IcoStar   = ({ size = 18, color = '#E8C547', off = false, style }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" style={style}
    fill={off ? 'none' : color} stroke={color} strokeWidth="1.6" strokeLinejoin="round">
    <path d="M12 3.2 14.7 9l6.1.6-4.6 4.1 1.3 6-5.5-3.2L6.5 19.7l1.3-6L3.2 9.6 9.3 9z" />
  </svg>
);

// ── Texture helpers ─────────────────────────────────────────────────────
const CC_NOISE = "url('data:image/svg+xml;utf8,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%22160%22 height=%22160%22><filter id=%22n%22><feTurbulence type=%22fractalNoise%22 baseFrequency=%220.9%22 numOctaves=%222%22/></filter><rect width=%22160%22 height=%22160%22 filter=%22url(%23n)%22 opacity=%220.5%22/></svg>')";

function GrungeBg({ red = true }) {
  // layered glow + noise, like the textured screens in the Figma mockups
  return (
    <div aria-hidden="true" style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
      {red && <div style={{
        position: 'absolute', inset: 0,
        background: 'radial-gradient(90% 50% at 15% 0%, rgba(140,30,20,0.35) 0%, transparent 60%), radial-gradient(90% 55% at 90% 100%, rgba(140,30,20,0.3) 0%, transparent 60%)',
      }} />}
      <div style={{ position: 'absolute', inset: 0, backgroundImage: CC_NOISE, opacity: 0.5, mixBlendMode: 'overlay' }}></div>
    </div>
  );
}

function Halftone({ color = '#000', opacity = 0.18, size = 7 }) {
  return <div aria-hidden="true" style={{
    position: 'absolute', inset: 0, pointerEvents: 'none', opacity,
    backgroundImage: `radial-gradient(${color} 1.1px, transparent 1.2px)`,
    backgroundSize: `${size}px ${size}px`,
  }}></div>;
}

// ── Comic logotype ──────────────────────────────────────────────────────
function ComicLogo({ text, size = 32, font = 'roboto', color, style }) {
  if (font === 'comic') {
    return (
      <span style={{
        fontFamily: "'Bangers', cursive",
        fontSize: size * 1.18, lineHeight: 1, letterSpacing: '0.04em',
        color: color || '#F2D02B',
        textShadow: '2px 2px 0 #1A0A08, -1.5px -1.5px 0 #1A0A08, 1.5px -1.5px 0 #1A0A08, -1.5px 1.5px 0 #1A0A08, 4px 5px 0 rgba(140,20,12,0.85)',
        ...style,
      }}>{text}</span>
    );
  }
  return (
    <span style={{
      fontFamily: "'Roboto', sans-serif", fontWeight: 800,
      fontSize: size, lineHeight: 1.1, letterSpacing: '0.01em',
      color: color || 'var(--accent)', textTransform: 'uppercase',
      ...style,
    }}>{text}</span>
  );
}

// ── Placeholder cover (stylized, for series w/o real art) ──────────────
function PhCover({ name, bg, ink, height = '100%', radius = 0 }) {
  return (
    <div style={{
      position: 'relative', width: '100%', height, overflow: 'hidden',
      borderRadius: radius, background: bg,
      display: 'flex', alignItems: 'flex-start', justifyContent: 'center',
    }}>
      <div style={{
        position: 'absolute', inset: 0,
        background: 'linear-gradient(155deg, rgba(255,255,255,0.16) 0%, transparent 45%, rgba(0,0,0,0.35) 100%)',
      }}></div>
      <Halftone color="#000" opacity={0.22} size={6} />
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0, height: '34%',
        background: 'linear-gradient(0deg, rgba(0,0,0,0.45) 0%, transparent 100%)',
      }}></div>
      <span style={{
        position: 'relative', marginTop: '9%', padding: '0 8%',
        fontFamily: "'Bangers', cursive", fontSize: 30, letterSpacing: '0.05em',
        lineHeight: 0.95, textAlign: 'center', color: ink,
        textShadow: '2px 2px 0 rgba(0,0,0,0.85), -1px -1px 0 rgba(0,0,0,0.85), 1px -1px 0 rgba(0,0,0,0.85), -1px 1px 0 rgba(0,0,0,0.85)',
        transform: 'rotate(-2deg)',
      }}>{name}</span>
      <span style={{
        position: 'absolute', bottom: '7%', left: 0, right: 0, textAlign: 'center',
        fontFamily: "'JetBrains Mono', monospace", fontSize: 9, letterSpacing: '0.12em',
        color: 'rgba(255,255,255,0.75)', textTransform: 'uppercase',
      }}>cover art</span>
    </div>
  );
}

function CoverArt({ series, issue, height = '100%', radius = 0 }) {
  const src = issue ? issue.cover : series && series.cover;
  if (src) {
    return <img src={src} alt="" style={{
      display: 'block', width: '100%', height, objectFit: 'cover',
      objectPosition: 'top', borderRadius: radius,
    }} />;
  }
  if (issue) {
    return <PhCover name={`#${issue.number}`} bg={issue.phBg} ink="#F2D02B" height={height} radius={radius} />;
  }
  return <PhCover name={series.name} bg={series.ph.bg} ink={series.ph.ink} height={height} radius={radius} />;
}

// ── Small bits ──────────────────────────────────────────────────────────
function StatLine({ icon, children, size = 13 }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 7, color: 'var(--text2)', fontSize: size, fontWeight: 500, fontFamily: "'Roboto', sans-serif" }}>
      {icon}
      <span>{children}</span>
    </div>
  );
}

function RedButton({ children, small = false, onClick, style }) {
  return (
    <button onClick={onClick} style={{
      appearance: 'none', border: 'none', cursor: 'pointer',
      borderRadius: 999, padding: small ? '9px 22px' : '13px 40px',
      fontFamily: "'Roboto', sans-serif", fontWeight: 700,
      fontSize: small ? 13 : 16, letterSpacing: '0.02em', color: '#FFF',
      background: 'linear-gradient(180deg, color-mix(in oklab, var(--accent) 78%, #fff) 0%, var(--accent) 38%, var(--accent-deep) 100%)',
      boxShadow: '0 4px 14px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,255,255,0.4), inset 0 -2px 4px rgba(0,0,0,0.3)',
      ...style,
    }}>{children}</button>
  );
}

function Stars({ value = 4, size = 16 }) {
  return (
    <div style={{ display: 'flex', gap: 2 }}>
      {[1, 2, 3, 4, 5].map(i => <IcoStar key={i} size={size} off={i > value} />)}
    </div>
  );
}

// Status badge pair used on issue cards (read / owned), per Figma Tema2.
// When onToggle is supplied the badges become tap targets: tapping marks the
// issue read/unread or gotten/missing without opening the detail screen.
function IssueBadges({ issue, onToggle }) {
  const tap = kind => e => { e.stopPropagation(); onToggle && onToggle(kind); };
  const b = (bg, child, title, kind) => (
    <div title={title} onClick={onToggle ? tap(kind) : undefined} style={{
      width: 24, height: 24, borderRadius: 6, background: bg,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      color: '#FFF', boxShadow: '0 2px 5px rgba(0,0,0,0.45)',
      cursor: onToggle ? 'pointer' : 'default',
    }}>{child}</div>
  );
  return (
    <div style={{ position: 'absolute', top: 6, right: 6, display: 'flex', gap: 5 }}>
      {issue.read
        ? b('#2E9E2E', <IcoEye size={14} sw={2.4} />, 'Pročitano — dodirni za nepročitano', 'read')
        : b('#A91A1A', <IcoEye size={14} sw={2.4} />, 'Nije čitano — dodirni za pročitano', 'read')}
      {issue.owned
        ? b('#2E9E2E', <IcoCheck size={13} sw={3} />, 'Imam — dodirni za nemam', 'owned')
        : b('#A91A1A', <IcoX size={13} sw={3} />, 'Nemam — dodirni za nabavljeno', 'owned')}
    </div>
  );
}

// ── Phone chrome ────────────────────────────────────────────────────────
function CCStatusBar() {
  return (
    <div style={{
      height: 34, flexShrink: 0, position: 'relative', zIndex: 5,
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '0 24px', fontFamily: "'Roboto', sans-serif",
      fontWeight: 500, fontSize: 14, color: 'var(--text2)',
      background: 'linear-gradient(0deg, rgba(255,255,255,0) 0%, rgba(0,0,0,0.25) 100%)',
    }}>
      <span>9:30</span>
      <div style={{
        position: 'absolute', left: '50%', top: 7, transform: 'translateX(-50%)',
        width: 20, height: 20, borderRadius: '50%', background: '#060808',
        boxShadow: 'inset 0 0 0 1.5px rgba(255,255,255,0.08)',
      }}></div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <svg width="15" height="11" viewBox="0 0 17 12.5" fill="currentColor"><path d="M 8.5 0 C 5.1 0 2.125 1.313 0 3.375 L 8.5 12.5 L 17 3.375 C 14.875 1.313 11.9 0 8.5 0 Z" /></svg>
        <svg width="13" height="11" viewBox="0 0 15 13" fill="currentColor"><path d="M 15 0 L 0 13 L 15 13 L 15 0 Z" /></svg>
        <svg width="9" height="13" viewBox="0 0 8 14" fill="currentColor"><path d="M 5.5 0 L 2.5 0 L 2.5 1.4 L 1 1.4 C 0.448 1.4 0 1.87 0 2.45 L 0 12.95 C 0 13.53 0.448 14 1 14 L 7 14 C 7.552 14 8 13.53 8 12.95 L 8 2.45 C 8 1.87 7.552 1.4 7 1.4 L 5.5 1.4 L 5.5 0 Z" /></svg>
      </div>
    </div>
  );
}

function CCNavBar({ active = 'home', onNav }) {
  const items = [
    { id: 'home',   Ico: IcoHome,   label: 'Home' },
    { id: 'unread', Ico: IcoBook,   label: 'Library' },
    { id: 'settings', Ico: IcoGear, label: 'Settings' },
    { id: 'search', Ico: IcoSearch, label: 'Search' },
  ];
  return (
    <div style={{
      height: 65, flexShrink: 0, background: 'var(--nav)',
      borderTop: '1px solid var(--line)',
      display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)',
      alignItems: 'center', justifyItems: 'center', position: 'relative', zIndex: 5,
    }}>
      {items.map(({ id, Ico, label }) => (
        <button key={id} aria-label={label} onClick={onNav ? () => onNav(id) : undefined} style={{
          appearance: 'none', background: 'none', border: 'none', cursor: onNav ? 'pointer' : 'default',
          width: 56, height: 48, display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: active === id ? 'var(--accent)' : 'var(--muted)',
        }}>
          <Ico size={26} sw={active === id ? 2.4 : 2} />
        </button>
      ))}
    </div>
  );
}

// Screen shell: 393×852 phone surface in figma's gray device ring
function CCScreen({ children, t, themeOverride, nav, onNav, grunge = false, statusBar = true }) {
  return (
    <div className="cc-screen" style={{
      ...ccVars(t, themeOverride),
      width: 393, height: 852, borderRadius: 28, overflow: 'hidden',
      background: 'var(--bg)', boxShadow: '0 0 0 8px #CAC4D0',
      display: 'flex', flexDirection: 'column', position: 'relative',
      fontFamily: "'Roboto', sans-serif", color: 'var(--text)',
    }}>
      {grunge && <GrungeBg />}
      {statusBar && <CCStatusBar />}
      <div style={{ flex: 1, minHeight: 0, position: 'relative', display: 'flex', flexDirection: 'column' }}>
        {children}
      </div>
      {nav !== undefined && <CCNavBar active={nav} onNav={onNav} />}
    </div>
  );
}

function CCTitle({ t, text, size = 30 }) {
  return (
    <div style={{ padding: '14px 20px 12px', textAlign: 'center', position: 'relative', zIndex: 2 }}>
      <ComicLogo text={text} size={size} font={t.font} />
    </div>
  );
}

Object.assign(window, {
  ccVars, CC_ACCENTS, GrungeBg, Halftone, ComicLogo, PhCover, CoverArt,
  StatLine, RedButton, Stars, IssueBadges, CCStatusBar, CCNavBar, CCScreen, CCTitle,
  IcoHome, IcoBook, IcoGear, IcoSearch, IcoEye, IcoCheck, IcoX, IcoPlay, IcoBack, IcoStar,
});
