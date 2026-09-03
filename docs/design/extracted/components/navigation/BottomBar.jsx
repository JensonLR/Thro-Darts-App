try { (() => {
const TABS = [{
  id: 'home',
  label: 'Home',
  icon: 'house'
}, {
  id: 'play',
  label: 'Play',
  icon: 'target'
}, {
  id: 'live',
  label: 'Live',
  icon: 'radio'
}, {
  id: 'discover',
  label: 'Discover',
  icon: 'compass'
}, {
  id: 'you',
  label: 'You',
  icon: 'circle-user'
}];
function BottomBar({
  value = 'home',
  onChange,
  badges = {},
  theme = 'light'
}) {
  return /*#__PURE__*/React.createElement("nav", {
    "data-theme": theme === 'dark' ? 'dark' : undefined,
    "aria-label": "Primary",
    style: {
      display: 'flex',
      background: 'var(--color-background-primary)',
      borderTop: '1px solid var(--color-border-default)',
      padding: '8px 0 10px'
    }
  }, TABS.map(t => {
    const on = value === t.id;
    return /*#__PURE__*/React.createElement("button", {
      key: t.id,
      type: "button",
      "aria-current": on ? 'page' : undefined,
      onClick: () => onChange && onChange(t.id),
      style: {
        flex: 1,
        minHeight: 52,
        border: 0,
        background: 'none',
        cursor: 'pointer',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: 4,
        color: on ? 'var(--color-text-primary)' : 'var(--color-text-secondary)',
        position: 'relative'
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        position: 'relative',
        display: 'flex'
      }
    }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
      name: t.icon,
      size: 24
    }), badges[t.id] ? /*#__PURE__*/React.createElement("span", {
      style: {
        position: 'absolute',
        top: -2,
        right: -6,
        width: 8,
        height: 8,
        borderRadius: '50%',
        background: 'var(--color-status-live)'
      }
    }) : null), /*#__PURE__*/React.createElement("span", {
      style: {
        fontFamily: 'var(--font-ui)',
        fontSize: '11px',
        letterSpacing: '0.02em',
        fontWeight: on ? 'var(--font-weight-bold)' : 'var(--font-weight-medium)'
      }
    }, t.label), on ? /*#__PURE__*/React.createElement("span", {
      style: {
        position: 'absolute',
        top: -8,
        width: 22,
        height: 2,
        background: 'var(--color-text-primary)'
      }
    }) : null);
  }));
}
Object.assign(__ds_scope, { BottomBar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/BottomBar.jsx", error: String((e && e.message) || e) }); }
