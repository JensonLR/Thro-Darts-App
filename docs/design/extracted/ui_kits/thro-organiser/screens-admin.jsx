try { (() => {
const D = window.THRDesignSystem_ac73b5;
const {
  DataTable,
  SectionHeader,
  Divider,
  Button,
  Tag,
  Icon,
  TeamRow,
  VenueRow,
  Stat,
  SegmentedControl,
  Progress,
  TrendChart,
  SearchField,
  FilterChip,
  EmptyState,
  Insight,
  PlayerRow,
  BoardStatus,
  VerificationState,
  Dialog
} = D;
const Bar = window.Bar;

/* 8 — League & divisions */
function League({
  go
}) {
  const [tab, setTab] = React.useState('table');
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Bar, {
    eyebrow: "Tyne League \xB7 2025/26 season",
    title: "Division One",
    actions: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Button, {
      variant: "secondary",
      size: "small"
    }, "Edit fixtures"), /*#__PURE__*/React.createElement(Button, {
      variant: "primary",
      size: "small"
    }, "Publish table"))
  }), /*#__PURE__*/React.createElement("div", {
    className: "body"
  }, /*#__PURE__*/React.createElement(SegmentedControl, {
    fullWidth: false,
    value: tab,
    onChange: setTab,
    items: [{
      id: 'table',
      label: 'Table'
    }, {
      id: 'fixtures',
      label: 'Fixtures'
    }, {
      id: 'results',
      label: 'Results'
    }, {
      id: 'teams',
      label: 'Teams'
    }]
  }), tab === 'table' ? /*#__PURE__*/React.createElement("div", {
    className: "two"
  }, /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Table",
    meta: "12 teams \xB7 14 of 22 rounds played"
  }), /*#__PURE__*/React.createElement(DataTable, {
    dense: true,
    selectedId: "t2",
    onRowClick: () => {},
    columns: [{
      key: 'p',
      label: 'Pos',
      numeric: true,
      width: '56px'
    }, {
      key: 't',
      label: 'Team',
      strong: true
    }, {
      key: 'v',
      label: 'Venue',
      wrap: true
    }, {
      key: 'pl',
      label: 'P',
      numeric: true
    }, {
      key: 'w',
      label: 'W',
      numeric: true
    }, {
      key: 'l',
      label: 'L',
      numeric: true
    }, {
      key: 'lf',
      label: 'LF',
      numeric: true
    }, {
      key: 'la',
      label: 'LA',
      numeric: true
    }, {
      key: 'r',
      label: 'Team rating',
      numeric: true
    }, {
      key: 'pts',
      label: 'Pts',
      numeric: true,
      strong: true
    }],
    rows: [[1, 'Riverside A', 'Riverside Club', 14, 12, 2, 79, 41, '1,881', 24], [2, 'Grange A', 'Grange WMC', 14, 11, 3, 74, 46, '1,864', 22], [3, 'Boro Legion', 'Boro Legion Club', 14, 9, 5, 68, 52, '1,822', 18], [4, 'Tyne Arms', 'The Tyne Arms', 14, 8, 6, 63, 57, '1,798', 16], [5, 'Sunderland B', 'Sunderland SC', 14, 6, 8, 55, 65, '1,771', 12], [6, 'Grange B', 'Grange WMC', 14, 3, 11, 44, 76, '1,712', 6]].map(([p, t, v, pl, w, l, lf, la, r, pts]) => ({
      id: 't' + p,
      p,
      t,
      v,
      pl,
      w,
      l,
      lf,
      la,
      r,
      pts
    }))
  })), /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Season"
  }), /*#__PURE__*/React.createElement(TrendChart, {
    label: "Division average",
    points: [1762, 1770, 1775, 1781, 1788, 1791, 1798],
    height: 100,
    tableLabel: "Division One average rating rose from 1,762 to 1,798 across 14 rounds"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 32
    }
  }, /*#__PURE__*/React.createElement(Stat, {
    label: "Fixtures played",
    value: "84"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Outstanding",
    value: "48"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Registered players",
    value: "118"
  })), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(Insight, {
    tone: "neutral",
    eyebrow: "Administration",
    headline: "Two fixtures unplayed past deadline",
    evidence: "Grange B v Tyne Arms and Sunderland B v Riverside A were due on 4 September. Both captains have been notified twice.",
    actionTitle: "Set a rearranged date or award the fixture",
    actionLabel: "Open fixtures",
    onAction: () => setTab('fixtures')
  }))) : tab === 'fixtures' ? /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Fixtures",
    meta: "Round 15 \xB7 week commencing 15 September"
  }), /*#__PURE__*/React.createElement(DataTable, {
    dense: true,
    onRowClick: () => {},
    columns: [{
      key: 'd',
      label: 'Date',
      numeric: true
    }, {
      key: 'h',
      label: 'Home',
      strong: true
    }, {
      key: 'a',
      label: 'Away',
      strong: true
    }, {
      key: 'v',
      label: 'Venue'
    }, {
      key: 't',
      label: 'Start',
      numeric: true
    }, {
      key: 's',
      label: 'State'
    }, {
      key: 'ac',
      label: ''
    }],
    rows: [['Tue 16 Sep', 'Grange A', 'Boro Legion', 'Grange WMC', '19:30', 'scheduled'], ['Tue 16 Sep', 'Riverside A', 'Tyne Arms', 'Riverside Club', '19:30', 'scheduled'], ['Wed 17 Sep', 'Sunderland B', 'Grange B', 'Sunderland SC', '19:30', 'scheduled'], ['Thu 4 Sep', 'Grange B', 'Tyne Arms', 'Grange WMC', '19:30', 'overdue'], ['Thu 4 Sep', 'Sunderland B', 'Riverside A', 'Sunderland SC', '19:30', 'overdue']].map(([d, h, a, v, t, s], i) => ({
      id: 'f' + i,
      d,
      h,
      a,
      v,
      t,
      s: s === 'overdue' ? /*#__PURE__*/React.createElement(Tag, {
        tone: "error",
        icon: "clock"
      }, "Overdue") : /*#__PURE__*/React.createElement(Tag, {
        tone: "neutral"
      }, "Scheduled"),
      ac: s === 'overdue' ? /*#__PURE__*/React.createElement(Button, {
        variant: "secondary",
        size: "small"
      }, "Rearrange") : /*#__PURE__*/React.createElement(Button, {
        variant: "ghost",
        size: "small"
      }, "Edit")
    }))
  })) : tab === 'results' ? /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Recent results",
    meta: "Round 14"
  }), /*#__PURE__*/React.createElement(DataTable, {
    dense: true,
    onRowClick: () => {},
    columns: [{
      key: 'd',
      label: 'Date',
      numeric: true
    }, {
      key: 'm',
      label: 'Fixture',
      strong: true
    }, {
      key: 's',
      label: 'Legs',
      numeric: true
    }, {
      key: 'p',
      label: 'Provenance'
    }, {
      key: 'ac',
      label: ''
    }],
    rows: [['Tue 9 Sep', 'Grange A 6–3 Sunderland B', '6–3', 'organiser-confirmed'], ['Tue 9 Sep', 'Riverside A 7–2 Grange B', '7–2', 'organiser-confirmed'], ['Wed 10 Sep', 'Tyne Arms 5–4 Boro Legion', '5–4', 'participant-confirmed']].map(([d, m, s, p], i) => ({
      id: 'r' + i,
      d,
      m,
      s,
      p: /*#__PURE__*/React.createElement(VerificationState, {
        compact: true,
        state: p
      }),
      ac: /*#__PURE__*/React.createElement(Button, {
        variant: "ghost",
        size: "small"
      }, "View card")
    }))
  })) : /*#__PURE__*/React.createElement("div", {
    className: "two"
  }, /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Teams",
    meta: "12 in Division One"
  }), /*#__PURE__*/React.createElement(TeamRow, {
    position: 1,
    name: "Riverside A",
    venue: "Riverside Club",
    division: "Division One",
    played: 14,
    points: 24
  }), /*#__PURE__*/React.createElement(TeamRow, {
    position: 2,
    name: "Grange A",
    venue: "Grange WMC",
    division: "Division One",
    played: 14,
    points: 22
  }), /*#__PURE__*/React.createElement(TeamRow, {
    position: 3,
    name: "Boro Legion",
    venue: "Boro Legion Club",
    division: "Division One",
    played: 14,
    points: 18
  }), /*#__PURE__*/React.createElement(TeamRow, {
    position: 6,
    name: "Grange B",
    venue: "Grange WMC",
    division: "Division One",
    played: 14,
    points: 6
  })), /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Grange A",
    meta: "Captain: M. Pike"
  }), /*#__PURE__*/React.createElement(PlayerRow, {
    name: "H. Nunn",
    rating: 1923,
    verified: true,
    meta: "12 played"
  }), /*#__PURE__*/React.createElement(PlayerRow, {
    name: "J. Raper",
    rating: 1847,
    verified: true,
    meta: "11 played"
  }), /*#__PURE__*/React.createElement(PlayerRow, {
    name: "C. Dunne",
    rating: 1841,
    meta: "9 played"
  }), /*#__PURE__*/React.createElement(PlayerRow, {
    name: "M. Pike",
    rating: 1794,
    verified: true,
    meta: "14 played"
  })))));
}

/* 9 — Venue operations */
function Venue({
  go
}) {
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Bar, {
    eyebrow: "Grange WMC \xB7 Gateshead",
    title: "Venue operations",
    actions: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Button, {
      variant: "secondary",
      size: "small"
    }, "Venue profile"), /*#__PURE__*/React.createElement(Button, {
      variant: "primary",
      size: "small"
    }, "Open a board"))
  }), /*#__PURE__*/React.createElement("div", {
    className: "body"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 40
    }
  }, /*#__PURE__*/React.createElement(Stat, {
    label: "Boards",
    value: "8",
    size: "large"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "In use",
    value: "5",
    size: "large"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Teams based here",
    value: "3",
    size: "large"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Events this month",
    value: "6",
    size: "large"
  })), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Boards tonight",
    meta: "Tyne League \xB7 Division One"
  }), /*#__PURE__*/React.createElement("div", {
    className: "grid5"
  }, /*#__PURE__*/React.createElement(BoardStatus, {
    board: "1",
    state: "playing",
    round: "League",
    home: "Nunn",
    away: "Doyle",
    score: "2\u20131",
    elapsed: "14 min"
  }), /*#__PURE__*/React.createElement(BoardStatus, {
    board: "2",
    state: "playing",
    round: "League",
    home: "Raper",
    away: "Hall",
    score: "1\u20131",
    elapsed: "9 min"
  }), /*#__PURE__*/React.createElement(BoardStatus, {
    board: "3",
    state: "awaiting",
    round: "League",
    home: "Dunne",
    away: "Frost",
    score: "3\u20132"
  }), /*#__PURE__*/React.createElement(BoardStatus, {
    board: "4",
    state: "free"
  }), /*#__PURE__*/React.createElement(BoardStatus, {
    board: "5",
    state: "closed"
  }))), /*#__PURE__*/React.createElement("div", {
    className: "two"
  }, /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Upcoming here",
    meta: "Next 30 days"
  }), /*#__PURE__*/React.createElement(DataTable, {
    dense: true,
    onRowClick: () => {},
    columns: [{
      key: 'd',
      label: 'Date',
      numeric: true
    }, {
      key: 'e',
      label: 'Event',
      strong: true
    }, {
      key: 't',
      label: 'Type',
      wrap: true
    }, {
      key: 'n',
      label: 'Entries',
      numeric: true
    }, {
      key: 's',
      label: 'State'
    }],
    rows: [['Tue 16 Sep', 'Grange A v Boro Legion', 'League fixture', '—', /*#__PURE__*/React.createElement(Tag, {
      tone: "neutral"
    }, "Scheduled")], ['Thu 18 Sep', 'Thursday Singles', 'Open · 501 Bo5', '34', /*#__PURE__*/React.createElement(Tag, {
      tone: "brand"
    }, "Registration open")], ['Sat 27 Sep', 'Gateshead Pairs', 'Pairs · 501 Bo9', '48', /*#__PURE__*/React.createElement(Tag, {
      tone: "warning"
    }, "Waiting list")], ['Tue 30 Sep', 'Grange B v Tyne Arms', 'League fixture (rearranged)', '—', /*#__PURE__*/React.createElement(Tag, {
      tone: "neutral"
    }, "Scheduled")]].map(([d, e, t, n, s], i) => ({
      id: 'v' + i,
      d,
      e,
      t,
      n,
      s
    }))
  })), /*#__PURE__*/React.createElement("div", {
    className: "sec"
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Venue details",
    meta: "Shown on public profiles"
  }), /*#__PURE__*/React.createElement(DataTable, {
    columns: [{
      key: 'k',
      label: 'Detail'
    }, {
      key: 'v',
      label: '',
      strong: true
    }],
    rows: [{
      id: '1',
      k: 'Boards',
      v: '8 · bristle · LED lighting'
    }, {
      id: '2',
      k: 'Oche',
      v: 'Raised, marked'
    }, {
      id: '3',
      k: 'Step-free access',
      v: 'Yes, main entrance'
    }, {
      id: '4',
      k: 'Accessible WC',
      v: 'Yes'
    }, {
      id: '5',
      k: 'Parking',
      v: 'On site, 40 spaces'
    }, {
      id: '6',
      k: 'Nearest station',
      v: 'Gateshead, 0.6 mi'
    }, {
      id: '7',
      k: 'Scoring',
      v: 'THRØ app · 2 venue scorers'
    }]
  }), /*#__PURE__*/React.createElement("p", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      margin: 0
    }
  }, "Accessibility details appear on the public venue page and in event listings. Players filter on them, so keep them accurate.")))));
}
Object.assign(window, {
  League,
  Venue
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/thro-organiser/screens-admin.jsx", error: String((e && e.message) || e) }); }
