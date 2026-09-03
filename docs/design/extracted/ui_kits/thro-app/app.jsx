try { (() => {
const D = window.THRDesignSystem_ac73b5;
const {
  BottomBar
} = D;
const SCREENS = [['Start', [['splash', 'Splash / launch'], ['onboarding', 'Onboarding']]], ['Home', [['home', 'Home — active player'], ['home-called', 'Home — match called'], ['home-new', 'Home — new player']]], ['Play', [['ready', 'Match ready'], ['scoring', 'Scoring — standard'], ['scoring-checkout', 'Scoring — checkout'], ['scoring-bust', 'Scoring — bust'], ['scoring-offline', 'Scoring — offline'], ['result', 'Match result']]], ['Live', [['live', 'Live directory'], ['live-match', 'Live match centre'], ['stream', 'Stream view'], ['following', 'Followed players live']]], ['Tournament', [['checkin', 'Check-in'], ['draw', 'Draw released'], ['bracket', 'Bracket — zoomed'], ['complete', 'Tournament complete']]], ['Shadow', [['shadow', 'Shadow overview'], ['shadow-setup', 'Shadow match setup'], ['shadow-play', 'Shadow — playing'], ['shadow-result', 'Practice result']]], ['Discover', [['discover', 'Discover'], ['event', 'Event detail']]], ['You', [['you', 'You — profile'], ['rating', 'Rating detail'], ['coach', 'Coach insight'], ['passport', 'THRØ Passport']]], ['Account', [['notifications', 'Notifications'], ['search', 'Search'], ['settings', 'Settings'], ['privacy', 'Privacy']]]];
const TAB_OF = {
  home: 'home',
  'home-called': 'home',
  'home-new': 'home',
  ready: 'play',
  scoring: 'play',
  'scoring-checkout': 'play',
  'scoring-bust': 'play',
  'scoring-offline': 'play',
  result: 'play',
  live: 'live',
  'live-match': 'live',
  stream: 'live',
  following: 'live',
  discover: 'discover',
  event: 'discover',
  checkin: 'discover',
  draw: 'discover',
  bracket: 'discover',
  complete: 'discover',
  you: 'you',
  rating: 'you',
  coach: 'you',
  passport: 'you',
  settings: 'you',
  privacy: 'you',
  notifications: 'home',
  search: 'discover',
  shadow: 'play',
  'shadow-setup': 'play',
  'shadow-play': 'play',
  'shadow-result': 'play'
};
const DARK = new Set(['scoring', 'scoring-checkout', 'scoring-bust', 'scoring-offline', 'live-match', 'stream', 'shadow', 'shadow-setup', 'shadow-play', 'splash']);
const NO_NAV = new Set(['scoring', 'scoring-checkout', 'scoring-bust', 'scoring-offline', 'shadow-play', 'splash', 'onboarding']);
const NO_STATUS = new Set(['splash']);
const MAP = {
  home: window.HomeActive,
  'home-called': window.HomeMatchCalled,
  'home-new': window.HomeNewPlayer,
  ready: window.MatchReady,
  scoring: window.ScoringStandard,
  'scoring-checkout': window.ScoringCheckout,
  'scoring-bust': window.ScoringBust,
  'scoring-offline': window.ScoringOffline,
  result: window.MatchResult,
  live: window.LiveDirectory,
  'live-match': window.LiveMatchCentre,
  discover: window.Discover,
  event: window.EventDetail,
  you: window.You,
  rating: window.RatingDetail,
  coach: window.CoachInsight,
  passport: window.Passport,
  stream: window.StreamView,
  following: window.FollowedLive,
  checkin: window.CheckIn,
  draw: window.DrawRelease,
  bracket: window.BracketDetail,
  complete: window.TournamentComplete,
  shadow: window.ShadowOverview,
  'shadow-setup': window.ShadowSetup,
  'shadow-play': window.ShadowPlay,
  'shadow-result': window.ShadowResult,
  splash: window.Splash,
  onboarding: window.Onboarding,
  settings: window.Settings,
  privacy: window.Privacy,
  notifications: window.Notifications,
  search: window.Search
};
function Phone({
  screen,
  go
}) {
  const dark = DARK.has(screen);
  const Body = MAP[screen];
  return /*#__PURE__*/React.createElement("div", {
    className: "phone",
    "data-theme": dark ? 'dark' : undefined
  }, !NO_STATUS.has(screen) ? /*#__PURE__*/React.createElement("div", {
    className: "statusbar"
  }, /*#__PURE__*/React.createElement("span", null, "20:41"), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      gap: 6,
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement("span", null, "5G"), /*#__PURE__*/React.createElement("span", null, "84%"))) : null, /*#__PURE__*/React.createElement("div", {
    className: "scroll"
  }, Body ? /*#__PURE__*/React.createElement(Body, {
    go: go
  }) : null), !NO_NAV.has(screen) ? /*#__PURE__*/React.createElement(BottomBar, {
    theme: dark ? 'dark' : 'light',
    value: TAB_OF[screen],
    onChange: t => go(t === 'play' ? 'ready' : t),
    badges: {
      live: true
    }
  }) : null, /*#__PURE__*/React.createElement("div", {
    className: "homebar"
  }, /*#__PURE__*/React.createElement("span", null)));
}
function App() {
  const [screen, setScreen] = React.useState('home');
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    className: "rail"
  }, /*#__PURE__*/React.createElement("h1", null, "THR\xD8 mobile UI kit"), /*#__PURE__*/React.createElement("p", null, "Recreation of the approved product surfaces. Tap through the phone or jump to a state."), SCREENS.map(([g, items]) => /*#__PURE__*/React.createElement(React.Fragment, {
    key: g
  }, /*#__PURE__*/React.createElement("div", {
    className: "grp"
  }, g), items.map(([id, label]) => /*#__PURE__*/React.createElement("button", {
    key: id,
    "aria-pressed": screen === id,
    onClick: () => setScreen(id)
  }, label))))), /*#__PURE__*/React.createElement(Phone, {
    screen: screen,
    go: setScreen
  }));
}
ReactDOM.createRoot(document.getElementById('root')).render(/*#__PURE__*/React.createElement(App, null));
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/thro-app/app.jsx", error: String((e && e.message) || e) }); }
