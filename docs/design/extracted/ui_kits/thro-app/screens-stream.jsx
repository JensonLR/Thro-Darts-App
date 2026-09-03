try { (() => {
const D = window.THRDesignSystem_ac73b5;
const {
  TopBar,
  SectionHeader,
  Divider,
  Button,
  Tag,
  Icon,
  IconButton,
  LiveIndicator,
  PlayerIdentity,
  Stat,
  SegmentedControl,
  FilterChip,
  ErrorState,
  Progress
} = D;

/* Broadcast overlay: the competitive state, rendered over the feed. Readable at
   arm's length on a phone and on a venue screen. Ink block, never a scrim. */
function StreamOverlay({
  home,
  away,
  remaining
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      left: 0,
      right: 0,
      bottom: 0,
      background: 'rgba(8,10,9,0.94)',
      padding: '10px 12px',
      display: 'flex',
      alignItems: 'center',
      gap: 10
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0,
      display: 'flex',
      flexDirection: 'column',
      gap: 1
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 15px var(--font-ui)',
      color: 'var(--thro-chalk)',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, home.name), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '600 12px var(--font-sport)',
      color: '#A7ADAA',
      fontVariantNumeric: 'tabular-nums'
    }
  }, home.rating.toLocaleString('en-GB'), " \xB7 ", home.avg, " avg")), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '700 34px/32px var(--font-sport)',
      letterSpacing: '-.02em',
      color: 'var(--thro-chalk)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, home.legs, "\u2013", away.legs), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0,
      display: 'flex',
      flexDirection: 'column',
      gap: 1,
      textAlign: 'right'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 15px var(--font-ui)',
      color: 'var(--thro-chalk)',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, away.name), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '600 12px var(--font-sport)',
      color: '#A7ADAA',
      fontVariantNumeric: 'tabular-nums'
    }
  }, away.rating.toLocaleString('en-GB'), " \xB7 ", away.avg, " avg")), remaining ? /*#__PURE__*/React.createElement("span", {
    style: {
      flex: '0 0 auto',
      borderLeft: '1px solid #2C312E',
      paddingLeft: 10,
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 10px var(--font-ui)',
      letterSpacing: '.09em',
      textTransform: 'uppercase',
      color: '#A7ADAA'
    }
  }, "Req"), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '700 24px var(--font-sport)',
      color: 'var(--thro-chalk)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, remaining)) : null);
}
function StreamView({
  go
}) {
  const [state, setState] = React.useState('playing');
  const [tab, setTab] = React.useState('boards');
  const home = {
    name: 'H. Nunn',
    rating: 1923,
    avg: '89.3',
    legs: 4
  };
  const away = {
    name: 'D. Kerr',
    rating: 1906,
    avg: '87.7',
    legs: 3
  };
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    theme: "dark",
    eyebrow: "Durham Masters",
    title: "Semi final \xB7 Board 4",
    onBack: () => go('live'),
    actions: [{
      icon: 'share',
      label: 'Share'
    }, {
      icon: 'heart',
      label: 'Follow'
    }]
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      background: 'var(--thro-ink-sunken)',
      aspectRatio: '16/9',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      flexDirection: 'column',
      gap: 10,
      color: 'var(--color-text-secondary)'
    }
  }, state === 'playing' ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Icon, {
    name: "video",
    size: 30
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px var(--font-ui)'
    }
  }, "Venue feed \xB7 1080p"), /*#__PURE__*/React.createElement(StreamOverlay, {
    home: home,
    away: away,
    remaining: 121
  })) : state === 'buffering' ? /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Icon, {
    name: "refresh-cw",
    size: 26
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '600 13px var(--font-ui)'
    }
  }, "Reconnecting to the venue feed"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px var(--font-ui)',
      color: 'var(--color-text-tertiary)'
    }
  }, "Scores continue below"), /*#__PURE__*/React.createElement(StreamOverlay, {
    home: home,
    away: away,
    remaining: 121
  })) : /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 20px',
      width: '100%'
    }
  }, /*#__PURE__*/React.createElement(ErrorState, {
    title: "Stream unavailable",
    what: "The venue has not started a feed for this board.",
    safe: "Live scoring is unaffected \u2014 every leg is still recorded.",
    todo: "Follow the match to be notified if a feed starts.",
    actionLabel: "Follow this match",
    onAction: () => setState('playing')
  }))), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '14px 20px 8px',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement(LiveIndicator, null), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      gap: 6
    }
  }, /*#__PURE__*/React.createElement(IconButton, {
    icon: "settings",
    label: "Stream quality",
    size: 40,
    variant: "outlined",
    onClick: () => setState(state === 'playing' ? 'buffering' : state === 'buffering' ? 'unavailable' : 'playing')
  }), /*#__PURE__*/React.createElement(IconButton, {
    icon: "chart-no-axes-column",
    label: "Match statistics",
    size: 40,
    variant: "outlined"
  }))), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '8px 20px 12px'
    }
  }, /*#__PURE__*/React.createElement(SegmentedControl, {
    items: [{
      id: 'boards',
      label: 'Other boards'
    }, {
      id: 'stats',
      label: 'Statistics'
    }, {
      id: 'field',
      label: 'Field'
    }],
    value: tab,
    onChange: setTab
  })), tab === 'boards' ? /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '4px 20px 24px'
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Live boards",
    meta: "Durham Masters"
  }), [['4', 'H. Nunn', 'D. Kerr', '4', '3', true], ['3', 'L. Okafor', 'T. Shaw', '2', '2', true], ['7', 'R. Blake', 'M. Doyle', '5', '1', false]].map(([b, h, a, hs, as, live]) => /*#__PURE__*/React.createElement("button", {
    key: b,
    onClick: () => {},
    style: {
      width: '100%',
      textAlign: 'left',
      background: 'none',
      border: 0,
      borderBottom: '1px solid var(--color-border-default)',
      padding: '14px 0',
      cursor: 'pointer',
      display: 'flex',
      alignItems: 'center',
      gap: 14
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      width: 56,
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 10px var(--font-ui)',
      letterSpacing: '.09em',
      textTransform: 'uppercase',
      color: 'var(--color-text-secondary)'
    }
  }, "Board"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 21px var(--font-sport)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, b)), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0,
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '600 15px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, h, " v ", a), live ? /*#__PURE__*/React.createElement(LiveIndicator, {
    size: "small"
  }) : /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, "Complete")), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '700 21px var(--font-sport)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, hs, "\u2013", as), /*#__PURE__*/React.createElement(Icon, {
    name: "chevron-right",
    size: 16,
    color: "var(--color-text-tertiary)"
  })))) : tab === 'stats' ? /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '4px 20px 24px',
      display: 'grid',
      gridTemplateColumns: '1fr 1fr',
      gap: 18
    }
  }, /*#__PURE__*/React.createElement(Stat, {
    label: "3-dart average",
    value: "89.3"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "3-dart average",
    value: "87.7",
    align: "right"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "First 9",
    value: "96.1"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "First 9",
    value: "93.4",
    align: "right"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Checkout %",
    value: "42",
    unit: "%"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Checkout %",
    value: "38",
    unit: "%",
    align: "right"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "180s",
    value: "4"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "180s",
    value: "2",
    align: "right"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Highest checkout",
    value: "148"
  }), /*#__PURE__*/React.createElement(Stat, {
    label: "Highest checkout",
    value: "121",
    align: "right"
  })) : /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '4px 20px 24px'
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Remaining field",
    meta: "4 players"
  }), [['H. Nunn', 1923, 'Semi final'], ['D. Kerr', 1906, 'Semi final'], ['L. Okafor', 1948, 'Semi final'], ['T. Shaw', 1877, 'Semi final']].map(([n, r, s]) => /*#__PURE__*/React.createElement("div", {
    key: n,
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      padding: '12px 0',
      borderBottom: '1px solid var(--color-border-default)'
    }
  }, /*#__PURE__*/React.createElement(PlayerIdentity, {
    name: n,
    rating: r,
    size: "small"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, s)))));
}
function FollowedLive({
  go
}) {
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    large: true,
    title: "Following",
    actions: [{
      icon: 'bell',
      label: 'Notifications'
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
  }, "Live now"), /*#__PURE__*/React.createElement(FilterChip, {
    count: 4
  }, "Playing today"), /*#__PURE__*/React.createElement(FilterChip, null, "Teams"), /*#__PURE__*/React.createElement(FilterChip, null, "Events")), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '20px 20px 8px'
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Live now",
    meta: "3 followed"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 20px 24px'
    }
  }, [['Harry Nunn', 1923, 'Durham Masters · Semi final', 'Board 4', '4–3', 121], ['Grange A', null, 'Tyne League · Division One', 'Grange WMC', '5–4', null], ['Sam Patel', 1812, 'North East Open · Round of 16', 'Board 11', '2–4', 56]].map(([n, r, ctx, loc, sc, req]) => /*#__PURE__*/React.createElement("button", {
    key: n,
    onClick: () => go('stream'),
    style: {
      width: '100%',
      textAlign: 'left',
      background: 'none',
      border: 0,
      borderBottom: '1px solid var(--color-border-default)',
      padding: '16px 0',
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
  }, ctx), /*#__PURE__*/React.createElement(LiveIndicator, {
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
      font: '700 21px var(--font-ui)',
      color: 'var(--color-text-primary)'
    }
  }, n, r ? /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '600 15px var(--font-sport)',
      color: 'var(--color-text-secondary)',
      marginLeft: 8
    }
  }, r.toLocaleString('en-GB')) : null), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '700 25px var(--font-sport)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, sc)), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      gap: 12,
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 13px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, loc), req ? /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '600 13px var(--font-sport)',
      color: 'var(--color-text-brand)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, "Requires ", req) : null, /*#__PURE__*/React.createElement("span", {
    style: {
      marginLeft: 'auto',
      display: 'flex',
      alignItems: 'center',
      gap: 4,
      font: '600 13px var(--font-ui)',
      color: 'var(--color-text-brand)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "video",
    size: 13
  }), "Feed"))))));
}
Object.assign(window, {
  StreamOverlay,
  StreamView,
  FollowedLive
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/thro-app/screens-stream.jsx", error: String((e && e.message) || e) }); }
