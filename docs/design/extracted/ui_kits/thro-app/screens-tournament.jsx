try { (() => {
const D = window.THRDesignSystem_ac73b5;
const {
  TopBar,
  SectionHeader,
  Divider,
  Button,
  Tag,
  Icon,
  PlayerRow,
  PlayerIdentity,
  Progress,
  Bracket,
  TournamentProgress,
  SegmentedControl,
  SearchField,
  FilterChip,
  LiveIndicator,
  VerificationState,
  Snackbar,
  EmptyState,
  SyncState,
  Sheet,
  Dialog
} = D;
function CheckIn({
  go
}) {
  const [state, setState] = React.useState('open');
  const [confirm, setConfirm] = React.useState(false);
  const done = state === 'done';
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    eyebrow: "North East Open",
    title: "Check-in",
    onBack: () => go('event'),
    actions: [{
      icon: 'circle-question-mark',
      label: 'Check-in help'
    }]
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '24px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 20
    }
  }, !done ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 6
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow",
    style: {
      color: 'var(--color-status-live)'
    }
  }, "Check-in closes in"), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '700 96px/88px var(--font-sport)',
      letterSpacing: '-.03em',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, "18:42"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 15px/22px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, "Closes at 11:30. The draw is made immediately after. Players not checked in are withdrawn.")), /*#__PURE__*/React.createElement(Progress, {
    label: "Field checked in",
    value: 74,
    max: 96,
    valueLabel: "74 of 96"
  }), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "You are checking in as"), /*#__PURE__*/React.createElement(PlayerIdentity, {
    name: "Jenson Raper",
    rating: 1847,
    team: "Grange A",
    verified: true,
    size: "medium"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, "Entry paid \xB7 \xA318 \xB7 12 September")), /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    size: "large",
    fullWidth: true,
    onClick: () => setConfirm(true)
  }, "I'm here \u2014 check me in"), /*#__PURE__*/React.createElement("button", {
    onClick: () => go('event'),
    style: {
      background: 'none',
      border: 0,
      padding: 0,
      cursor: 'pointer',
      font: '600 15px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      textAlign: 'center'
    }
  }, "Withdraw from this event")) : /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 10
    }
  }, /*#__PURE__*/React.createElement(Tag, {
    tone: "success",
    icon: "circle-check"
  }, "Checked in"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '800 32px/36px var(--font-ui)',
      letterSpacing: '-.01em',
      color: 'var(--color-text-primary)'
    }
  }, "You're in the draw"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 17px/25px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, "The draw is published at 11:30. You'll be notified with your first-round opponent and board.")), /*#__PURE__*/React.createElement(SyncState, {
    state: "synced",
    detail: "Check-in confirmed by the organiser at 11:12."
  }), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "What happens next"
  }), [['11:30', 'Draw published'], ['11:45', 'Board assignments'], ['12:30', 'First matches called']].map(([t, l]) => /*#__PURE__*/React.createElement("div", {
    key: t,
    style: {
      display: 'flex',
      gap: 16,
      alignItems: 'baseline'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      width: 52,
      font: '600 17px var(--font-sport)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, t), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 15px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, l)))), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    size: "large",
    fullWidth: true,
    onClick: () => go('draw')
  }, "View the draw"))), confirm ? /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'sticky',
      bottom: 0,
      padding: '0 20px 20px'
    }
  }, /*#__PURE__*/React.createElement(Dialog, {
    title: "Check in for the North East Open?",
    message: "You must be at the venue. False check-in can lead to withdrawal from the event.",
    confirmLabel: "I'm at the venue",
    cancelLabel: "Not yet",
    onCancel: () => setConfirm(false),
    onConfirm: () => {
      setConfirm(false);
      setState('done');
    }
  })) : null);
}
function DrawRelease({
  go
}) {
  const [view, setView] = React.useState('you');
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    eyebrow: "North East Open",
    title: "The draw",
    onBack: () => go('checkin'),
    actions: [{
      icon: 'share',
      label: 'Share the draw'
    }]
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '20px 20px 12px'
    }
  }, /*#__PURE__*/React.createElement(SegmentedControl, {
    items: [{
      id: 'you',
      label: 'Your path'
    }, {
      id: 'round',
      label: 'Round of 64'
    }, {
      id: 'full',
      label: 'Full draw'
    }],
    value: view,
    onChange: setView
  })), view === 'you' ? /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '8px 20px 24px',
      display: 'flex',
      flexDirection: 'column',
      gap: 20
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--thro-ink)',
      margin: '0 -20px',
      padding: '24px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    },
    "data-theme": "dark"
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Your first match"), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '700 72px/68px var(--font-sport)',
      letterSpacing: '-.02em',
      color: 'var(--thro-chalk)'
    }
  }, "BOARD 14"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 17px var(--font-ui)',
      color: '#A7ADAA'
    }
  }, "Round of 64 \xB7 vs Alex Wilson \xB7 1,903"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px var(--font-ui)',
      color: '#A7ADAA'
    }
  }, "Called at approximately 12:30"), /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    size: "large",
    fullWidth: true,
    onClick: () => go('ready')
  }, "Go to match")), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "If you progress",
    meta: "Seeded projection"
  }), /*#__PURE__*/React.createElement(TournamentProgress, {
    rounds: [{
      round: 'Round of 64',
      opponent: 'Alex Wilson · 1,903',
      state: 'active'
    }, {
      round: 'Round of 32',
      opponent: 'Winner of Kerr v Patel',
      state: 'future'
    }, {
      round: 'Round of 16',
      opponent: 'Projected: H. Nunn · 1,923',
      state: 'future'
    }, {
      round: 'Quarter final',
      opponent: 'Projected: L. Okafor · 1,948',
      state: 'future'
    }],
    nextLabel: "Board 14 \xB7 approximately 12:30"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 10,
      alignItems: 'flex-start'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "info",
    size: 16,
    color: "var(--color-text-secondary)",
    style: {
      marginTop: 2
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, "Projections use current ratings only. They are context, not a prediction."))) : view === 'round' ? /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '8px 20px 24px'
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Round of 64",
    meta: "32 matches"
  }), /*#__PURE__*/React.createElement(PlayerRow, {
    rank: 1,
    name: "L. Okafor",
    rating: 1948,
    team: "Riverside",
    meta: "Board 1"
  }), /*#__PURE__*/React.createElement(PlayerRow, {
    rank: 2,
    name: "H. Nunn",
    rating: 1923,
    team: "Grange A",
    verified: true,
    meta: "Board 2"
  }), /*#__PURE__*/React.createElement(PlayerRow, {
    rank: 7,
    name: "A. Wilson",
    rating: 1903,
    team: "Sunderland B",
    meta: "Board 14"
  }), /*#__PURE__*/React.createElement(PlayerRow, {
    rank: 12,
    name: "J. Raper",
    rating: 1847,
    team: "Grange A",
    verified: true,
    meta: "Board 14"
  }), /*#__PURE__*/React.createElement(PlayerRow, {
    rank: 14,
    name: "D. Kerr",
    rating: 1839,
    team: "Boro Legion",
    meta: "Board 9"
  }), /*#__PURE__*/React.createElement(PlayerRow, {
    rank: 19,
    name: "S. Patel",
    rating: 1812,
    team: "Tyne Arms",
    meta: "Board 9"
  })) : /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '8px 0 24px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 20px'
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Full draw",
    meta: "Scroll to move through rounds"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 20px'
    }
  }, /*#__PURE__*/React.createElement(Bracket, {
    highlightPlayer: "J. Raper",
    selectedId: "r64-7",
    onSelectMatch: () => go('bracket'),
    rounds: [{
      name: 'Round of 64',
      matches: [{
        id: 'r64-1',
        home: 'L. Okafor',
        away: 'M. Doyle',
        homeScore: 5,
        awayScore: 1
      }, {
        id: 'r64-7',
        home: 'J. Raper',
        away: 'A. Wilson',
        state: 'live',
        board: '14'
      }, {
        id: 'r64-9',
        home: 'D. Kerr',
        away: 'S. Patel',
        state: 'pending'
      }]
    }, {
      name: 'Round of 32',
      matches: [{
        id: 'r32-1',
        home: 'L. Okafor'
      }, {
        id: 'r32-4'
      }]
    }, {
      name: 'Round of 16',
      matches: [{
        id: 'r16-1'
      }]
    }]
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '16px 20px 0'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    fullWidth: true,
    onClick: () => setView('you')
  }, "Read the draw as a list"), /*#__PURE__*/React.createElement("p", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      paddingTop: 10,
      margin: 0
    }
  }, "Every draw has a linear alternative. Screen readers and Reduced Motion default to the list."))));
}
function BracketDetail({
  go
}) {
  const [zoom, setZoom] = React.useState('near');
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    eyebrow: "North East Open",
    title: "Bracket",
    onBack: () => go('draw'),
    actions: [{
      icon: 'share',
      label: 'Share'
    }]
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '16px 20px 12px',
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement(SegmentedControl, {
    items: [{
      id: 'near',
      label: 'Your half'
    }, {
      id: 'far',
      label: 'Other half'
    }],
    value: zoom,
    onChange: setZoom,
    fullWidth: false
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      font: '600 13px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 10,
      height: 10,
      background: 'var(--color-background-brand-subtle)',
      border: '1px solid var(--color-border-brand)'
    }
  }), "You")), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 20px 16px'
    }
  }, /*#__PURE__*/React.createElement(Bracket, {
    highlightPlayer: "J. Raper",
    selectedId: "r32-4",
    onSelectMatch: () => {},
    rounds: zoom === 'near' ? [{
      name: 'Round of 64',
      matches: [{
        id: 'a',
        home: 'J. Raper',
        away: 'A. Wilson',
        homeScore: 5,
        awayScore: 3
      }, {
        id: 'b',
        home: 'D. Kerr',
        away: 'S. Patel',
        homeScore: 5,
        awayScore: 2
      }]
    }, {
      name: 'Round of 32',
      matches: [{
        id: 'r32-4',
        home: 'J. Raper',
        away: 'D. Kerr',
        homeScore: 2,
        awayScore: 1,
        state: 'live',
        board: '9'
      }]
    }, {
      name: 'Round of 16',
      matches: [{
        id: 'c',
        away: 'H. Nunn'
      }]
    }] : [{
      name: 'Round of 64',
      matches: [{
        id: 'd',
        home: 'L. Okafor',
        away: 'M. Doyle',
        homeScore: 5,
        awayScore: 1
      }, {
        id: 'e',
        home: 'R. Blake',
        away: 'T. Shaw',
        homeScore: 4,
        awayScore: 5
      }]
    }, {
      name: 'Round of 32',
      matches: [{
        id: 'f',
        home: 'L. Okafor',
        away: 'T. Shaw',
        state: 'live',
        board: '3'
      }]
    }, {
      name: 'Round of 16',
      matches: [{
        id: 'g'
      }]
    }]
  })), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '20px 20px 24px',
      display: 'flex',
      flexDirection: 'column',
      gap: 16
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Selected match"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Round of 32 \xB7 Board 9"), /*#__PURE__*/React.createElement(LiveIndicator, {
    size: "small"
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(PlayerIdentity, {
    name: "J. Raper",
    rating: 1847,
    verified: true,
    size: "small"
  }), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '700 40px var(--font-sport)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, "2\u20131"), /*#__PURE__*/React.createElement(PlayerIdentity, {
    name: "D. Kerr",
    rating: 1839,
    size: "small",
    align: "right"
  })), /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    fullWidth: true,
    onClick: () => go('live-match')
  }, "Open match centre"))));
}
function TournamentComplete({
  go
}) {
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    eyebrow: "North East Open",
    title: "Tournament complete",
    onBack: () => go('home')
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '28px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '800 25px/29px var(--font-ui)',
      letterSpacing: '.02em',
      textTransform: 'uppercase',
      color: 'var(--color-text-primary)'
    }
  }, "Semi finalist"), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '700 72px/68px var(--font-sport)',
      letterSpacing: '-.02em',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, "Last 4"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 17px/25px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, "Beaten 4\u20135 by Harry Nunn, rated 1,923. Your best result at this level."), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexWrap: 'wrap',
      gap: 8,
      paddingTop: 8
    }
  }, /*#__PURE__*/React.createElement(Tag, {
    tone: "achievement",
    icon: "award"
  }, "Career best run"), /*#__PURE__*/React.createElement(Tag, {
    tone: "neutral"
  }, "96 entries"))), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '24px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 20
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Your tournament"
  }), /*#__PURE__*/React.createElement(TournamentProgress, {
    rounds: [{
      round: 'Round of 64',
      opponent: 'Alex Wilson · 1,903',
      score: '5–3',
      state: 'won'
    }, {
      round: 'Round of 32',
      opponent: 'Danny Kerr · 1,839',
      score: '5–2',
      state: 'won'
    }, {
      round: 'Round of 16',
      opponent: 'Sam Patel · 1,812',
      score: '5–4',
      state: 'won'
    }, {
      round: 'Quarter final',
      opponent: 'Ryan Blake · 1,871',
      score: '5–3',
      state: 'won'
    }, {
      round: 'Semi final',
      opponent: 'Harry Nunn · 1,923',
      score: '4–5',
      state: 'lost'
    }]
  }), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 10
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Evidence"
  }), /*#__PURE__*/React.createElement(VerificationState, {
    state: "organiser-confirmed",
    explain: true
  })), /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    fullWidth: true,
    onClick: () => go('rating')
  }, "See how your rating moved"), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    fullWidth: true,
    onClick: () => go('discover')
  }, "Find your next event")));
}
Object.assign(window, {
  CheckIn,
  DrawRelease,
  BracketDetail,
  TournamentComplete
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/thro-app/screens-tournament.jsx", error: String((e && e.message) || e) }); }
