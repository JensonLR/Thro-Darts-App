try { (() => {
const D = window.THRDesignSystem_ac73b5;
const {
  DataTable,
  SectionHeader,
  Divider,
  Button,
  Tag,
  Icon,
  SearchField,
  FilterChip,
  SegmentedControl,
  Stat,
  Progress,
  VerificationState,
  ErrorState,
  PlayerIdentity,
  Bracket,
  TournamentProgress,
  Dialog,
  TeamRow,
  EmptyState,
  SyncState,
  Insight,
  LiveIndicator
} = D;
const Bar = window.Bar;

/* 4 — Entries & check-in */
function Entries({
  go
}) {
  const [q, setQ] = React.useState('');
  const [scope, setScope] = React.useState('all');
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Bar, {
    eyebrow: "North East Open \xB7 Check-in closes 11:30",
    title: "Entries & check-in",
    actions: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Button, {
      variant: "secondary",
      size: "small",
      icon: "share"
    }, "Export list"), /*#__PURE__*/React.createElement(Button, {
      variant: "primary",
      size: "small"
    }, "Close check-in"))
  }), /*#__PURE__*/React.createElement("div", {
    className: "body"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 40
    }
  }, /*#__PURE__*/React.createElement(Stat, {
    label: "Entries",
    value: "96",
    size: "large"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Checked in",
    value: "74",
    size: "large"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Outstanding",
    value: "22",
    size: "large"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Unpaid",
    value: "3",
    size: "large"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Capacity",
    value: "128",
    size: "large"
  })), /*#__PURE__*/React.createElement(Progress, {
    label: "Field checked in",
    value: 74,
    max: 96,
    valueLabel: "74 of 96",
    height: 8
  }), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 16,
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      maxWidth: 420
    }
  }, /*#__PURE__*/React.createElement(SearchField, {
    value: q,
    onChange: setQ,
    placeholder: "Player, team or venue",
    scope: "entries"
  })), /*#__PURE__*/React.createElement(SegmentedControl, {
    fullWidth: false,
    value: scope,
    onChange: setScope,
    items: [{
      id: 'all',
      label: 'All'
    }, {
      id: 'in',
      label: 'Checked in'
    }, {
      id: 'out',
      label: 'Outstanding'
    }, {
      id: 'unpaid',
      label: 'Unpaid'
    }]
  })), /*#__PURE__*/React.createElement(DataTable, {
    dense: true,
    caption: scope === 'out' ? 'Outstanding · 22 players' : 'Entries · 96 players',
    onRowClick: () => {},
    columns: [{
      key: 's',
      label: 'Seed',
      numeric: true,
      width: '64px'
    }, {
      key: 'p',
      label: 'Player',
      strong: true
    }, {
      key: 't',
      label: 'Team'
    }, {
      key: 'r',
      label: 'Rating',
      numeric: true
    }, {
      key: 'v',
      label: 'Identity'
    }, {
      key: 'c',
      label: 'Checked in'
    }, {
      key: 'e',
      label: 'Entry'
    }, {
      key: 'a',
      label: ''
    }],
    rows: (scope === 'out' ? [['19', 'S. Patel', 'Tyne Arms', '1,812', 'verified', '—', 'Paid'], ['24', 'F. Ngata', 'Riverside', '1,788', 'participant', '—', 'Paid'], ['31', 'J. Ahmed', 'Boro Legion', '1,754', 'verified', '—', 'Unpaid'], ['44', 'P. Sowe', 'Grange B', '1,701', 'self', '—', 'Paid']] : [['1', 'L. Okafor', 'Riverside', '1,948', 'verified', '11:04', 'Paid'], ['2', 'H. Nunn', 'Grange A', '1,923', 'verified', '10:58', 'Paid'], ['7', 'A. Wilson', 'Sunderland B', '1,903', 'participant', '11:11', 'Paid'], ['12', 'J. Raper', 'Grange A', '1,847', 'verified', '11:12', 'Paid'], ['19', 'S. Patel', 'Tyne Arms', '1,812', 'verified', '—', 'Paid'], ['24', 'F. Ngata', 'Riverside', '1,788', 'participant', '—', 'Paid'], ['31', 'J. Ahmed', 'Boro Legion', '1,754', 'verified', '—', 'Unpaid']]).map(([s, p, t, r, v, c, e], i) => ({
      id: 'e' + i,
      s,
      p,
      t,
      r,
      v: /*#__PURE__*/React.createElement(VerificationState, {
        compact: true,
        state: v === 'verified' ? 'thro-verified' : v === 'participant' ? 'participant-confirmed' : 'self-reported'
      }),
      c: c === '—' ? /*#__PURE__*/React.createElement("span", {
        style: {
          color: 'var(--color-text-tertiary)'
        }
      }, "\u2014") : c,
      e: e === 'Paid' ? /*#__PURE__*/React.createElement(Tag, {
        tone: "success"
      }, "Paid") : /*#__PURE__*/React.createElement(Tag, {
        tone: "warning"
      }, "Unpaid"),
      a: c === '—' ? /*#__PURE__*/React.createElement(Button, {
        variant: "secondary",
        size: "small"
      }, "Check in") : /*#__PURE__*/React.createElement(Button, {
        variant: "ghost",
        size: "small"
      }, "Undo")
    }))
  }), /*#__PURE__*/React.createElement(Insight, {
    tone: "neutral",
    eyebrow: "Before you close check-in",
    headline: "22 players outstanding",
    evidence: "Closing check-in withdraws every outstanding player and makes the draw from 74 entries. Three of them have unpaid entries and would be withdrawn regardless.",
    actionTitle: "Send a final call to all outstanding players",
    actionLabel: "Send final call",
    onAction: () => {}
  })));
}

/* 5 — Draw management */
function DrawManagement({
  go
}) {
  const [state, setState] = React.useState('draft');
  const [confirm, setConfirm] = React.useState(false);
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Bar, {
    eyebrow: "North East Open",
    title: "Draw management",
    actions: state === 'draft' ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Button, {
      variant: "secondary",
      size: "small",
      icon: "rotate-ccw"
    }, "Redraw"), /*#__PURE__*/React.createElement(Button, {
      variant: "primary",
      size: "small",
      onClick: () => setConfirm(true)
    }, "Publish draw")) : /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Tag, {
      tone: "success",
      icon: "circle-check"
    }, "Published 11:30"), /*#__PURE__*/React.createElement(Button, {
      variant: "secondary",
      size: "small"
    }, "Notify field"))
  }), /*#__PURE__*/React.createElement("div", {
    className: "body"
  }, state === 'draft' ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 10,
      alignItems: 'flex-start',
      background: 'var(--color-status-warning-surface)',
      border: '1px solid var(--color-status-warning)',
      borderRadius: 'var(--radius-card)',
      padding: 14
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "info",
    size: 18,
    color: "var(--color-status-warning)",
    style: {
      marginTop: 2
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 15px/22px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, "This draw is a draft. Players cannot see it, and no boards are assigned until you publish.")) : /*#__PURE__*/React.createElement(SyncState, {
    state: "synced",
    detail: "Published at 11:30. 74 players notified with their first-round opponent and board."
  }), /*#__PURE__*/React.createElement("div", {
    className: "two"
  }, /*#__PURE__*/React.createElement("div", {
    className: "sec",
    style: {
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Draw",
    meta: "74 entries \xB7 Round of 64 with 10 byes"
  }), /*#__PURE__*/React.createElement(Bracket, {
    highlightPlayer: "J. Raper",
    selectedId: "m1",
    onSelectMatch: () => {},
    rounds: [{
      name: 'Round of 64',
      matches: [{
        id: 'm1',
        home: 'L. Okafor',
        away: 'M. Doyle'
      }, {
        id: 'm2',
        home: 'J. Raper',
        away: 'A. Wilson'
      }, {
        id: 'm3',
        home: 'D. Kerr',
        away: 'S. Patel'
      }, {
        id: 'm4',
        home: 'R. Blake',
        away: 'T. Shaw'
      }]
    }, {
      name: 'Round of 32',
      matches: [{
        id: 'm5'
      }, {
        id: 'm6'
      }]
    }, {
      name: 'Round of 16',
      matches: [{
        id: 'm7'
      }]
    }]
  })), /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Draw settings"
  }), /*#__PURE__*/React.createElement(DataTable, {
    columns: [{
      key: 'k',
      label: 'Setting'
    }, {
      key: 'v',
      label: 'Value',
      strong: true
    }],
    rows: [{
      id: '1',
      k: 'Seeding',
      v: 'THRØ Rating'
    }, {
      id: '2',
      k: 'Byes',
      v: '10, top seeds'
    }, {
      id: '3',
      k: 'Format',
      v: '501 · Bo9 · double out'
    }, {
      id: '4',
      k: 'Boards',
      v: '16, assigned on publish'
    }, {
      id: '5',
      k: 'Club protection',
      v: 'First round only'
    }]
  }), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Bye allocation",
    meta: "Top 10 seeds"
  }), /*#__PURE__*/React.createElement("p", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      margin: 0
    }
  }, "74 entries need 10 byes to reach a 64-player bracket. Byes go to the highest-rated checked-in players. Every bye is recorded on the affected players' match history as a bye, not a win \u2014 it does not affect rating."))), confirm ? /*#__PURE__*/React.createElement(Dialog, {
    title: "Publish the draw?",
    message: "74 players will be notified immediately with their first-round opponent and board. The draw cannot be changed after publishing without a recorded correction.",
    confirmLabel: "Publish draw",
    cancelLabel: "Keep as draft",
    onCancel: () => setConfirm(false),
    onConfirm: () => {
      setConfirm(false);
      setState('live');
    }
  }) : null));
}
Object.assign(window, {
  Entries,
  DrawManagement
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/thro-organiser/screens-setup.jsx", error: String((e && e.message) || e) }); }
