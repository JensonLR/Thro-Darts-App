try { (() => {
const D = window.THRDesignSystem_ac73b5;
const {
  TopBar,
  SectionHeader,
  Divider,
  LiveIndicator,
  PlayerIdentity,
  PlayerComparison,
  Icon,
  FilterChip,
  Tag,
  ScoreHero,
  Stat,
  Button,
  SegmentedControl
} = D;
function LiveDirectory({
  go
}) {
  const rows = [['Durham Masters', 'Semi final', 'Board 4', 'Harry Nunn', 'Danny Kerr', '4', '3'], ['North East Open', 'Round of 32', 'Board 11', 'S. Patel', 'L. Okafor', '2', '1'], ['Tyne League', 'Division One', 'Grange WMC', 'Grange A', 'Boro Legion', '5', '4']];
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    large: true,
    title: "Live",
    actions: [{
      icon: 'search',
      label: 'Search'
    }]
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 20px 16px',
      display: 'flex',
      gap: 8,
      overflowX: 'auto'
    }
  }, /*#__PURE__*/React.createElement(FilterChip, {
    selected: true
  }, "Following"), /*#__PURE__*/React.createElement(FilterChip, null, "Tournaments"), /*#__PURE__*/React.createElement(FilterChip, null, "Leagues"), /*#__PURE__*/React.createElement(FilterChip, null, "Near you")), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '20px 20px 8px'
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Live now",
    meta: "7 matches"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 20px'
    }
  }, rows.map(r => /*#__PURE__*/React.createElement("button", {
    key: r[2],
    onClick: () => go('live-match'),
    style: {
      width: '100%',
      textAlign: 'left',
      background: 'none',
      border: 0,
      borderBottom: '1px solid var(--color-border-default)',
      padding: '14px 0',
      cursor: 'pointer',
      display: 'flex',
      flexDirection: 'column',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '600 13px var(--font-ui)',
      letterSpacing: '.06em',
      textTransform: 'uppercase',
      color: 'var(--color-text-secondary)'
    }
  }, r[0], " \xB7 ", r[1]), /*#__PURE__*/React.createElement(LiveIndicator, {
    size: "small"
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 17px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, r[3]), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '700 21px var(--font-sport)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, r[5], "\u2013", r[6]), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 17px var(--font-ui)',
      color: 'var(--color-text-primary)',
      textAlign: 'right',
      flex: 1
    }
  }, r[4])), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, r[2])))));
}
function LiveMatchCentre({
  go
}) {
  const [tab, setTab] = React.useState('match');
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    theme: "dark",
    eyebrow: "Durham Masters",
    title: "Semi final",
    onBack: () => go('live'),
    actions: [{
      icon: 'share',
      label: 'Share'
    }]
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--thro-ink-sunken)',
      aspectRatio: '16/9',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      flexDirection: 'column',
      gap: 8,
      color: 'var(--color-text-secondary)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "video",
    size: 28
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px var(--font-ui)'
    }
  }, "Stream placeholder \u2014 venue feed")), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '16px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 16
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(LiveIndicator, null), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '600 13px var(--font-sport)',
      color: 'var(--color-text-secondary)'
    }
  }, "Board 4 \xB7 Leg 8")), /*#__PURE__*/React.createElement(ScoreHero, {
    home: 4,
    away: 3,
    homeLabel: "Nunn",
    awayLabel: "Kerr",
    unit: "Legs"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      borderTop: '1px solid var(--color-border-default)',
      paddingTop: 16
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "thro-sport",
    style: {
      font: '700 40px var(--font-sport)',
      color: 'var(--color-text-primary)'
    }
  }, "121"), /*#__PURE__*/React.createElement("div", {
    style: {
      textAlign: 'center',
      alignSelf: 'center'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Remaining")), /*#__PURE__*/React.createElement("div", {
    className: "thro-sport",
    style: {
      font: '700 40px var(--font-sport)',
      color: 'var(--color-text-primary)'
    }
  }, "274")), /*#__PURE__*/React.createElement(SegmentedControl, {
    items: [{
      id: 'match',
      label: 'Match'
    }, {
      id: 'stats',
      label: 'Statistics'
    }, {
      id: 'players',
      label: 'Players'
    }],
    value: tab,
    onChange: setTab
  }), tab === 'stats' ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: '1fr 1fr',
      gap: 16
    }
  }, /*#__PURE__*/React.createElement(Stat, {
    label: "Avg",
    value: "89.3"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Avg",
    value: "87.7",
    align: "right"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Checkout",
    value: "42%"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Checkout",
    value: "38%",
    align: "right"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "180s",
    value: "4"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "180s",
    value: "2",
    align: "right"
  })) : tab === 'players' ? /*#__PURE__*/React.createElement(PlayerComparison, {
    theme: "dark",
    home: {
      name: 'Harry Nunn',
      rating: 1923,
      verified: true
    },
    away: {
      name: 'Danny Kerr',
      rating: 1906
    },
    rows: [{
      label: 'Rank',
      home: '#94',
      away: '#121'
    }, {
      label: 'Form',
      home: '1,940',
      away: '1,899'
    }]
  }) : /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 10
    }
  }, [['Leg 8', 'Nunn 140, Kerr 100'], ['Leg 7', 'Nunn checkout 84 — Nunn wins leg'], ['Leg 6', 'Kerr checkout 40 — Kerr wins leg']].map(([l, t]) => /*#__PURE__*/React.createElement("div", {
    key: l,
    style: {
      display: 'flex',
      gap: 12,
      borderBottom: '1px solid var(--color-border-default)',
      paddingBottom: 10
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '600 13px var(--font-sport)',
      color: 'var(--color-text-secondary)',
      width: 44
    }
  }, l), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 15px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, t)))), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    fullWidth: true,
    onClick: () => go('live')
  }, "Follow this match")));
}
Object.assign(window, {
  LiveDirectory,
  LiveMatchCentre
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/thro-app/screens-live.jsx", error: String((e && e.message) || e) }); }
