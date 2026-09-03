try { (() => {
const D = window.THRDesignSystem_ac73b5;
const {
  TopBar,
  SearchField,
  FilterChip,
  SectionHeader,
  EventRow,
  VenueRow,
  PlayerRow,
  Divider,
  EventHero,
  Button,
  Tag,
  Icon,
  VerificationState,
  SegmentedControl
} = D;
function Discover({
  go
}) {
  const [q, setQ] = React.useState('');
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(TopBar, {
    large: true,
    title: "Discover"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 20px 12px'
    }
  }, /*#__PURE__*/React.createElement(SearchField, {
    value: q,
    onChange: setQ,
    scope: "events, players and venues"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 20px 16px',
      display: 'flex',
      gap: 8,
      overflowX: 'auto'
    }
  }, /*#__PURE__*/React.createElement(FilterChip, {
    selected: true,
    icon: "map-pin"
  }, "Near you"), /*#__PURE__*/React.createElement(FilterChip, null, "Your level"), /*#__PURE__*/React.createElement(FilterChip, null, "Tonight"), /*#__PURE__*/React.createElement(FilterChip, null, "This week"), /*#__PURE__*/React.createElement(FilterChip, null, "Majors")), /*#__PURE__*/React.createElement(Divider, {
    inset: 20
  }), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '20px 20px 0'
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "For you",
    meta: "Matched to your level"
  }), /*#__PURE__*/React.createElement(EventRow, {
    name: "North East Open",
    date: "Sat 14 Sep \xB7 12:30",
    venue: "Sunderland Sports Centre",
    distance: "11 mi",
    format: "501 \xB7 Bo9",
    entry: "\xA318",
    fit: "good",
    status: "Registered",
    onClick: () => go('event')
  }), /*#__PURE__*/React.createElement(EventRow, {
    name: "Durham Masters Qualifier",
    date: "Sun 22 Sep \xB7 10:00",
    venue: "Riverside Club",
    distance: "18 mi",
    format: "501 \xB7 Bo11",
    entry: "\xA325",
    fit: "strong",
    onClick: () => go('event')
  }), /*#__PURE__*/React.createElement(EventRow, {
    name: "Tyne Invitational",
    date: "Sat 5 Oct \xB7 11:00",
    venue: "Newcastle Arena Suite",
    distance: "9 mi",
    format: "501 \xB7 Bo11",
    entry: "\xA340",
    fit: "stretch",
    onClick: () => go('event')
  })), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '24px 20px 0'
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Tonight",
    action: "All",
    onAction: () => {}
  }), /*#__PURE__*/React.createElement(VenueRow, {
    name: "Grange WMC",
    town: "Gateshead",
    boards: 8,
    distance: "4.2 mi",
    tonight: true,
    accessible: true
  }), /*#__PURE__*/React.createElement(VenueRow, {
    name: "Boro Legion",
    town: "Middlesbrough",
    boards: 6,
    distance: "31 mi",
    tonight: true
  })), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '24px 20px 24px'
    }
  }, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Players at your level"
  }), /*#__PURE__*/React.createElement(PlayerRow, {
    rank: 181,
    name: "Sam Okafor",
    rating: 1852,
    team: "Riverside",
    delta: 12,
    meta: "88.9 avg"
  }), /*#__PURE__*/React.createElement(PlayerRow, {
    rank: 186,
    name: "Chris Dunne",
    rating: 1841,
    team: "Grange B",
    delta: -4,
    verified: true,
    meta: "87.2 avg"
  })));
}
function EventDetail({
  go
}) {
  const [reg, setReg] = React.useState('open');
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(EventHero, {
    name: "North East Open",
    date: "Saturday 14 September \xB7 12:30",
    venue: "Sunderland Sports Centre",
    format: "501 \xB7 Best of 9 \xB7 Double out",
    entry: "\xA318 entry",
    status: reg === 'open' ? 'Registration open' : 'Registered',
    strength: "Field average 1,780"
  }, reg === 'open' ? /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    size: "large",
    fullWidth: true,
    onClick: () => setReg('done')
  }, "Register \xB7 \xA318") : /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement(Tag, {
    tone: "success",
    icon: "circle-check"
  }, "Registration confirmed"), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    size: "large",
    fullWidth: true,
    onClick: () => go('home-called')
  }, "Check in opens 11:30"))), /*#__PURE__*/React.createElement("section", {
    style: {
      padding: '24px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 20
    }
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Your fit"), /*#__PURE__*/React.createElement("p", {
    style: {
      font: '400 17px/25px var(--font-ui)',
      color: 'var(--color-text-primary)',
      paddingTop: 8,
      margin: 0
    }
  }, "Good competitive fit. The field average of 1,780 sits just below your rating of 1,847, with eight players above 1,900.")), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: '1fr 1fr',
      gap: 16
    }
  }, [['Format', '501 · Bo9'], ['Entries', '96 of 128'], ['Start', '12:30'], ['Boards', '16'], ['Rounds', 'Straight knockout'], ['Prize', '£1,400']].map(([l, v]) => /*#__PURE__*/React.createElement("span", {
    key: l,
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, l), /*#__PURE__*/React.createElement("span", {
    className: "thro-sport",
    style: {
      font: '600 17px var(--font-sport)',
      color: 'var(--color-text-primary)'
    }
  }, v)))), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Organiser"), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      font: '600 17px var(--font-ui)'
    }
  }, "North East Darts Organisation", /*#__PURE__*/React.createElement(Icon, {
    name: "circle-check",
    size: 15,
    color: "var(--color-status-verified)",
    title: "Verified organiser"
  })), /*#__PURE__*/React.createElement(VerificationState, {
    state: "organiser-confirmed",
    explain: true
  })), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Venue"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '600 17px var(--font-ui)'
    }
  }, "Sunderland Sports Centre"), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '400 15px var(--font-ui)',
      color: 'var(--color-text-secondary)'
    }
  }, "Chester Road, Sunderland \xB7 11 mi \xB7 Step-free access \xB7 Parking on site"))));
}
Object.assign(window, {
  Discover,
  EventDetail
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/thro-app/screens-discover.jsx", error: String((e && e.message) || e) }); }
