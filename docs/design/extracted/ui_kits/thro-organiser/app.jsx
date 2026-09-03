try { (() => {
const D = window.THRDesignSystem_ac73b5;
const {
  Icon
} = D;
const MAP = {
  control: window.Control,
  boards: window.Boards,
  queue: window.Queue,
  entries: window.Entries,
  draw: window.DrawManagement,
  disputes: window.Disputes,
  verification: window.Verification,
  league: window.League,
  venue: window.Venue
};
const ICONS = {
  control: 'target',
  boards: 'grid-2x2',
  queue: 'list-ordered',
  entries: 'clipboard-check',
  draw: 'git-fork',
  disputes: 'triangle-alert',
  verification: 'circle-check',
  league: 'shield',
  venue: 'map-pin'
};
function App() {
  const [screen, setScreen] = React.useState('control');
  const Body = MAP[screen];
  return /*#__PURE__*/React.createElement("div", {
    className: "app"
  }, /*#__PURE__*/React.createElement("nav", {
    className: "side",
    "aria-label": "Organiser"
  }, /*#__PURE__*/React.createElement("div", {
    className: "brand"
  }, /*#__PURE__*/React.createElement("img", {
    src: "../../assets/logo-chalk.svg",
    alt: "THR\xD8"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      font: '700 11px/14px var(--font-ui)',
      letterSpacing: '.09em',
      textTransform: 'uppercase',
      color: '#7C8380'
    }
  }, "Organiser")), window.NAV.map(([g, items]) => /*#__PURE__*/React.createElement(React.Fragment, {
    key: g
  }, /*#__PURE__*/React.createElement("div", {
    className: "grp"
  }, g), items.map(([id, label]) => /*#__PURE__*/React.createElement("button", {
    key: id,
    "aria-current": screen === id ? 'page' : undefined,
    onClick: () => setScreen(id)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: ICONS[id] || 'circle',
    size: 17
  }), label)))), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '16px 20px 0',
      borderTop: '1px solid #2C312E',
      margin: '16px 10px 0'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: '600 13px var(--font-ui)',
      color: 'var(--thro-chalk)'
    }
  }, "North East Darts Organisation"), /*#__PURE__*/React.createElement("div", {
    style: {
      font: '400 13px var(--font-ui)',
      color: '#7C8380'
    }
  }, "M. Pike \xB7 Tournament director"))), /*#__PURE__*/React.createElement("main", {
    className: "main"
  }, Body ? /*#__PURE__*/React.createElement(Body, {
    go: setScreen
  }) : null));
}
ReactDOM.createRoot(document.getElementById('root')).render(/*#__PURE__*/React.createElement(App, null));
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/thro-organiser/app.jsx", error: String((e && e.message) || e) }); }
