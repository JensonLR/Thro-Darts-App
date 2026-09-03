try { (() => {
const D = window.THRDesignSystem_ac73b5;
const {
  TopBar,
  SectionHeader,
  Button,
  Tag,
  Divider,
  Icon,
  RatingHero,
  RatingCompact,
  Progress,
  Insight,
  EventRow,
  PlayerIdentity,
  LiveIndicator,
  Confidence,
  EmptyState,
  Notification
} = D;
function Block({
  children,
  style
}) {
  return /*#__PURE__*/React.createElement("section", {
    className: "gutter",
    style: {
      padding: '24px 20px',
      ...style
    }
  }, children);
}
function HomeActive({
  go
}) {
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    large: true,
    eyebrow: "Saturday 14 September",
    title: "Home",
    actions: [{
      icon: 'bell',
      label: 'Notifications'
    }]
  }), /*#__PURE__*/React.createElement(Block, {
    style: {
      paddingBottom: 8
    }
  }, /*#__PURE__*/React.createElement(RatingHero, {
    rating: 1847,
    delta: 27,
    band: "Elite Amateur",
    rankCountry: "#183",
    rankRegion: "#14",
    form: 1921
  })), /*#__PURE__*/React.createElement(Block, {
    style: {
      paddingTop: 16
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Next",
    action: "All events",
    onAction: () => go('discover')
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 4
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 21px/26px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, "North East Open"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 15px/20px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, "Saturday 12:30 \xB7 Sunderland Sports Centre"), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      flexWrap: 'wrap',
      gap: 8,
      paddingTop: 4
    }
  }, /*#__PURE__*/React.createElement(Tag, {
    tone: "brand"
  }, "Registered"), /*#__PURE__*/React.createElement(Tag, {
    tone: "neutral"
  }, "Board pending"))), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    size: "small",
    onClick: () => go('event')
  }, "Event detail"))), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), /*#__PURE__*/React.createElement(Block, null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Progress"
  }), /*#__PURE__*/React.createElement(Progress, {
    label: "Toward 1,900 benchmark",
    value: 57,
    max: 100,
    valueLabel: "57 points"
  })), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), /*#__PURE__*/React.createElement(Block, null, /*#__PURE__*/React.createElement(Insight, {
    headline: "Finishing",
    evidence: "Your scoring matches the 1,900 field. Finishing efficiency is the clearest current opportunity.",
    actionTitle: "15-minute finishing session",
    actionLabel: "Open Coach",
    onAction: () => go('coach')
  })), /*#__PURE__*/React.createElement(Block, {
    style: {
      paddingTop: 8
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Live",
    action: "All live",
    onAction: () => go('live')
  }), /*#__PURE__*/React.createElement("button", {
    onClick: () => go('live-match'),
    style: {
      width: '100%',
      textAlign: 'left',
      background: 'none',
      border: 0,
      padding: 0,
      cursor: 'pointer',
      display: 'flex',
      flexDirection: 'column',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement(LiveIndicator, null), /*#__PURE__*/React.createElement(PlayerIdentity, {
    name: "Harry Nunn",
    rating: 1902,
    team: "Grange A"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, "Durham Masters \xB7 Semi final \xB7 Board 4"))), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 16
    }
  }));
}
function HomeMatchCalled({
  go
}) {
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    large: true,
    eyebrow: "North East Open",
    title: "Home",
    actions: [{
      icon: 'bell',
      label: 'Notifications'
    }]
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      background: 'var(--thro-ink)',
      padding: '28px 20px 32px',
      display: 'flex',
      flexDirection: 'column',
      gap: 16
    },
    "data-theme": "dark"
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      font: '700 13px/16px var(--font-ui)',
      letterSpacing: '.09em',
      textTransform: 'uppercase',
      color: 'var(--color-status-live)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "bell-ring",
    size: 16
  }), "Your match has been called"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '600 15px var(--font-sport)',
      letterSpacing: '.08em',
      textTransform: 'uppercase',
      color: '#A7ADAA'
    }
  }, "Round of 64"), /*#__PURE__*/React.createElement("span", {
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
  }, "vs Alex Wilson \xB7 1,903")), /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    size: "large",
    fullWidth: true,
    onClick: () => go('ready')
  }, "Go to match"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px/18px var(--font-ui)',
      color: '#A7ADAA'
    }
  }, "Report to board 14. The organiser has been notified that you have seen this call.")), /*#__PURE__*/React.createElement(Block, null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Everything else",
    meta: "Muted while you are called"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      opacity: .55
    }
  }, /*#__PURE__*/React.createElement(Notification, {
    type: "development",
    title: "Finishing is your clearest current opportunity",
    time: "1h"
  }), /*#__PURE__*/React.createElement(Notification, {
    type: "social",
    title: "Danny Kerr won the Boro Open",
    time: "3h"
  }))));
}
function HomeNewPlayer({
  go
}) {
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    large: true,
    title: "Home"
  }), /*#__PURE__*/React.createElement(Block, {
    style: {
      paddingBottom: 8
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "THR\xD8 Rating"), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '700 56px/54px var(--font-sport)',
      color: 'var(--color-text-primary)'
    }
  }, "\u2014"), /*#__PURE__*/React.createElement(Tag, {
    tone: "warning",
    icon: "clock"
  }, "Rating establishing"), /*#__PURE__*/React.createElement(Confidence, {
    level: "low",
    matches: 2,
    required: 10,
    explain: true
  }), /*#__PURE__*/React.createElement("p", {
    style: {
      font: '400 15px/22px var(--font-ui)',
      color: 'var(--color-text-secondary)',
      maxWidth: '40ch'
    }
  }, "The system is still learning your competitive level. Two qualifying matches complete."))), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), /*#__PURE__*/React.createElement(Block, null, /*#__PURE__*/React.createElement(EmptyState, {
    title: "No rated matches yet",
    message: "Play qualifying matches to begin establishing your THR\xD8 Rating.",
    actionLabel: "Start match",
    onAction: () => go('ready')
  })), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), /*#__PURE__*/React.createElement(Block, null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Near you",
    action: "Discover",
    onAction: () => go('discover')
  }), /*#__PURE__*/React.createElement(EventRow, {
    name: "Tuesday Singles",
    date: "Tue 17 Sep \xB7 19:30",
    venue: "Grange WMC",
    distance: "4.2 mi",
    format: "501 \xB7 Bo5",
    entry: "Free",
    fit: "good"
  })));
}
Object.assign(window, {
  HomeActive,
  HomeMatchCalled,
  HomeNewPlayer,
  Block
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/thro-app/screens-home.jsx", error: String((e && e.message) || e) }); }
