// cc-enterprise-app.jsx — interaktivni ENTERPRISE prototip:
// aktivacija ugovorom → pregled → inventar (pozicije → primjerci → detalj),
// posudbe (članovi, rezervacije, nova posudba), prijem robe, postavke.

function EApp({ t }) {
  const [route, setRoute] = React.useState({ name: 'aktivacija' });
  const go = (name, extra) => setRoute({ name, ...(extra || {}) });
  const nav = id => go(id);
  const onScan = () => go('prijem');
  const common = { t, onNav: nav, onScan };

  switch (route.name) {
    case 'aktivacija':
      return <EScreenActivate t={t} onDone={() => go('pregled')} />;
    case 'pregled':
      return <EScreenDash {...common}
        onOpenLocations={() => go('inventar')}
        onOpenLoans={() => go('posudbe')}
        onOpenRes={() => go('rezervacije')} />;
    case 'inventar':
      return <EScreenLocations {...common} onBack={() => go('pregled')}
        onOpenPos={l => go('pozicija', { pos: l })} />;
    case 'pozicija':
      return <EScreenPosition {...common} pos={route.pos}
        onBack={() => go('inventar')}
        onOpenItem={item => go('primjerak', { item, from: route })} />;
    case 'primjerak':
      return <EScreenItem {...common} item={route.item}
        onBack={() => setRoute(route.from || { name: 'inventar' })}
        onLoan={() => go('novaposudba')} />;
    case 'posudbe':
      return <EScreenLoans {...common} onBack={() => go('pregled')}
        onNew={() => go('novaposudba')}
        onMembers={() => go('clanovi')}
        onReservations={() => go('rezervacije')} />;
    case 'clanovi':
      return <EScreenMembers {...common} onBack={() => go('posudbe')}
        onOpenMember={m => go('clan', { member: m })}
        onNewMember={() => go('noviclan')} />;
    case 'noviclan':
      return <EScreenNewMember {...common} onBack={() => go('clanovi')} onSave={() => go('clanovi')} />;
    case 'clan':
      return <EScreenMember {...common} member={route.member}
        onBack={() => go('clanovi')}
        onNew={() => go('novaposudba')} />;
    case 'rezervacije':
      return <EScreenReservations {...common} onBack={() => go('pregled')} />;
    case 'novaposudba':
      return <EScreenNewLoan t={t} onClose={() => go('posudbe')} onDone={() => go('posudbe')} />;
    case 'prijem':
      return <EScreenReceiving t={t} onClose={() => go('pregled')} />;
    case 'postavke':
      return <EScreenSettingsE {...common} />;
    default:
      return <EScreenDash {...common} />;
  }
}

Object.assign(window, { EApp });
