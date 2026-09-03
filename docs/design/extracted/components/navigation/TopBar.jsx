try { (() => {
function TopBar({
  title,
  eyebrow,
  onBack,
  actions = [],
  theme = 'light',
  large
}) {
  const dark = theme === 'dark';
  return /*#__PURE__*/React.createElement("header", {
    "data-theme": dark ? 'dark' : undefined,
    style: {
      display: 'flex',
      flexDirection: large ? 'column' : 'row',
      alignItems: large ? 'stretch' : 'center',
      gap: large ? 'var(--spacing-2)' : 'var(--spacing-3)',
      padding: 'var(--spacing-3) var(--space-screen-gutter) var(--spacing-4)',
      background: 'var(--color-background-primary)',
      borderBottom: '1px solid var(--color-border-default)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--spacing-3)'
    }
  }, onBack ? /*#__PURE__*/React.createElement("button", {
    type: "button",
    "aria-label": "Back",
    onClick: onBack,
    style: {
      width: 44,
      height: 44,
      marginLeft: -12,
      border: 0,
      background: 'none',
      cursor: 'pointer',
      color: 'var(--color-text-primary)',
      display: 'flex',
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "chevron-left",
    size: 26
  })) : null, !large ? /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, eyebrow ? /*#__PURE__*/React.createElement("div", {
    className: "thro-eyebrow",
    style: {
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, eyebrow) : null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-heading-3-size)',
      fontWeight: 'var(--font-weight-bold)',
      color: 'var(--color-text-primary)',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, title)) : /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--spacing-1)'
    }
  }, actions.map(a => /*#__PURE__*/React.createElement("button", {
    key: a.icon,
    type: "button",
    "aria-label": a.label,
    onClick: a.onClick,
    style: {
      width: 44,
      height: 44,
      border: 0,
      background: 'none',
      cursor: 'pointer',
      color: 'var(--color-text-primary)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: a.icon,
    size: 22
  }))))), large ? /*#__PURE__*/React.createElement("div", null, eyebrow ? /*#__PURE__*/React.createElement("div", {
    className: "thro-eyebrow"
  }, eyebrow) : null, /*#__PURE__*/React.createElement("h1", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-heading-1-size)',
      lineHeight: 'var(--typography-heading-1-line)',
      fontWeight: 'var(--font-weight-extrabold)',
      letterSpacing: '-0.01em',
      color: 'var(--color-text-primary)'
    }
  }, title)) : null);
}
Object.assign(__ds_scope, { TopBar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/TopBar.jsx", error: String((e && e.message) || e) }); }
