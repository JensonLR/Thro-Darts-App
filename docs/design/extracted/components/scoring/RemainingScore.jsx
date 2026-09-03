try { (() => {
function RemainingScore({
  value = 501,
  label = 'You require',
  state = 'normal',
  darts,
  theme = 'dark'
}) {
  const bust = state === 'bust',
    checkout = state === 'checkout';
  const color = bust ? 'var(--color-status-error)' : checkout ? 'var(--color-text-brand)' : 'var(--color-text-primary)';
  return /*#__PURE__*/React.createElement("div", {
    "data-theme": theme === 'dark' ? 'dark' : undefined,
    "aria-live": "polite",
    style: {
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      gap: 'var(--spacing-1)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow",
    style: {
      color: bust ? 'var(--color-status-error)' : 'var(--color-text-secondary)'
    }
  }, bust ? 'Bust — score restored' : label), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-score-hero-size)',
      lineHeight: 'var(--typography-score-hero-line)',
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: 'var(--typography-score-hero-tracking)',
      fontVariantNumeric: 'tabular-nums',
      color
    }
  }, value), darts ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-label-default-size)',
      color: 'var(--color-text-secondary)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, darts) : null);
}
Object.assign(__ds_scope, { RemainingScore });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/scoring/RemainingScore.jsx", error: String((e && e.message) || e) }); }
