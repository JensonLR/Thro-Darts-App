try { (() => {
function Checkout({
  required = 121,
  route = ['T20', 'T11', 'D14'],
  theme = 'dark',
  compact,
  hideValue
}) {
  return /*#__PURE__*/React.createElement("div", {
    "data-theme": theme === 'dark' ? 'dark' : undefined,
    style: {
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      gap: 'var(--spacing-2)',
      padding: compact ? 'var(--spacing-3)' : 'var(--spacing-4)',
      border: '2px solid var(--color-border-brand)',
      borderRadius: 'var(--radius-card)',
      background: 'var(--color-background-brand-subtle)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow",
    style: {
      color: 'var(--color-text-brand)'
    }
  }, "Checkout available"), hideValue ? null : /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: compact ? 'var(--typography-heading-1-size)' : 'var(--typography-sport-hero-size)',
      lineHeight: 1,
      fontWeight: 'var(--font-weight-bold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, required), route && route.length ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      gap: 'var(--spacing-2)'
    }
  }, route.map(r => /*#__PURE__*/React.createElement("span", {
    key: r,
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-label-default-size)',
      fontWeight: 'var(--font-weight-semibold)',
      letterSpacing: '0.04em',
      padding: '2px 8px',
      borderRadius: 'var(--radius-small)',
      background: 'var(--color-background-raised)',
      border: '1px solid var(--color-border-default)',
      color: 'var(--color-text-primary)'
    }
  }, r))) : null);
}
Object.assign(__ds_scope, { Checkout });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/scoring/Checkout.jsx", error: String((e && e.message) || e) }); }
