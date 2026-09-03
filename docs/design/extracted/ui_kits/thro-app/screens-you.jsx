try { (() => {
const D = window.THRDesignSystem_ac73b5;
const {
  TopBar,
  SectionHeader,
  Divider,
  PlayerIdentity,
  RatingHero,
  RatingCompact,
  Rank,
  FormIndicator,
  Confidence,
  TrendChart,
  ComparisonChart,
  Stat,
  Insight,
  Button,
  Tag,
  Icon,
  SegmentedControl,
  PathwayStep,
  TrainingSession,
  Tabs,
  VerificationState
} = D;
function You({
  go
}) {
  const [tab, setTab] = React.useState('overview');
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    large: true,
    eyebrow: "Grange A \xB7 North East",
    title: "Jenson Raper",
    actions: [{
      icon: 'settings',
      label: 'Settings'
    }]
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '8px 20px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 20
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 28,
      alignItems: 'flex-start'
    }
  }, /*#__PURE__*/React.createElement(RatingCompact, {
    rating: 1847,
    delta: 27
  }), /*#__PURE__*/React.createElement(Rank, {
    position: 183,
    scope: "UK"
  }), /*#__PURE__*/React.createElement(Rank, {
    position: 14,
    scope: "North East"
  })), /*#__PURE__*/React.createElement(FormIndicator, {
    results: ['W', 'W', 'L', 'W', 'L'],
    form: 1921
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    size: "small",
    onClick: () => go('rating')
  }, "Rating detail"), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    size: "small",
    onClick: () => go('coach')
  }, "Coach"), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    size: "small",
    onClick: () => go('passport')
  }, "Passport"))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 20px'
    }
  }, /*#__PURE__*/React.createElement(Tabs, {
    items: [{
      id: 'overview',
      label: 'Overview'
    }, {
      id: 'stats',
      label: 'Statistics'
    }, {
      id: 'pathway',
      label: 'Pathway'
    }],
    value: tab,
    onChange: setTab
  })), tab === 'overview' ? /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '20px 20px 24px',
      display: 'flex',
      flexDirection: 'column',
      gap: 24
    }
  }, /*#__PURE__*/React.createElement(TrendChart, {
    points: [1780, 1795, 1788, 1810, 1824, 1821, 1847],
    label: "Rating \xB7 last 7 rated matches",
    reference: 1900
  }), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Recent matches"
  }), [['North East Open · R64', '5–3', 'W'], ['Tyne League · Grange A', '4–5', 'L'], ['Boro Open · R32', '5–1', 'W']].map(([m, s, r]) => /*#__PURE__*/React.createElement("div", {
    key: m,
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      padding: '12px 0',
      borderBottom: '1px solid var(--color-border-default)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 15px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, m), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      gap: 10,
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '700 17px var(--font-sport)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, s), /*#__PURE__*/React.createElement("span", {
    style: {
      width: 22,
      height: 22,
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      borderRadius: 2,
      font: '700 12px var(--font-sport)',
      background: r === 'W' ? 'var(--thro-green)' : 'var(--color-surface-secondary)',
      color: r === 'W' ? 'var(--thro-chalk)' : 'var(--color-text-secondary)'
    }
  }, r))))), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Team"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 21px var(--font-ui)'
    }
  }, "Grange A"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 15px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, "Tyne League \xB7 Division One \xB7 2nd of 12"))) : tab === 'stats' ? /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '20px 20px 24px',
      display: 'flex',
      flexDirection: 'column',
      gap: 24
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: '1fr 1fr',
      gap: 20
    }
  }, /*#__PURE__*/React.createElement(Stat, {
    label: "3-dart average",
    value: "89.4",
    delta: 1.6
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "First 9",
    value: "94.2",
    delta: 0.8
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Checkout %",
    value: "42",
    unit: "%"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Highest checkout",
    value: "141"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "180s \xB7 season",
    value: "38"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Leg win rate",
    value: "54",
    unit: "%"
  })), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(ComparisonChart, {
    rows: [{
      label: 'Scoring',
      value: 89.4,
      benchmark: 90.1,
      max: 110
    }, {
      label: 'Finishing',
      value: 42,
      benchmark: 48,
      max: 60,
      unit: '%'
    }, {
      label: 'First 9',
      value: 94.2,
      benchmark: 95.0,
      max: 110
    }, {
      label: 'Pressure legs',
      value: 47,
      benchmark: 52,
      max: 70,
      unit: '%'
    }]
  })) : /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '20px 20px 24px'
    }
  }, /*#__PURE__*/React.createElement(PathwayStep, {
    label: "Local league field",
    rating: "1,700",
    state: "reached",
    context: "You compete here weekly."
  }), /*#__PURE__*/React.createElement(PathwayStep, {
    label: "County open field",
    rating: "1,760",
    state: "reached",
    context: "You have reached three quarter finals."
  }), /*#__PURE__*/React.createElement(PathwayStep, {
    label: "Regional ranked field",
    rating: "1,900",
    state: "current",
    gap: "Finishing +6% closes most of this.",
    context: "Your target competitive context. Eight events within 30 miles this season."
  }), /*#__PURE__*/React.createElement(PathwayStep, {
    label: "National open field",
    rating: "2,050",
    state: "future",
    context: "Open entry. Recommended once regional results are consistent.",
    last: true
  })));
}
function RatingDetail({
  go
}) {
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    eyebrow: "THR\xD8 Rating",
    title: "1,847",
    onBack: () => go('you'),
    actions: [{
      icon: 'circle-question-mark',
      label: 'How rating works'
    }]
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '24px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 24
    }
  }, /*#__PURE__*/React.createElement(RatingHero, {
    rating: 1847,
    delta: 27,
    band: "Elite Amateur",
    rankCountry: "#183",
    rankRegion: "#14",
    form: 1921
  }), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(TrendChart, {
    points: [1712, 1740, 1755, 1780, 1795, 1788, 1810, 1824, 1821, 1847],
    label: "Rating \xB7 10 rated matches",
    reference: 1900
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 32
    }
  }, /*#__PURE__*/React.createElement(Stat, {
    label: "Personal best",
    value: "1,847"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Season low",
    value: "1,712"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Rated matches",
    value: "42"
  })), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(Confidence, {
    level: "high",
    matches: 42,
    required: 10,
    explain: false
  }), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Why your rating moved"
  }), [['Defeated Alex Wilson · 1,903', '+26'], ['Lost to Harry Nunn · 1,923', '+4'], ['Defeated Chris Dunne · 1,841', '+7']].map(([t, d]) => /*#__PURE__*/React.createElement("div", {
    key: t,
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      padding: '12px 0',
      borderBottom: '1px solid var(--color-border-default)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 15px var(--font-ui)'
    }
  }, t), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '600 15px var(--font-sport)',
      color: 'var(--color-status-success)'
    }
  }, d)))), /*#__PURE__*/React.createElement("p", {
    style: {
      font: '400 15px/22px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      margin: 0
    }
  }, "Rating estimates competitive strength across your recent rated matches, weighted by opponent strength. Form reflects your last five results only.")));
}
function CoachInsight({
  go
}) {
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    eyebrow: "THR\xD8 Coach",
    title: "Your game",
    onBack: () => go('you')
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '20px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 20
    }
  }, [['Scoring', 'Strong', 'success'], ['Finishing', 'Opportunity', 'warning'], ['Consistency', 'Stable', 'neutral'], ['Pressure', 'Improving', 'info']].map(([k, v, t]) => /*#__PURE__*/React.createElement("div", {
    key: k,
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      borderBottom: '1px solid var(--color-border-default)',
      paddingBottom: 12
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 21px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, k), /*#__PURE__*/React.createElement(Tag, {
    tone: t
  }, v)))), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '4px 20px 24px',
      display: 'flex',
      flexDirection: 'column',
      gap: 24
    }
  }, /*#__PURE__*/React.createElement(Insight, {
    headline: "Finishing",
    evidence: "From 41\u201360 you convert 31% of visits. Players at 1,900 convert 44% from the same range. Your scoring already matches that level.",
    actionTitle: "15-minute finishing session",
    actionLabel: "Start session"
  }), /*#__PURE__*/React.createElement(ComparisonChart, {
    rows: [{
      label: 'Checkout 41–60',
      value: 31,
      benchmark: 44,
      max: 60,
      unit: '%'
    }, {
      label: 'Checkout 61–100',
      value: 26,
      benchmark: 31,
      max: 50,
      unit: '%'
    }, {
      label: 'Doubles hit rate',
      value: 38,
      benchmark: 45,
      max: 60,
      unit: '%'
    }]
  }), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(TrainingSession, {
    title: "Today",
    duration: "20 min",
    focus: "Built around finishing 41\u201360",
    drills: [{
      name: 'Doubles ladder',
      length: '5 min'
    }, {
      name: 'Finishing 41–60',
      length: '5 min'
    }, {
      name: 'Scoring · 501',
      length: '5 min'
    }, {
      name: 'Pressure simulation',
      length: '5 min'
    }],
    onStart: () => go('you')
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Transfer"), /*#__PURE__*/React.createElement("p", {
    style: {
      font: '400 15px/22px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      margin: 0
    }
  }, "Practice improvement in this range has not yet appeared under competitive conditions. Four more rated matches will confirm transfer."))));
}
function Passport({
  go
}) {
  const items = [['2026', 'Career-best rating 1,847', 'milestone'], ['2026', 'First regional semi final · North East Open', 'event'], ['2025', 'First established rating · 1,712', 'rating'], ['2025', 'First tournament win · Boro Singles', 'trophy'], ['2024', 'First rated match · Tyne League', 'start'], ['2024', 'Joined THRØ', 'start']];
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    eyebrow: "THR\xD8 Passport",
    title: "Jenson Raper",
    onBack: () => go('you')
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '20px 20px 8px',
      display: 'flex',
      gap: 24
    }
  }, /*#__PURE__*/React.createElement(Stat, {
    label: "Rated matches",
    value: "42"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Tournaments",
    value: "9"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Titles",
    value: "1"
  })), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '20px 20px 24px'
    }
  }, items.map(([y, t, k], i) => /*#__PURE__*/React.createElement("div", {
    key: t,
    style: {
      display: 'flex',
      gap: 16
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      width: 24
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: k === 'milestone' ? 'award' : k === 'trophy' ? 'trophy' : k === 'rating' ? 'circle-check' : k === 'event' ? 'target' : 'circle',
    size: 18,
    color: k === 'milestone' || k === 'trophy' ? 'var(--color-text-achievement)' : 'var(--color-text-secondary)'
  }), i < items.length - 1 ? /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      width: 1,
      background: 'var(--color-border-default)',
      minHeight: 28
    }
  }) : null), /*#__PURE__*/React.createElement("div", {
    style: {
      paddingBottom: 24,
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, y), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '600 17px/24px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, t))))));
}
Object.assign(window, {
  You,
  RatingDetail,
  CoachInsight,
  Passport
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/thro-app/screens-you.jsx", error: String((e && e.message) || e) }); }
