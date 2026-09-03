try { (() => {
function RatingMovement({
  before = 1821,
  after = 1847,
  reason,
  opponent,
  theme = 'light'
}) {
  const delta = after - before,
    up = delta > 0;
  return /*#__PURE__*/React.createElement("section", {
    "data-theme": theme === 'dark' ? 'dark' : undefined,
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-4)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "thro-eyebrow"
  }, "Rating"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--spacing-4)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-heading-1-size)',
      fontWeight: 'var(--font-weight-semibold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-secondary)'
    }
  }, before.toLocaleString('en-GB')), /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "arrow-right",
    size: 18,
    color: "var(--color-text-tertiary)"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-sport-hero-size)',
      lineHeight: 'var(--typography-sport-hero-line)',
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: 'var(--typography-sport-hero-tracking)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, after.toLocaleString('en-GB')), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 2,
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-heading-2-size)',
      fontWeight: 'var(--font-weight-bold)',
      fontVariantNumeric: 'tabular-nums',
      color: up ? 'var(--color-status-success)' : 'var(--color-text-secondary)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: up ? 'arrow-up' : 'arrow-down',
    size: 18
  }), Math.abs(delta))), opponent || reason ? /*#__PURE__*/React.createElement("div", {
    style: {
      borderTop: '1px solid var(--color-border-default)',
      paddingTop: 'var(--spacing-3)',
      display: 'flex',
      flexDirection: 'column',
      gap: 6
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, "Why your rating moved"), opponent ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-default-size)',
      color: 'var(--color-text-primary)'
    }
  }, opponent) : null, reason ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-default-size)',
      color: 'var(--color-text-secondary)'
    }
  }, reason) : null) : null);
}
Object.assign(__ds_scope, { RatingMovement });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/rating/RatingMovement.jsx", error: String((e && e.message) || e) }); }
