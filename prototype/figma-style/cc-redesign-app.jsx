// cc-redesign-app.jsx — interaktivni prototip redizajna: FAB nav,
// Home dashboard, Polica, dodavanje (sheet → sken → potvrda), uređivanje,
// hub funkcije, pretraga i postavke. Sve rute koriste zajednički store.

function RApp({ t, setTweak }) {
  const [route, setRoute] = React.useState({ name: 'welcome' });
  const st = useStore();
  const go = (name, extra) => setRoute({ name, ...(extra || {}) });
  const nav = id => go(id === 'home' ? 'home' : id); // home | polica | search | settings
  const onAdd = () => go('add');
  const openIssue = (it, from) => go('issue', { issue: it, from: from || route });
  const backTo = r => () => setRoute(r);
  const common = { t, onNav: nav, onAdd, st };

  switch (route.name) {
    case 'welcome':
      return <RScreenWelcome t={t} onEnter={() => go('mode')} onGuest={() => go('home')} />;
    case 'mode':
      return <RScreenModePick t={t} onBack={backTo({ name: 'welcome' })}
        onPersonal={() => go('login')}
        onEnterprise={() => go('enterprise')} />;
    case 'enterprise':
      return <EApp t={t} />;
    case 'login':
      return <RScreenLoginR t={t} onBack={backTo({ name: 'mode' })} onLogin={() => go('home')} onRegister={() => go('register')} />;
    case 'register':
      return <RScreenRegisterR t={t} onBack={backTo({ name: 'login' })} onDone={() => go('empty')} />;
    case 'empty':
      return <RScreenEmptyR t={t} onNav={nav} onAdd={onAdd} onImport={() => go('import')} />;
    case 'import':
      return <RScreenImportR {...common} onBack={backTo({ name: 'empty' })} onDone={() => go('polica')} />;
    case 'conflict':
      return <RScreenConflictR t={t} onKeepLocal={backTo({ name: 'settings' })} onKeepServer={backTo({ name: 'settings' })} />;
    case 'home':
      return <RScreenHome {...common}
        onOpenReleases={() => go('releases')}
        onOpenReading={() => { const u = CC_DATA.UNREAD[0]; u && openIssue(u, { name: 'home' }); }}
        onOpenTrazim={() => go('trazim', { from: { name: 'home' } })}
        onOpenSeries={s => go('series', { series: s })} />;
    case 'polica':
      return <RScreenShelf {...common}
        onOpenSeries={s => go('series', { series: s })}
        onHub={id => go(id, { from: { name: 'polica' } })} />;
    case 'series':
      return <RScreenSeriesR {...common} series={route.series}
        onBack={backTo({ name: 'polica' })}
        onOpenEdition={e => go('issues', { series: route.series, tab: e.name })} />;
    case 'issues':
      return <RScreenCompact {...common}
        title={(route.series ? route.series.name : 'DYLAN DOG') + ' · ' + (route.tab || 'EXTRA')}
        onBack={backTo({ name: 'series', series: route.series })}
        onOpenIssue={it => openIssue(it, route)} />;
    case 'issue':
      return <RScreenIssueR {...common} issue={route.issue}
        onBack={backTo(route.from || { name: 'polica' })}
        onEdit={() => go('edit', { issue: route.issue, from: route })}
        onStep={it => go('issue', { issue: it, from: route.from })} />;
    case 'edit':
      return <RScreenEditR {...common} issue={route.issue}
        onBack={backTo(route.from || { name: 'polica' })}
        onSave={backTo(route.from || { name: 'polica' })} />;
    case 'add':
      return <RAddSheet t={t}
        onClose={backTo({ name: 'home' })}
        onScan={() => go('scan')}
        onManual={() => go('manual')}
        onSearch={() => go('search')}
        onBatch={() => go('batch')} />;
    case 'scan':
      return <RScreenFastScan t={t}
        onBack={backTo({ name: 'home' })}
        onEdit={() => go('confirm')}
        onDone={list => go('review', { scanned: list })} />;
    case 'review':
      return <RScreenScanReview {...common} items={route.scanned}
        onBack={backTo({ name: 'scan' })}
        onDone={() => go('polica')} />;
    case 'confirm':
      return <RScreenConfirm {...common}
        onBack={() => go('search')}
        onSave={() => go('photo')} />;
    case 'photo':
      return <RScreenPhotoR t={t} onDone={() => go('scan')} onSkip={() => go('scan')} />;
    case 'batch':
      return <RScreenBatchR {...common} onBack={backTo({ name: 'add' })} onSave={() => go('polica')} />;
    case 'hub':
      return <RScreenHub {...common}
        onBack={backTo({ name: 'polica' })}
        onGo={id => go(id, { from: { name: 'hub' } })} />;
    case 'trade':
      return <RScreenTradeR {...common} onBack={backTo({ name: 'dupli', from: { name: 'polica' } })} />;
    case 'manual':
      return <RScreenManual {...common}
        onBack={backTo({ name: 'add' })}
        onSave={() => go('polica')} />;
    case 'search':
      return <RScreenSearchR {...common}
        onOpenSeries={s => go('series', { series: s })}
        onOpenIssue={it => openIssue(it, { name: 'search' })} />;
    case 'settings':
      return <RScreenSettingsR t={t} setTweak={setTweak} onNav={nav} onAdd={onAdd} onSyncNow={() => go('conflict')} onLogout={() => go('welcome')} />;
    case 'stats':
      return <RScreenStatsR {...common} onBack={backTo(route.from || { name: 'polica' })} />;
    case 'unread':
      return <RScreenUnreadR {...common} onBack={backTo(route.from || { name: 'polica' })}
        onOpenIssue={it => openIssue(it, route)} />;
    case 'trazim':
      return <RScreenTrazimR {...common} onBack={backTo(route.from || { name: 'polica' })}
        onOpenIssue={it => openIssue(it, route)} />;
    case 'dupli':
      return <RScreenDupliR {...common} onBack={backTo(route.from || { name: 'polica' })}
        onOpenIssue={it => openIssue(it, route)} onTrade={() => go('trade')} />;
    case 'posudeno':
      return <RScreenPosudenoR {...common} onBack={backTo(route.from || { name: 'polica' })}
        onOpenIssue={it => openIssue(it, route)} />;
    case 'releases':
      return <RScreenReleasesR {...common} onBack={backTo(route.from || { name: 'home' })} />;
    case 'export':
      return <RScreenExportR {...common} onBack={backTo(route.from || { name: 'polica' })} />;
    default:
      return <RScreenHome {...common} />;
  }
}

Object.assign(window, { RApp });
