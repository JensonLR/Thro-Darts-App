try { (() => {
const D = window.THRDesignSystem_ac73b5;
const {
  BoardStatus,
  DataTable,
  CallControl,
  SectionHeader,
  Divider,
  Button,
  Tag,
  Icon,
  IconButton,
  SearchField,
  FilterChip,
  SegmentedControl,
  Stat,
  Progress,
  LiveIndicator,
  VerificationState,
  ErrorState,
  PlayerIdentity,
  Bracket,
  TournamentProgress,
  EmptyState,
  SyncState,
  Dialog,
  TeamRow,
  Insight
} = D;
const NAV = [['Live event', [['control', 'Tournament control'], ['boards', 'Board management'], ['queue', 'Match queue']]], ['Event setup', [['entries', 'Entries & check-in'], ['draw', 'Draw management']]], ['Integrity', [['disputes', 'Disputes'], ['verification', 'Result verification']]], ['Administration', [['league', 'League & divisions'], ['venue', 'Venue operations']]]];
function Bar({
  title,
  eyebrow,
  actions,
  children
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "bar"
  }, /*#__PURE__*/React.createElement("div", null, eyebrow ? /*#__PURE__*/React.createElement("div", {
    className: "thro-eyebrow"
  }, eyebrow) : null, /*#__PURE__*/React.createElement("h1", null, title)), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12
    }
  }, children, actions));
}

/* 1 — Tournament control: the operator's single screen. */
function Control({
  go
}) {
  const [sel, setSel] = React.useState('14');
  const [called, setCalled] = React.useState(false);
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Bar, {
    eyebrow: "North East Open \xB7 Saturday 14 September",
    title: "Tournament control",
    actions: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Button, {
      variant: "secondary",
      size: "small",
      icon: "share"
    }, "Publish results"), /*#__PURE__*/React.createElement(Button, {
      variant: "primary",
      size: "small",
      icon: "bell-ring"
    }, "Call next 4"))
  }, /*#__PURE__*/React.createElement(LiveIndicator, null)), /*#__PURE__*/React.createElement("div", {
    className: "body"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 40
    }
  }, /*#__PURE__*/React.createElement(Stat, {
    label: "Round",
    value: "R64",
    size: "large"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Boards in play",
    value: "12",
    size: "large"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Queue",
    value: "9",
    size: "large"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Awaiting result",
    value: "3",
    size: "large"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Disputed",
    value: "1",
    size: "large"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Avg match",
    value: "21",
    unit: "min",
    size: "large"
  })), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
    className: "two"
  }, /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Boards",
    meta: "16 boards \xB7 12 in play"
  }), /*#__PURE__*/React.createElement("div", {
    className: "grid5"
  }, [['14', 'playing', 'R64', 'J. Raper', 'A. Wilson', '3–2', '18 min'], ['9', 'called', 'R64', 'D. Kerr', 'S. Patel', '', '2 min'], ['3', 'awaiting', 'R64', 'L. Okafor', 'M. Doyle', '5–1', ''], ['7', 'disputed', 'R64', 'R. Blake', 'T. Shaw', '5–4', ''], ['11', 'free', '', '', '', '', ''], ['1', 'playing', 'R64', 'C. Dunne', 'P. Hall', '2–4', '11 min'], ['2', 'playing', 'R64', 'G. Ives', 'N. Frost', '1–1', '6 min'], ['4', 'playing', 'R64', 'K. Marsh', 'O. Wren', '4–3', '24 min'], ['5', 'closed', '', '', '', '', ''], ['6', 'free', '', '', '', '', '']].map(([b, st, r, h, a, s, e]) => /*#__PURE__*/React.createElement(BoardStatus, {
    key: b,
    board: b,
    state: st,
    round: r || undefined,
    home: h || undefined,
    away: a || undefined,
    score: s || undefined,
    elapsed: e || undefined,
    selected: sel === b,
    onClick: () => setSel(b)
  }))), /*#__PURE__*/React.createElement("p", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      margin: 0
    }
  }, "Board state is carried by an icon, a word and a surface tint \u2014 these screens are read from across a venue office, often in monochrome on a projected display.")), /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Queue",
    meta: "Longest wait 14 min",
    action: "Manage",
    onAction: () => go('queue')
  }), /*#__PURE__*/React.createElement(CallControl, {
    round: "Round of 64",
    home: "G. Ives",
    away: "N. Frost",
    board: "11",
    waiting: "14 min",
    called: called,
    onCall: () => setCalled(true),
    onReassign: () => {},
    onWithdraw: () => {}
  }), /*#__PURE__*/React.createElement(CallControl, {
    round: "Round of 64",
    home: "E. Vance",
    away: "B. Ridley",
    waiting: "9 min",
    onCall: () => {},
    onReassign: () => {}
  }), /*#__PURE__*/React.createElement(CallControl, {
    round: "Round of 64",
    home: "F. Ngata",
    away: "W. Croft",
    waiting: "6 min",
    onCall: () => {},
    onReassign: () => {}
  }), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Needs attention"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("button", {
    onClick: () => go('disputes'),
    style: {
      textAlign: 'left',
      background: 'var(--color-status-error-surface)',
      border: '1px solid var(--color-status-error)',
      borderRadius: 'var(--radius-card)',
      padding: 14,
      cursor: 'pointer',
      display: 'flex',
      gap: 10,
      alignItems: 'flex-start'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "triangle-alert",
    size: 18,
    color: "var(--color-status-error)",
    style: {
      marginTop: 2
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 15px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, "Board 7 \u2014 result disputed"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, "Blake and Shaw submitted different results. Both players are at the board."))), /*#__PURE__*/React.createElement("button", {
    onClick: () => go('boards'),
    style: {
      textAlign: 'left',
      background: 'var(--color-status-warning-surface)',
      border: '1px solid var(--color-status-warning)',
      borderRadius: 'var(--radius-card)',
      padding: 14,
      cursor: 'pointer',
      display: 'flex',
      gap: 10,
      alignItems: 'flex-start'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "clock",
    size: 18,
    color: "var(--color-status-warning)",
    style: {
      marginTop: 2
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 15px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, "Board 3 \u2014 result outstanding 11 min"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, "Okafor won 5\u20131. Awaiting the second confirmation."))))))));
}

/* 2 — Board management */
function Boards({
  go
}) {
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Bar, {
    eyebrow: "North East Open",
    title: "Board management",
    actions: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Button, {
      variant: "secondary",
      size: "small"
    }, "Close a board"), /*#__PURE__*/React.createElement(Button, {
      variant: "primary",
      size: "small"
    }, "Add board"))
  }), /*#__PURE__*/React.createElement("div", {
    className: "body"
  }, /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Board register",
    meta: "16 boards \xB7 Sunderland Sports Centre"
  }), /*#__PURE__*/React.createElement(DataTable, {
    dense: true,
    selectedId: "b7",
    onRowClick: () => {},
    columns: [{
      key: 'b',
      label: 'Board',
      numeric: true,
      width: '70px'
    }, {
      key: 's',
      label: 'State'
    }, {
      key: 'm',
      label: 'Match'
    }, {
      key: 'r',
      label: 'Round'
    }, {
      key: 'e',
      label: 'On board',
      numeric: true
    }, {
      key: 'sc',
      label: 'Score',
      numeric: true
    }, {
      key: 'a',
      label: ''
    }],
    rows: [{
      id: 'b14',
      b: 14,
      s: /*#__PURE__*/React.createElement(Tag, {
        tone: "live",
        icon: "radio"
      }, "In play"),
      m: 'J. Raper v A. Wilson',
      r: 'R64',
      e: '18 min',
      sc: '3–2',
      a: /*#__PURE__*/React.createElement(Button, {
        variant: "ghost",
        size: "small"
      }, "Open")
    }, {
      id: 'b9',
      b: 9,
      s: /*#__PURE__*/React.createElement(Tag, {
        tone: "live",
        icon: "bell-ring"
      }, "Called"),
      m: 'D. Kerr v S. Patel',
      r: 'R64',
      e: '2 min',
      sc: '—',
      a: /*#__PURE__*/React.createElement(Button, {
        variant: "ghost",
        size: "small"
      }, "Recall")
    }, {
      id: 'b3',
      b: 3,
      s: /*#__PURE__*/React.createElement(Tag, {
        tone: "warning",
        icon: "clock"
      }, "Awaiting result"),
      m: 'L. Okafor v M. Doyle',
      r: 'R64',
      e: '32 min',
      sc: '5–1',
      a: /*#__PURE__*/React.createElement(Button, {
        variant: "ghost",
        size: "small"
      }, "Confirm")
    }, {
      id: 'b7',
      b: 7,
      s: /*#__PURE__*/React.createElement(Tag, {
        tone: "error",
        icon: "triangle-alert"
      }, "Disputed"),
      m: 'R. Blake v T. Shaw',
      r: 'R64',
      e: '41 min',
      sc: '5–4',
      a: /*#__PURE__*/React.createElement(Button, {
        variant: "ghost",
        size: "small"
      }, "Resolve")
    }, {
      id: 'b11',
      b: 11,
      s: /*#__PURE__*/React.createElement(Tag, {
        tone: "neutral"
      }, "Free"),
      m: '—',
      r: '—',
      e: '—',
      sc: '—',
      a: /*#__PURE__*/React.createElement(Button, {
        variant: "ghost",
        size: "small"
      }, "Assign")
    }, {
      id: 'b5',
      b: 5,
      s: /*#__PURE__*/React.createElement(Tag, {
        tone: "neutral",
        icon: "circle-x"
      }, "Closed"),
      m: 'Lighting fault',
      r: '—',
      e: '—',
      sc: '—',
      a: /*#__PURE__*/React.createElement(Button, {
        variant: "ghost",
        size: "small"
      }, "Reopen")
    }]
  })), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
    className: "two"
  }, /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Throughput",
    meta: "Round of 64"
  }), /*#__PURE__*/React.createElement(Progress, {
    label: "Matches complete",
    value: 41,
    max: 64,
    valueLabel: "41 of 64",
    height: 8
  }), /*#__PURE__*/React.createElement(Progress, {
    label: "Boards utilised",
    value: 12,
    max: 15,
    valueLabel: "12 of 15 open",
    tone: "neutral",
    height: 8
  }), /*#__PURE__*/React.createElement("p", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      margin: 0
    }
  }, "At the current rate the round completes at approximately 14:05. Reopening board 5 would bring that forward by about 12 minutes.")), /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Scorer coverage"
  }), /*#__PURE__*/React.createElement(DataTable, {
    dense: true,
    columns: [{
      key: 'b',
      label: 'Board',
      numeric: true
    }, {
      key: 's',
      label: 'Scorer'
    }, {
      key: 'm',
      label: 'Method'
    }],
    rows: [{
      id: '1',
      b: 14,
      s: 'THRØ app · A. Wilson',
      m: 'Participant'
    }, {
      id: '2',
      b: 9,
      s: 'Venue scorer · M. Pike',
      m: 'Official'
    }, {
      id: '3',
      b: 3,
      s: 'THRØ app · L. Okafor',
      m: 'Participant'
    }, {
      id: '4',
      b: 7,
      s: 'Unassigned',
      m: 'Self-reported'
    }]
  })))));
}

/* 3 — Match queue */
function Queue({
  go
}) {
  const [f, setF] = React.useState('waiting');
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Bar, {
    eyebrow: "North East Open",
    title: "Match queue",
    actions: /*#__PURE__*/React.createElement(Button, {
      variant: "primary",
      size: "small",
      icon: "bell-ring"
    }, "Call next available")
  }), /*#__PURE__*/React.createElement("div", {
    className: "body"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 10
    }
  }, /*#__PURE__*/React.createElement(FilterChip, {
    selected: f === 'waiting',
    count: 9,
    onClick: () => setF('waiting')
  }, "Waiting"), /*#__PURE__*/React.createElement(FilterChip, {
    selected: f === 'called',
    count: 2,
    onClick: () => setF('called')
  }, "Called"), /*#__PURE__*/React.createElement(FilterChip, {
    selected: f === 'blocked',
    count: 1,
    onClick: () => setF('blocked')
  }, "Blocked")), f === 'blocked' ? /*#__PURE__*/React.createElement(ErrorState, {
    title: "One match cannot be called",
    what: "F. Ngata has not checked in.",
    safe: "The draw is unaffected and the opponent keeps their place.",
    todo: "Withdraw F. Ngata to advance W. Croft, or extend check-in for this player.",
    actionLabel: "Open entries",
    onAction: () => go('entries')
  }) : /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, (f === 'waiting' ? [['Round of 64', 'G. Ives', 'N. Frost', '11', '14 min', false], ['Round of 64', 'E. Vance', 'B. Ridley', '', '9 min', false], ['Round of 64', 'F. Ngata', 'W. Croft', '', '6 min', false], ['Round of 64', 'H. Nunn', 'P. Sowe', '', '4 min', false], ['Round of 64', 'C. Dunne', 'J. Ahmed', '', '2 min', false]] : [['Round of 64', 'D. Kerr', 'S. Patel', '9', '2 min', true], ['Round of 64', 'K. Marsh', 'O. Wren', '4', '1 min', true]]).map(([r, h, a, b, w, c]) => /*#__PURE__*/React.createElement(CallControl, {
    key: h,
    round: r,
    home: h,
    away: a,
    board: b || undefined,
    waiting: w,
    called: c,
    onCall: () => {},
    onReassign: () => {},
    onWithdraw: () => {}
  }))), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(Insight, {
    tone: "neutral",
    eyebrow: "Operational note",
    headline: "Two boards free, five matches waiting",
    evidence: "Boards 6 and 11 are free while five matches have been waiting more than two minutes. Calling in draw order keeps the bracket balanced.",
    actionTitle: "Call G. Ives v N. Frost to board 11",
    actionLabel: "Call to board",
    onAction: () => {}
  })));
}
Object.assign(window, {
  NAV,
  Bar,
  Control,
  Boards,
  Queue
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/thro-organiser/screens.jsx", error: String((e && e.message) || e) }); }

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Divider = __ds_scope.Divider;

__ds_ns.Icon = __ds_scope.Icon;

__ds_ns.IconButton = __ds_scope.IconButton;

__ds_ns.SectionHeader = __ds_scope.SectionHeader;

__ds_ns.Tag = __ds_scope.Tag;

__ds_ns.ComparisonChart = __ds_scope.ComparisonChart;

__ds_ns.Insight = __ds_scope.Insight;

__ds_ns.Stat = __ds_scope.Stat;

__ds_ns.TrendChart = __ds_scope.TrendChart;

__ds_ns.Bracket = __ds_scope.Bracket;

__ds_ns.PathwayStep = __ds_scope.PathwayStep;

__ds_ns.ShadowSelector = __ds_scope.ShadowSelector;

__ds_ns.TournamentProgress = __ds_scope.TournamentProgress;

__ds_ns.TrainingDrill = __ds_scope.TrainingDrill;

__ds_ns.TrainingSession = __ds_scope.TrainingSession;

__ds_ns.FilterChip = __ds_scope.FilterChip;

__ds_ns.NumericInput = __ds_scope.NumericInput;

__ds_ns.SearchField = __ds_scope.SearchField;

__ds_ns.SegmentedControl = __ds_scope.SegmentedControl;

__ds_ns.Tabs = __ds_scope.Tabs;

__ds_ns.TextField = __ds_scope.TextField;

__ds_ns.EventHero = __ds_scope.EventHero;

__ds_ns.EventRow = __ds_scope.EventRow;

__ds_ns.PlayerComparison = __ds_scope.PlayerComparison;

__ds_ns.PlayerIdentity = __ds_scope.PlayerIdentity;

__ds_ns.PlayerRow = __ds_scope.PlayerRow;

__ds_ns.TeamRow = __ds_scope.TeamRow;

__ds_ns.VenueRow = __ds_scope.VenueRow;

__ds_ns.BottomBar = __ds_scope.BottomBar;

__ds_ns.TopBar = __ds_scope.TopBar;

__ds_ns.BoardStatus = __ds_scope.BoardStatus;

__ds_ns.CallControl = __ds_scope.CallControl;

__ds_ns.DataTable = __ds_scope.DataTable;

__ds_ns.Confidence = __ds_scope.Confidence;

__ds_ns.FormIndicator = __ds_scope.FormIndicator;

__ds_ns.Rank = __ds_scope.Rank;

__ds_ns.RatingCompact = __ds_scope.RatingCompact;

__ds_ns.RatingHero = __ds_scope.RatingHero;

__ds_ns.RatingMovement = __ds_scope.RatingMovement;

__ds_ns.Checkout = __ds_scope.Checkout;

__ds_ns.LegState = __ds_scope.LegState;

__ds_ns.MatchHeader = __ds_scope.MatchHeader;

__ds_ns.MatchSummary = __ds_scope.MatchSummary;

__ds_ns.RemainingScore = __ds_scope.RemainingScore;

__ds_ns.ScoreHero = __ds_scope.ScoreHero;

__ds_ns.ScoreKeypad = __ds_scope.ScoreKeypad;

__ds_ns.SetState = __ds_scope.SetState;

__ds_ns.TurnIndicator = __ds_scope.TurnIndicator;

__ds_ns.Dialog = __ds_scope.Dialog;

__ds_ns.EmptyState = __ds_scope.EmptyState;

__ds_ns.ErrorState = __ds_scope.ErrorState;

__ds_ns.LiveIndicator = __ds_scope.LiveIndicator;

__ds_ns.LoadingState = __ds_scope.LoadingState;

__ds_ns.Notification = __ds_scope.Notification;

__ds_ns.OfflineState = __ds_scope.OfflineState;

__ds_ns.Progress = __ds_scope.Progress;

__ds_ns.Sheet = __ds_scope.Sheet;

__ds_ns.Snackbar = __ds_scope.Snackbar;

__ds_ns.SyncState = __ds_scope.SyncState;

__ds_ns.VerificationState = __ds_scope.VerificationState;

})();
