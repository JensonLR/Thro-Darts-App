try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
function PlayerComparison({
  home,
  away,
  rows = [],
  theme = 'light'
}) {
  return /*#__PURE__*/React.createElement("div", {
    "data-theme": theme === 'dark' ? 'dark' : undefined,
    style: {
      background: 'var(--color-background-primary)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'flex-start',
      justifyContent: 'space-between',
      gap: 'var(--spacing-3)',
      paddingBottom: 'var(--spacing-4)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: '1 1 0',
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.PlayerIdentity, _extends({}, home, {
    size: "medium"
  }))), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: '0 0 auto',
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-strong-size)',
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: '0.08em',
      textTransform: 'uppercase',
      color: 'var(--color-text-tertiary)',
      paddingTop: 10
    }
  }, "vs"), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: '1 1 0',
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.PlayerIdentity, _extends({}, away, {
    size: "medium",
    align: "right"
  })))), rows.map(r => /*#__PURE__*/React.createElement("div", {
    key: r.label,
    style: {
      display: 'grid',
      gridTemplateColumns: '1fr auto 1fr',
      alignItems: 'center',
      gap: 'var(--spacing-3)',
      padding: 'var(--spacing-3) 0',
      borderTop: '1px solid var(--color-border-default)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-heading-3-size)',
      fontWeight: 'var(--font-weight-bold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, r.home), /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow",
    style: {
      textAlign: 'center'
    }
  }, r.label), /*#__PURE__*/React.createElement("span", {
    style: {
      textAlign: 'right',
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-heading-3-size)',
      fontWeight: 'var(--font-weight-bold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, r.away))));
}
Object.assign(__ds_scope, { PlayerComparison });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/identity/PlayerComparison.jsx", error: String((e && e.message) || e) }); }
