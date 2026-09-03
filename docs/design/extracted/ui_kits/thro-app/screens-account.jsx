try { (() => {
const D = window.THRDesignSystem_ac73b5;
const {
  TopBar,
  SectionHeader,
  Divider,
  Button,
  Tag,
  Icon,
  IconButton,
  TextField,
  SearchField,
  SegmentedControl,
  FilterChip,
  Progress,
  Confidence,
  PlayerIdentity,
  VerificationState,
  EmptyState,
  Sheet,
  Dialog,
  Snackbar,
  Notification,
  Insight,
  Stat
} = D;

/* Splash / launch */
function Splash({
  go
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      minHeight: '100%',
      background: 'var(--thro-green)',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 28,
      padding: '0 20px'
    }
  }, /*#__PURE__*/React.createElement("img", {
    src: "../../assets/mark-chalk.svg",
    alt: "THR\xD8",
    style: {
      width: 104
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 6,
      alignItems: 'center',
      textAlign: 'center'
    }
  }, /*#__PURE__*/React.createElement("img", {
    src: "../../assets/logo-chalk.svg",
    alt: "",
    style: {
      width: 150
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '600 13px/16px var(--font-ui)',
      letterSpacing: '.09em',
      textTransform: 'uppercase',
      color: 'rgba(247,246,242,.72)'
    }
  }, "From the pub board to the world stage")), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      bottom: 44,
      left: 20,
      right: 20,
      display: 'flex',
      flexDirection: 'column',
      gap: 10
    }
  }, /*#__PURE__*/React.createElement("button", {
    onClick: () => go('onboarding'),
    style: {
      minHeight: 56,
      border: 0,
      borderRadius: 'var(--radius-control)',
      background: 'var(--thro-chalk)',
      color: 'var(--thro-green)',
      font: '700 18px var(--font-ui)',
      cursor: 'pointer'
    }
  }, "Create your THR\xD8 ID"), /*#__PURE__*/React.createElement("button", {
    onClick: () => go('home'),
    style: {
      minHeight: 56,
      borderRadius: 'var(--radius-control)',
      background: 'transparent',
      border: '2px solid rgba(247,246,242,.4)',
      color: 'var(--thro-chalk)',
      font: '700 18px var(--font-ui)',
      cursor: 'pointer'
    }
  }, "Sign in")));
}

/* Onboarding — four steps, no rating promised */
const STEPS = [{
  eyebrow: 'Step 1 of 4',
  title: 'Who are you?',
  body: 'Your THRØ ID follows you across the sport — not a league, not a venue, not a team.'
}, {
  eyebrow: 'Step 2 of 4',
  title: 'Where do you play?',
  body: 'We use this to show you competition you can actually get to.'
}, {
  eyebrow: 'Step 3 of 4',
  title: 'How do you compete?',
  body: 'This only sets your starting point. Your rating comes from results, not from what you tell us.'
}, {
  eyebrow: 'Step 4 of 4',
  title: 'What should we tell you about?',
  body: 'Match calls and results always come through. Everything else is yours to choose.'
}];
function Onboarding({
  go
}) {
  const [i, setI] = React.useState(0);
  const [level, setLevel] = React.useState('league');
  const s = STEPS[i];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      minHeight: '100%'
    }
  }, /*#__PURE__*/React.createElement(TopBar, {
    title: "",
    onBack: () => i ? setI(i - 1) : go('splash')
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 20px'
    }
  }, /*#__PURE__*/React.createElement(Progress, {
    value: i + 1,
    max: 4,
    height: 4
  })), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '24px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 20,
      flex: 1
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, s.eyebrow), /*#__PURE__*/React.createElement("h1", {
    style: {
      font: '800 32px/36px var(--font-ui)',
      letterSpacing: '-.01em',
      color: 'var(--color-text-primary)'
    }
  }, s.title), /*#__PURE__*/React.createElement("p", {
    style: {
      font: '400 17px/25px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      margin: 0,
      textWrap: 'pretty'
    }
  }, s.body)), i === 0 ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 16
    }
  }, /*#__PURE__*/React.createElement(TextField, {
    label: "Display name",
    placeholder: "e.g. Jenson Raper",
    helper: "Shown on your profile, in draws and on results"
  }), /*#__PURE__*/React.createElement(TextField, {
    label: "Email",
    placeholder: "you@example.com",
    type: "email",
    icon: "user"
  })) : i === 1 ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 16
    }
  }, /*#__PURE__*/React.createElement(TextField, {
    label: "Home venue",
    placeholder: "Search venues",
    icon: "map-pin",
    helper: "Optional \u2014 you can add this later"
  }), /*#__PURE__*/React.createElement(TextField, {
    label: "Region",
    value: "North East",
    icon: "globe"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Travel distance"), /*#__PURE__*/React.createElement(SegmentedControl, {
    items: [{
      id: '10',
      label: '10 mi'
    }, {
      id: '25',
      label: '25 mi'
    }, {
      id: '50',
      label: '50 mi'
    }, {
      id: 'any',
      label: 'Any'
    }],
    value: "25",
    onChange: () => {}
  }))) : i === 2 ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, [['social', 'Social', 'I play for fun, mostly at one venue'], ['league', 'League', 'I play in a local or regional league'], ['competitive', 'Competitive', 'I enter open tournaments'], ['elite', 'Elite amateur', 'I compete at regional or national level']].map(([id, t, d]) => /*#__PURE__*/React.createElement("button", {
    key: id,
    onClick: () => setLevel(id),
    "aria-pressed": level === id,
    style: {
      textAlign: 'left',
      padding: 16,
      cursor: 'pointer',
      borderRadius: 'var(--radius-card)',
      background: level === id ? 'var(--color-background-brand-subtle)' : 'transparent',
      border: `1px solid ${level === id ? 'var(--color-border-brand)' : 'var(--color-border-default)'}`,
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 17px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, t), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, d)))) : /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 4
    }
  }, [['Match called', 'Always on', 'locked'], ['Results and rating', 'Always on', 'locked'], ['Events near you', 'On', 'on'], ['Followed players live', 'On', 'on'], ['Development insights', 'On', 'on'], ['Team and league news', 'Off', 'off']].map(([t, v, st]) => /*#__PURE__*/React.createElement("div", {
    key: t,
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      padding: '14px 0',
      borderBottom: '1px solid var(--color-border-default)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 17px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, t), st === 'locked' ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      font: '600 13px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "lock",
    size: 13
  }), v) : /*#__PURE__*/React.createElement(Tag, {
    tone: st === 'on' ? 'brand' : 'neutral'
  }, v)))), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    size: "large",
    fullWidth: true,
    onClick: () => i < 3 ? setI(i + 1) : go('home-new')
  }, i < 3 ? 'Continue' : 'Create my THRØ ID'), i === 2 ? /*#__PURE__*/React.createElement("p", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      margin: 0,
      textAlign: 'center'
    }
  }, "Your first ten rated matches establish your real level. Nothing here is permanent.") : null));
}

/* Settings */
function Settings({
  go
}) {
  const GROUPS = [['Account', [['Display name', 'Jenson Raper', 'user'], ['Email', 'j.raper@example.com', 'user'], ['Sign-in method', 'Passkey', 'lock'], ['Region', 'North East', 'globe']]], ['Competing', [['Home venue', 'Grange WMC', 'map-pin'], ['Teams', 'Grange A', 'users'], ['Travel distance', '25 miles', 'compass'], ['Default format', '501 · Bo9', 'target']]], ['Scoring', [['Checkout suggestions', 'On', 'lightbulb'], ['Haptics', 'On', 'smartphone'], ['Keep screen awake', 'On', 'eye'], ['Offline scoring', 'Always allowed', 'wifi-off']]], ['Notifications', [['Match called', 'Always on', 'bell-ring'], ['Results and rating', 'On', 'trending-up'], ['Events near you', 'On', 'calendar'], ['Followed players', 'On', 'heart']]], ['Accessibility', [['Text size', 'System', 'user'], ['Reduce motion', 'System', 'play'], ['Increase contrast', 'Off', 'eye'], ['Screen reader labels', 'Verbose', 'circle-question-mark']]], ['THRØ', [['Privacy', 'Manage', 'shield-check'], ['Verification', 'THRØ verified', 'circle-check'], ['Export my data', 'Request', 'share'], ['Sign out', '', 'log-out']]]];
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    large: true,
    title: "Settings"
  }), GROUPS.map(([g, items]) => /*#__PURE__*/React.createElement("section", {
    key: g,
    style: {
      padding: '8px 20px 16px'
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: g
  }), items.map(([label, value, icon]) => /*#__PURE__*/React.createElement("button", {
    key: label,
    onClick: () => label === 'Privacy' ? go('privacy') : null,
    style: {
      width: '100%',
      textAlign: 'left',
      background: 'none',
      border: 0,
      borderBottom: '1px solid var(--color-border-default)',
      padding: '14px 0',
      cursor: 'pointer',
      display: 'flex',
      alignItems: 'center',
      gap: 12,
      minHeight: 52
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: icon,
    size: 18,
    color: "var(--color-text-secondary)"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      font: '400 17px var(--font-ui)',
      color: label === 'Sign out' ? 'var(--color-status-error)' : 'var(--color-text-primary)'
    }
  }, label), value ? /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 15px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, value) : null, label !== 'Sign out' ? /*#__PURE__*/React.createElement(Icon, {
    name: "chevron-right",
    size: 16,
    color: "var(--color-text-tertiary)"
  }) : null)))));
}

/* Privacy */
function Privacy({
  go
}) {
  const [vis, setVis] = React.useState('public');
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    eyebrow: "Settings",
    title: "Privacy",
    onBack: () => go('settings')
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '20px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 20
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Profile visibility"
  }), /*#__PURE__*/React.createElement(SegmentedControl, {
    items: [{
      id: 'public',
      label: 'Public'
    }, {
      id: 'players',
      label: 'Players'
    }, {
      id: 'private',
      label: 'Private'
    }],
    value: vis,
    onChange: setVis
  }), /*#__PURE__*/React.createElement("p", {
    style: {
      font: '400 15px/22px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      margin: 0
    }
  }, vis === 'public' ? 'Your name, rating, rank, form and competition history appear on public THRØ pages and in search engines.' : vis === 'players' ? 'Signed-in THRØ players can see your profile. It is excluded from public pages and search engines.' : 'Only opponents, team-mates and organisers of events you enter can see your profile.')), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 4
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "What others can see"
  }), [['Rating and rank', 'On', 'Results are competitive evidence. Hiding your rating also removes you from rankings.'], ['Match history', 'On', 'Individual results, opponents and scores.'], ['Statistics', 'On', 'Averages, checkout percentage, 180s.'], ['Team and venue', 'On', 'Your club affiliations.'], ['Development and Coach', 'Off', 'Never visible to anyone else. This is yours.'], ['Shadow and practice', 'Off', 'Never visible to anyone else.'], ['Location', 'Region only', 'Never your precise location — region at most.']].map(([t, v, d]) => /*#__PURE__*/React.createElement("div", {
    key: t,
    style: {
      padding: '14px 0',
      borderBottom: '1px solid var(--color-border-default)',
      display: 'flex',
      flexDirection: 'column',
      gap: 4
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '600 17px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, t), /*#__PURE__*/React.createElement(Tag, {
    tone: v === 'On' ? 'brand' : 'neutral'
  }, v)), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, d)))), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Your data"
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    fullWidth: true
  }, "Export everything THR\xD8 holds"), /*#__PURE__*/React.createElement(Button, {
    variant: "destructive",
    fullWidth: true
  }, "Delete my THR\xD8 ID"), /*#__PURE__*/React.createElement("p", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      margin: 0
    }
  }, "Deleting your ID removes your profile, statistics and development data. Results of matches you played remain on your opponents' records and in competition archives, without your name attached."))));
}

/* Notifications inbox */
function Notifications({
  go
}) {
  const [f, setF] = React.useState('all');
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    large: true,
    title: "Notifications",
    actions: [{
      icon: 'settings',
      label: 'Notification settings'
    }]
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 20px 16px',
      display: 'flex',
      gap: 8,
      overflowX: 'auto'
    }
  }, /*#__PURE__*/React.createElement(FilterChip, {
    selected: f === 'all',
    onClick: () => setF('all')
  }, "All"), /*#__PURE__*/React.createElement(FilterChip, {
    selected: f === 'action',
    count: 1,
    onClick: () => setF('action')
  }, "Action required"), /*#__PURE__*/React.createElement(FilterChip, {
    selected: f === 'dev',
    onClick: () => setF('dev')
  }, "Development"), /*#__PURE__*/React.createElement(FilterChip, {
    selected: f === 'social',
    onClick: () => setF('social')
  }, "Social")), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '16px 20px 24px'
    }
  }, f === 'action' || f === 'all' ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Now"
  }), /*#__PURE__*/React.createElement(Notification, {
    type: "action",
    title: "Board 14 \u2014 your match has been called",
    body: "North East Open \xB7 Round of 64 \xB7 vs Alex Wilson",
    time: "2m",
    unread: true,
    onClick: () => go('ready')
  })) : null, f === 'all' || f === 'dev' ? /*#__PURE__*/React.createElement("div", {
    style: {
      paddingTop: 16
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Earlier today"
  }), /*#__PURE__*/React.createElement(Notification, {
    type: "milestone",
    title: "Career-best rating: 1,847",
    body: "Up 26 after defeating Alex Wilson, rated 1,903.",
    time: "1h",
    onClick: () => go('rating')
  }), /*#__PURE__*/React.createElement(Notification, {
    type: "development",
    title: "Finishing is your clearest current opportunity",
    body: "Your scoring already matches the 1,900 field.",
    time: "3h",
    onClick: () => go('coach')
  })) : null, f === 'all' || f === 'social' ? /*#__PURE__*/React.createElement("div", {
    style: {
      paddingTop: 16
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "This week"
  }), /*#__PURE__*/React.createElement(Notification, {
    type: "live",
    title: "Harry Nunn is playing now",
    body: "Durham Masters \xB7 Semi final \xB7 Board 4",
    time: "1d",
    onClick: () => go('stream')
  }), /*#__PURE__*/React.createElement(Notification, {
    type: "opportunity",
    title: "Durham Masters Qualifier is open",
    body: "Sun 22 Sep \xB7 18 mi \xB7 Strong challenge",
    time: "2d",
    onClick: () => go('event')
  }), /*#__PURE__*/React.createElement(Notification, {
    type: "social",
    title: "Grange A beat Sunderland B 6\u20133",
    body: "Tyne League \xB7 Division One",
    time: "4d"
  }), /*#__PURE__*/React.createElement(Notification, {
    type: "information",
    title: "Your North East Open result was confirmed",
    body: "Organiser-confirmed by North East Darts Organisation.",
    time: "5d"
  })) : null));
}

/* Search */
function Search({
  go
}) {
  const [q, setQ] = React.useState('north');
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    large: true,
    title: "Search",
    onBack: () => go('discover')
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 20px 16px'
    }
  }, /*#__PURE__*/React.createElement(SearchField, {
    value: q,
    onChange: setQ,
    scope: "players, events, teams and venues"
  })), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), !q ? /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '20px 20px'
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Recent"
  }), ['North East Open', 'Harry Nunn', 'Grange WMC'].map(t => /*#__PURE__*/React.createElement("button", {
    key: t,
    style: {
      width: '100%',
      textAlign: 'left',
      background: 'none',
      border: 0,
      borderBottom: '1px solid var(--color-border-default)',
      padding: '14px 0',
      cursor: 'pointer',
      display: 'flex',
      alignItems: 'center',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "clock",
    size: 16,
    color: "var(--color-text-tertiary)"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      font: '400 17px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, t), /*#__PURE__*/React.createElement(Icon, {
    name: "chevron-right",
    size: 16,
    color: "var(--color-text-tertiary)"
  })))) : /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '20px 20px 24px',
      display: 'flex',
      flexDirection: 'column',
      gap: 24
    }
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Events",
    meta: "3"
  }), [['North East Open', 'Sat 14 Sep · Sunderland'], ['North East Pairs', 'Sat 28 Sep · Gateshead'], ['Northumberland Open', 'Sun 12 Oct · Ashington']].map(([t, d]) => /*#__PURE__*/React.createElement("button", {
    key: t,
    onClick: () => go('event'),
    style: {
      width: '100%',
      textAlign: 'left',
      background: 'none',
      border: 0,
      borderBottom: '1px solid var(--color-border-default)',
      padding: '12px 0',
      cursor: 'pointer',
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 17px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, t), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, d)))), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Leagues",
    meta: "1"
  }), /*#__PURE__*/React.createElement("button", {
    onClick: () => {},
    style: {
      width: '100%',
      textAlign: 'left',
      background: 'none',
      border: 0,
      borderBottom: '1px solid var(--color-border-default)',
      padding: '12px 0',
      cursor: 'pointer',
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 17px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, "North East Super League"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, "4 divisions \xB7 48 teams"))), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Venues",
    meta: "2"
  }), /*#__PURE__*/React.createElement("button", {
    onClick: () => {},
    style: {
      width: '100%',
      textAlign: 'left',
      background: 'none',
      border: 0,
      borderBottom: '1px solid var(--color-border-default)',
      padding: '12px 0',
      cursor: 'pointer',
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 17px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, "North East Sports Bar"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, "Newcastle \xB7 6 boards \xB7 8.4 mi")))));
}
Object.assign(window, {
  Splash,
  Onboarding,
  Settings,
  Privacy,
  Notifications,
  Search
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/thro-app/screens-account.jsx", error: String((e && e.message) || e) }); }
