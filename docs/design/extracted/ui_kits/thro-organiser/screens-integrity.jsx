try { (() => {
const D = window.THRDesignSystem_ac73b5;
const {
  DataTable,
  SectionHeader,
  Divider,
  Button,
  Tag,
  Icon,
  VerificationState,
  ErrorState,
  PlayerIdentity,
  PlayerComparison,
  Stat,
  SegmentedControl,
  Dialog,
  Snackbar,
  EmptyState,
  Insight,
  TeamRow,
  SearchField,
  FilterChip,
  Progress,
  TrendChart
} = D;
const Bar = window.Bar;

/* 6 — Disputes */
function Disputes({
  go
}) {
  const [resolved, setResolved] = React.useState(null);
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Bar, {
    eyebrow: "North East Open \xB7 Board 7",
    title: "Dispute resolution",
    actions: /*#__PURE__*/React.createElement(Button, {
      variant: "secondary",
      size: "small",
      icon: "circle-question-mark"
    }, "Dispute policy")
  }), /*#__PURE__*/React.createElement("div", {
    className: "body"
  }, resolved ? /*#__PURE__*/React.createElement(Snackbar, {
    tone: "success",
    message: `Result recorded as ${resolved}. Both players and the bracket have been updated.`,
    actionLabel: "Undo",
    onAction: () => setResolved(null)
  }) : null, /*#__PURE__*/React.createElement("div", {
    className: "two"
  }, /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "What was submitted",
    meta: "Round of 64 \xB7 13:42"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: '1fr 1fr',
      gap: 16
    }
  }, [['R. Blake', 1871, '5–4 to Blake', 'thro-recorded', 'Scored in the THRØ app, leg by leg.'], ['T. Shaw', 1849, '5–4 to Shaw', 'self-reported', 'Entered after the match from memory.']].map(([n, r, claim, prov, note]) => /*#__PURE__*/React.createElement("div", {
    key: n,
    style: {
      border: '1px solid var(--color-border-default)',
      borderRadius: 'var(--radius-card)',
      padding: 16,
      display: 'flex',
      flexDirection: 'column',
      gap: 10
    }
  }, /*#__PURE__*/React.createElement(PlayerIdentity, {
    name: n,
    rating: r,
    size: "small"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 25px var(--font-sport)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, claim), /*#__PURE__*/React.createElement(VerificationState, {
    state: prov,
    explain: true
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, note)))), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Evidence",
    meta: "THR\xD8-recorded legs"
  }), /*#__PURE__*/React.createElement(DataTable, {
    dense: true,
    columns: [{
      key: 'l',
      label: 'Leg',
      numeric: true,
      width: '60px'
    }, {
      key: 'w',
      label: 'Winner'
    }, {
      key: 'c',
      label: 'Checkout',
      numeric: true
    }, {
      key: 'd',
      label: 'Darts',
      numeric: true
    }, {
      key: 's',
      label: 'Confirmed'
    }],
    rows: [[1, 'Blake', '40', '15', 'Both'], [2, 'Shaw', '76', '18', 'Both'], [3, 'Blake', '32', '17', 'Both'], [4, 'Blake', '80', '15', 'Both'], [5, 'Shaw', '36', '21', 'Both'], [6, 'Shaw', '48', '19', 'Both'], [7, 'Blake', '101', '14', 'Both'], [8, 'Shaw', '24', '20', 'Both'], [9, 'Blake', '64', '16', 'Blake only']].map(([l, w, c, d, s], i) => ({
      id: 'l' + i,
      l,
      w,
      c,
      d,
      s: s === 'Both' ? /*#__PURE__*/React.createElement(Tag, {
        tone: "success"
      }, "Both") : /*#__PURE__*/React.createElement(Tag, {
        tone: "warning"
      }, "Blake only")
    }))
  }), /*#__PURE__*/React.createElement("p", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      margin: 0
    }
  }, "Legs 1\u20138 are confirmed by both players and give 4\u20134. The dispute concerns leg 9 only, which Blake recorded in the app and Shaw did not confirm.")), /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Resolve"
  }), !resolved ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 10
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    fullWidth: true,
    onClick: () => setResolved('5–4 to Blake')
  }, "Uphold Blake \xB7 5\u20134"), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    fullWidth: true,
    onClick: () => setResolved('5–4 to Shaw')
  }, "Uphold Shaw \xB7 5\u20134"), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    fullWidth: true,
    onClick: () => setResolved('leg 9 replayed')
  }, "Replay leg 9"), /*#__PURE__*/React.createElement(Button, {
    variant: "destructive",
    fullWidth: true,
    onClick: () => setResolved('void, both withdrawn')
  }, "Void the match")), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
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
  }, "Whatever you decide is recorded as an organiser decision with your name against it. Both players see the outcome, the reason and the evidence used. Ratings are recalculated from the corrected result."))) : /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 14
    }
  }, /*#__PURE__*/React.createElement(VerificationState, {
    state: "corrected",
    explain: true
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    fullWidth: true,
    onClick: () => go('control')
  }, "Back to tournament control")), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Open disputes",
    meta: "1 of 41 results"
  }), /*#__PURE__*/React.createElement("p", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      margin: 0
    }
  }, "One dispute in this event. Across the last twelve months, 0.4% of results at your events have been disputed.")))));
}

/* 7 — Result verification */
function Verification({
  go
}) {
  const [f, setF] = React.useState('pending');
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Bar, {
    eyebrow: "North East Open",
    title: "Result verification",
    actions: /*#__PURE__*/React.createElement(Button, {
      variant: "primary",
      size: "small"
    }, "Confirm all THR\xD8-recorded")
  }), /*#__PURE__*/React.createElement("div", {
    className: "body"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 40
    }
  }, /*#__PURE__*/React.createElement(Stat, {
    label: "Results",
    value: "41",
    size: "large"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "THR\xD8 verified",
    value: "28",
    size: "large"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Pending",
    value: "12",
    size: "large"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Disputed",
    value: "1",
    size: "large"
  })), /*#__PURE__*/React.createElement(SegmentedControl, {
    fullWidth: false,
    value: f,
    onChange: setF,
    items: [{
      id: 'pending',
      label: 'Pending'
    }, {
      id: 'verified',
      label: 'Verified'
    }, {
      id: 'corrected',
      label: 'Corrected'
    }]
  }), f === 'corrected' ? /*#__PURE__*/React.createElement(EmptyState, {
    title: "No corrections in this event",
    message: "Corrected results appear here with the organiser decision and the evidence used."
  }) : /*#__PURE__*/React.createElement(DataTable, {
    dense: true,
    onRowClick: () => {},
    columns: [{
      key: 'b',
      label: 'Board',
      numeric: true,
      width: '70px'
    }, {
      key: 'r',
      label: 'Round'
    }, {
      key: 'm',
      label: 'Match',
      strong: true
    }, {
      key: 's',
      label: 'Score',
      numeric: true
    }, {
      key: 'p',
      label: 'Provenance'
    }, {
      key: 't',
      label: 'Submitted',
      numeric: true
    }, {
      key: 'a',
      label: ''
    }],
    rows: (f === 'pending' ? [[3, 'R64', 'L. Okafor bt M. Doyle', '5–1', 'organiser-confirmed', '13:38'], [1, 'R64', 'C. Dunne bt P. Hall', '5–4', 'participant-confirmed', '13:31'], [12, 'R64', 'G. Ives bt N. Frost', '5–2', 'self-reported', '13:29'], [6, 'R64', 'K. Marsh bt O. Wren', '5–3', 'self-reported', '13:24']] : [[14, 'R64', 'J. Raper bt A. Wilson', '5–3', 'thro-verified', '13:44'], [9, 'R64', 'D. Kerr bt S. Patel', '5–2', 'thro-verified', '13:40'], [2, 'R64', 'H. Nunn bt P. Sowe', '5–0', 'thro-verified', '13:12']]).map(([b, r, m, s, p, t], i) => ({
      id: 'v' + i,
      b,
      r,
      m,
      s,
      p: /*#__PURE__*/React.createElement(VerificationState, {
        compact: true,
        state: p
      }),
      t,
      a: f === 'pending' ? /*#__PURE__*/React.createElement(Button, {
        variant: "secondary",
        size: "small"
      }, "Confirm") : /*#__PURE__*/React.createElement(Button, {
        variant: "ghost",
        size: "small"
      }, "View")
    }))
  }), /*#__PURE__*/React.createElement(Insight, {
    tone: "neutral",
    eyebrow: "Integrity note",
    headline: "Four results are self-reported",
    evidence: "Self-reported results still count, but they carry the weakest provenance and are the most common source of later disputes. Assigning a venue scorer to boards 6 and 12 would raise the whole round to participant-confirmed or better.",
    actionTitle: "Assign scorers to boards 6 and 12",
    actionLabel: "Open board management",
    onAction: () => go('boards')
  })));
}
Object.assign(window, {
  Disputes,
  Verification
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/thro-organiser/screens-integrity.jsx", error: String((e && e.message) || e) }); }
