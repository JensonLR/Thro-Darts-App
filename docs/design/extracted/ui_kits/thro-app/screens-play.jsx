try { (() => {
const D = window.THRDesignSystem_ac73b5;
const {
  TopBar,
  MatchHeader,
  PlayerComparison,
  Button,
  RemainingScore,
  Checkout,
  TurnIndicator,
  LegState,
  ScoreKeypad,
  OfflineState,
  SyncState,
  MatchSummary,
  RatingMovement,
  SectionHeader,
  Divider,
  Tag,
  Icon,
  VerificationState,
  TournamentProgress,
  Snackbar
} = D;
function MatchReady({
  go
}) {
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    eyebrow: "North East Open",
    title: "Round of 64",
    onBack: () => go('home-called'),
    actions: [{
      icon: 'ellipsis',
      label: 'More'
    }]
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '28px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 24
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 2,
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Board"), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '700 96px/88px var(--font-sport)',
      letterSpacing: '-.03em',
      color: 'var(--color-text-primary)'
    }
  }, "14")), /*#__PURE__*/React.createElement(PlayerComparison, {
    home: {
      name: 'Jenson Raper',
      rating: 1847,
      team: 'Grange A',
      verified: true
    },
    away: {
      name: 'Alex Wilson',
      rating: 1903,
      team: 'Sunderland B'
    },
    rows: [{
      label: 'Form',
      home: '1,921',
      away: '1,880'
    }, {
      label: 'Avg',
      home: '89.3',
      away: '87.7'
    }, {
      label: 'Checkout',
      home: '42%',
      away: '38%'
    }]
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexWrap: 'wrap',
      gap: 8,
      justifyContent: 'center'
    }
  }, /*#__PURE__*/React.createElement(Tag, {
    tone: "neutral"
  }, "501"), /*#__PURE__*/React.createElement(Tag, {
    tone: "neutral"
  }, "Best of 9"), /*#__PURE__*/React.createElement(Tag, {
    tone: "neutral"
  }, "Double out")), /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    size: "large",
    fullWidth: true,
    onClick: () => go('scoring')
  }, "I'm ready"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      textAlign: 'center'
    }
  }, "Both players must confirm before scoring opens. Alex Wilson confirmed 40 seconds ago.")));
}
function ScoringBase({
  go,
  state
}) {
  const checkout = state === 'checkout',
    bust = state === 'bust',
    offline = state === 'offline';
  const [entry, setEntry] = React.useState(checkout ? '121' : bust ? '186' : '60');
  const remaining = checkout ? 121 : bust ? 186 : 301;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      minHeight: '100%'
    }
  }, /*#__PURE__*/React.createElement(MatchHeader, {
    competition: "North East Open",
    round: "Round of 64",
    board: "14",
    format: "501 \xB7 Bo9"
  }), offline ? /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '12px 20px 0'
    }
  }, /*#__PURE__*/React.createElement(OfflineState, {
    inline: true
  })) : null, state === 'syncing' ? /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '12px 20px 0'
    }
  }, /*#__PURE__*/React.createElement(SyncState, {
    state: "syncing"
  })) : null, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '20px 20px 8px',
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(LegState, {
    home: 2,
    away: 1,
    bestOf: 9
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '600 13px var(--font-sport)',
      color: 'var(--color-text-secondary)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, "Wilson 274")), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '8px 20px 4px'
    }
  }, bust ? /*#__PURE__*/React.createElement(RemainingScore, {
    value: remaining,
    state: "bust"
  }) : /*#__PURE__*/React.createElement(RemainingScore, {
    value: remaining,
    state: checkout ? 'checkout' : 'normal',
    darts: checkout ? '3 darts remaining' : undefined
  })), checkout ? /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '8px 20px 0'
    }
  }, /*#__PURE__*/React.createElement(Checkout, {
    required: 121,
    route: ['T20', 'T11', 'D14'],
    compact: true,
    hideValue: true
  })) : null, bust ? /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '12px 20px 0'
    }
  }, /*#__PURE__*/React.createElement(Snackbar, {
    message: "Bust. Score restored to 186. Wilson to throw.",
    tone: "error"
  })) : null, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '16px 20px 4px',
      display: 'flex',
      justifyContent: 'center'
    }
  }, /*#__PURE__*/React.createElement(TurnIndicator, {
    player: bust ? 'Wilson' : 'You',
    dartsThrown: bust ? 0 : 2,
    active: !bust
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(ScoreKeypad, {
    value: entry,
    onDigit: d => setEntry(e => (e + d).slice(0, 3)),
    onScore: () => go('result'),
    onUndo: () => setEntry(''),
    onMiss: () => setEntry('0'),
    disabled: bust
  }));
}
const ScoringStandard = ({
  go
}) => /*#__PURE__*/React.createElement(ScoringBase, {
  go: go,
  state: "standard"
});
const ScoringCheckout = ({
  go
}) => /*#__PURE__*/React.createElement(ScoringBase, {
  go: go,
  state: "checkout"
});
const ScoringBust = ({
  go
}) => /*#__PURE__*/React.createElement(ScoringBase, {
  go: go,
  state: "bust"
});
const ScoringOffline = ({
  go
}) => /*#__PURE__*/React.createElement(ScoringBase, {
  go: go,
  state: "offline"
});
function MatchResult({
  go
}) {
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    eyebrow: "North East Open",
    title: "Round of 64",
    onBack: () => go('home')
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '28px 20px 20px'
    }
  }, /*#__PURE__*/React.createElement(MatchSummary, {
    result: "win",
    score: "5\u20133",
    opponent: "vs Alex Wilson \xB7 1,903",
    stats: [{
      label: '3-dart average',
      value: '89.4'
    }, {
      label: 'First 9',
      value: '94.2'
    }, {
      label: 'Checkout %',
      value: '42%'
    }, {
      label: '180s',
      value: '3'
    }, {
      label: 'Highest checkout',
      value: '141'
    }, {
      label: '140+',
      value: '7'
    }]
  })), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '24px 20px'
    }
  }, /*#__PURE__*/React.createElement(RatingMovement, {
    before: 1821,
    after: 1847,
    opponent: "Defeated Alex Wilson, rated 1,903.",
    reason: "Above-baseline competitive result against a stronger opponent."
  })), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '24px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 16
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Evidence"
  }), /*#__PURE__*/React.createElement(VerificationState, {
    state: "thro-verified",
    explain: true
  }), /*#__PURE__*/React.createElement(SyncState, {
    state: "synced"
  })), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '24px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 16
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Tournament"
  }), /*#__PURE__*/React.createElement(TournamentProgress, {
    rounds: [{
      round: 'Round of 64',
      opponent: 'Alex Wilson',
      score: '5–3',
      state: 'won'
    }, {
      round: 'Round of 32',
      opponent: 'Danny Kerr',
      state: 'active'
    }, {
      round: 'Round of 16',
      state: 'future'
    }],
    nextLabel: "Next: Board 9 \xB7 approx. 14:10"
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    fullWidth: true,
    onClick: () => go('home-called')
  }, "Back to tournament")));
}
Object.assign(window, {
  MatchReady,
  ScoringStandard,
  ScoringCheckout,
  ScoringBust,
  ScoringOffline,
  MatchResult
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/thro-app/screens-play.jsx", error: String((e && e.message) || e) }); }
