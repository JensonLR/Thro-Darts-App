try { (() => {
function LegState({
  home = 2,
  away = 1,
  bestOf = 9,
  unit = 'Legs',
  theme = 'dark'
}) {
  return /*#__PURE__*/React.createElement("div", {
    "data-theme": theme === 'dark' ? 'dark' : undefined,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--spacing-2)',
      fontFamily: 'var(--font-sport)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, unit), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 'var(--typography-heading-3-size)',
      fontWeight: 'var(--font-weight-bold)',
      color: 'var(--color-text-primary)'
    }
  }, home, "\u2013", away), bestOf ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 'var(--typography-metadata-size)',
      color: 'var(--color-text-secondary)'
    }
  }, "Best of ", bestOf) : null);
}
Object.assign(__ds_scope, { LegState });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/scoring/LegState.jsx", error: String((e && e.message) || e) }); }
