try { (() => {
const D = window.THRDesignSystem_ac73b5;
const {
  TopBar,
  SectionHeader,
  Divider,
  Button,
  Tag,
  Icon,
  ShadowSelector,
  ComparisonChart,
  Stat,
  SegmentedControl,
  RemainingScore,
  TurnIndicator,
  LegState,
  ScoreKeypad,
  MatchHeader,
  MatchSummary,
  Insight,
  EmptyState,
  Confidence,
  Progress
} = D;

/* The Shadow mark: abstract Ø geometry — a circle whose slash is drawn from the
   player's own data. No avatar, no face, no character. The ring segments encode
   the five performance dimensions of the selected model. */
function ShadowMark({
  size = 132,
  dims = [0.86, 0.52, 0.74, 0.61, 0.68],
  theme = 'dark',
  label
}) {
  const r = size / 2 - 6,
    cx = size / 2,
    cy = size / 2;
  return /*#__PURE__*/React.createElement("svg", {
    width: size,
    height: size,
    viewBox: `0 0 ${size} ${size}`,
    role: "img",
    "aria-label": label || 'Shadow model',
    style: {
      display: 'block'
    }
  }, /*#__PURE__*/React.createElement("circle", {
    cx: cx,
    cy: cy,
    r: r,
    fill: "none",
    stroke: "var(--color-border-strong)",
    strokeWidth: "1"
  }), dims.map((v, i) => {
    const a0 = (-90 + i * 72) * Math.PI / 180,
      a1 = (-90 + (i + 1) * 72 - 8) * Math.PI / 180;
    const rr = r * (0.34 + v * 0.66);
    return /*#__PURE__*/React.createElement("path", {
      key: i,
      d: `M ${cx + rr * Math.cos(a0)} ${cy + rr * Math.sin(a0)} A ${rr} ${rr} 0 0 1 ${cx + rr * Math.cos(a1)} ${cy + rr * Math.sin(a1)}`,
      fill: "none",
      stroke: "var(--color-text-brand)",
      strokeWidth: "3",
      strokeLinecap: "butt"
    });
  }), /*#__PURE__*/React.createElement("line", {
    x1: cx - r - 6,
    y1: cy + r + 6,
    x2: cx + r + 6,
    y2: cy - r - 6,
    stroke: "var(--color-text-primary)",
    strokeWidth: "3"
  }));
}
const MODELS = {
  current: {
    name: 'Current You',
    rating: 1847,
    dims: [0.86, 0.52, 0.74, 0.61, 0.68],
    detail: 'Your live statistical model, built from your last 20 rated matches.',
    matches: 20
  },
  season: {
    name: 'Season You',
    rating: 1809,
    dims: [0.81, 0.48, 0.70, 0.58, 0.63],
    detail: 'Every rated match this season, weighted evenly.',
    matches: 42
  },
  peak: {
    name: 'Peak You',
    rating: 1902,
    dims: [0.93, 0.61, 0.84, 0.72, 0.79],
    detail: 'Your best sustained six-match run — March 2026.',
    matches: 6
  },
  pressure: {
    name: 'Pressure You',
    rating: 1794,
    dims: [0.79, 0.44, 0.62, 0.77, 0.58],
    detail: 'Deciding legs only. Finishing drops, nerve holds.',
    matches: 31
  },
  next: {
    name: 'Next Level',
    rating: 1900,
    dims: [0.88, 0.68, 0.80, 0.70, 0.75],
    detail: 'The measured profile of the regional ranked field you are targeting.',
    matches: null
  }
};
const DIMS = ['Scoring', 'Finishing', 'Consistency', 'Pressure', 'First 9'];
function ShadowOverview({
  go
}) {
  const [m, setM] = React.useState('peak');
  const model = MODELS[m];
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    theme: "dark",
    eyebrow: "THR\xD8 Shadow",
    title: "A mathematical mirror",
    onBack: () => go('play'),
    actions: [{
      icon: 'circle-question-mark',
      label: 'How Shadow works'
    }]
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '24px 20px',
      display: 'flex',
      gap: 20,
      alignItems: 'center',
      borderBottom: '1px solid var(--color-border-default)'
    }
  }, /*#__PURE__*/React.createElement(ShadowMark, {
    dims: model.dims,
    label: `${model.name} profile`
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 6,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Selected model"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '800 25px/29px var(--font-ui)',
      letterSpacing: '-.01em',
      color: 'var(--color-text-primary)'
    }
  }, model.name), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '700 40px/40px var(--font-sport)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, model.rating.toLocaleString('en-GB')), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, model.detail))), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '20px 20px 8px'
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Profile",
    meta: model.matches ? `${model.matches} matches` : 'Field benchmark'
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 10
    }
  }, DIMS.map((d, i) => /*#__PURE__*/React.createElement("div", {
    key: d,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 96,
      font: '600 15px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, d), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      height: 8,
      background: 'var(--color-surface-secondary)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'block',
      width: `${Math.round(model.dims[i] * 100)}%`,
      height: '100%',
      background: 'var(--color-background-brand)'
    }
  })), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      width: 34,
      textAlign: 'right',
      font: '600 13px var(--font-sport)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-secondary)'
    }
  }, Math.round(model.dims[i] * 100))))), /*#__PURE__*/React.createElement("p", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      paddingTop: 14,
      margin: 0
    }
  }, "Shadow plays to this profile, not to a difficulty setting. It scores, finishes and misses at the rates your evidence shows.")), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '20px 20px'
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Choose a model"
  }), /*#__PURE__*/React.createElement(ShadowSelector, {
    value: m,
    onChange: setM
  })), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '0 20px 24px'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    size: "large",
    fullWidth: true,
    onClick: () => go('shadow-setup')
  }, "Set up match")));
}
function ShadowSetup({
  go
}) {
  const [m, setM] = React.useState('peak');
  const [game, setGame] = React.useState('501');
  const [len, setLen] = React.useState('9');
  const model = MODELS[m];
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    theme: "dark",
    eyebrow: "THR\xD8 Shadow",
    title: "Match setup",
    onBack: () => go('shadow')
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '24px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 20
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      gap: 16
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 4
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "You"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 21px var(--font-ui)',
      color: 'var(--color-text-primary)',
      whiteSpace: 'nowrap'
    }
  }, "J. Raper"), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '600 21px var(--font-sport)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-secondary)'
    }
  }, "1,847")), /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "vs"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 4,
      textAlign: 'right'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Shadow"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 21px var(--font-ui)',
      color: 'var(--color-text-primary)',
      whiteSpace: 'nowrap'
    }
  }, model.name), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '600 21px var(--font-sport)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-secondary)'
    }
  }, model.rating.toLocaleString('en-GB'))), /*#__PURE__*/React.createElement(ShadowMark, {
    size: 56,
    dims: model.dims,
    label: model.name
  }))), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Model"), /*#__PURE__*/React.createElement(SegmentedControl, {
    items: [{
      id: 'current',
      label: 'Current'
    }, {
      id: 'peak',
      label: 'Peak'
    }, {
      id: 'pressure',
      label: 'Pressure'
    }, {
      id: 'next',
      label: 'Next'
    }],
    value: m,
    onChange: setM
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, model.detail)), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Game"), /*#__PURE__*/React.createElement(SegmentedControl, {
    items: [{
      id: '301',
      label: '301'
    }, {
      id: '501',
      label: '501'
    }, {
      id: '701',
      label: '701'
    }],
    value: game,
    onChange: setGame
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Length"), /*#__PURE__*/React.createElement(SegmentedControl, {
    items: [{
      id: '5',
      label: 'Bo5'
    }, {
      id: '9',
      label: 'Bo9'
    }, {
      id: '11',
      label: 'Bo11'
    }],
    value: len,
    onChange: setLen
  })), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
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
  }, "Shadow matches are not rated and never affect your THR\xD8 Rating or Form. They appear in your practice history only.")), /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    size: "large",
    fullWidth: true,
    onClick: () => go('shadow-play')
  }, "Start against ", model.name)));
}
function ShadowPlay({
  go
}) {
  const [entry, setEntry] = React.useState('');
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      minHeight: '100%'
    }
  }, /*#__PURE__*/React.createElement(MatchHeader, {
    competition: "THR\xD8 Shadow",
    round: "Peak You \xB7 1,902",
    board: "\u2014",
    format: "501 \xB7 Bo9"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '14px 20px 0',
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(LegState, {
    home: 2,
    away: 2,
    bestOf: 9
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement(ShadowMark, {
    size: 26,
    dims: MODELS.peak.dims,
    label: "Peak You"
  }), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '600 13px var(--font-sport)',
      color: 'var(--color-text-secondary)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, "Shadow 218"))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '8px 20px 4px'
    }
  }, /*#__PURE__*/React.createElement(RemainingScore, {
    value: 164,
    label: "You require"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '14px 20px 0',
      display: 'flex',
      flexDirection: 'column',
      gap: 10,
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(TurnIndicator, {
    player: "You",
    dartsThrown: 0
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      textAlign: 'center',
      maxWidth: '34ch'
    }
  }, "Shadow scored 140, 100, 81 \u2014 it is throwing to your March form, not to beat you.")), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(ScoreKeypad, {
    value: entry,
    onDigit: d => setEntry(e => (e + d).slice(0, 3)),
    onScore: () => go('shadow-result'),
    onUndo: () => setEntry(''),
    onMiss: () => setEntry('0')
  }));
}
function ShadowResult({
  go
}) {
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    eyebrow: "THR\xD8 Shadow \xB7 Peak You",
    title: "Practice result",
    onBack: () => go('shadow')
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '24px 20px 20px'
    }
  }, /*#__PURE__*/React.createElement(MatchSummary, {
    result: "loss",
    score: "4\u20135",
    opponent: "vs Peak You \xB7 1,902",
    stats: [{
      label: '3-dart average',
      value: '88.1'
    }, {
      label: 'Peak You average',
      value: '91.4'
    }, {
      label: 'Checkout %',
      value: '39%'
    }, {
      label: 'Peak You checkout',
      value: '47%'
    }]
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      paddingTop: 16
    }
  }, /*#__PURE__*/React.createElement(Tag, {
    tone: "neutral",
    icon: "info"
  }, "Not rated"))), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '24px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 20
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Where the match was decided"
  }), /*#__PURE__*/React.createElement(ComparisonChart, {
    youLabel: "You today",
    benchmarkLabel: "Peak You",
    rows: [{
      label: 'Scoring',
      value: 88.1,
      benchmark: 91.4,
      max: 110
    }, {
      label: 'Finishing',
      value: 39,
      benchmark: 47,
      max: 60,
      unit: '%'
    }, {
      label: 'First 9',
      value: 92.6,
      benchmark: 96.1,
      max: 110
    }]
  }), /*#__PURE__*/React.createElement(Insight, {
    eyebrow: "What this tells you",
    headline: "Eight points of finishing",
    tone: "neutral",
    evidence: "Your scoring was within three points of your best sustained run. The match turned on eight percentage points of finishing across four legs.",
    actionTitle: "Finishing 41\u201360 \xB7 10 minutes",
    actionLabel: "Open Coach",
    onAction: () => go('coach')
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    size: "large",
    fullWidth: true,
    onClick: () => go('shadow-setup')
  }, "Play again")));
}
Object.assign(window, {
  ShadowMark,
  ShadowOverview,
  ShadowSetup,
  ShadowPlay,
  ShadowResult
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/thro-app/screens-shadow.jsx", error: String((e && e.message) || e) }); }
