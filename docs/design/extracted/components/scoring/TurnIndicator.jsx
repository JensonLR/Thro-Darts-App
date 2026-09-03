try { (() => {
function TurnIndicator({
  player = 'You',
  dartsThrown = 0,
  active = true,
  theme = 'dark'
}) {
  return /*#__PURE__*/React.createElement("div", {
    "data-theme": theme === 'dark' ? 'dark' : undefined,
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 'var(--spacing-3)',
      padding: 'var(--spacing-2) var(--spacing-4)',
      borderRadius: 'var(--radius-status)',
      background: active ? 'var(--color-background-brand)' : 'var(--color-surface-secondary)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-default-size)',
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: '0.04em',
      textTransform: 'uppercase',
      whiteSpace: 'nowrap',
      color: active ? 'var(--thro-chalk)' : 'var(--color-text-secondary)'
    }
  }, active ? `${player} to throw` : `${player} waiting`), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      gap: 4
    },
    "aria-label": `${dartsThrown} of 3 darts thrown`
  }, [0, 1, 2].map(i => /*#__PURE__*/React.createElement("span", {
    key: i,
    style: {
      width: 7,
      height: 7,
      borderRadius: '50%',
      background: i < dartsThrown ? active ? 'var(--thro-chalk)' : 'var(--color-text-secondary)' : 'transparent',
      border: `1px solid ${active ? 'rgba(247,246,242,0.6)' : 'var(--color-border-strong)'}`
    }
  }))));
}
Object.assign(__ds_scope, { TurnIndicator });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/scoring/TurnIndicator.jsx", error: String((e && e.message) || e) }); }
