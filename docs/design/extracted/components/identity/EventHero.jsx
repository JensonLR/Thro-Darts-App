try { (() => {
function EventHero({
  name,
  date,
  venue,
  format,
  entry,
  status,
  strength,
  theme = 'dark',
  children
}) {
  return /*#__PURE__*/React.createElement("section", {
    "data-theme": theme === 'dark' ? 'dark' : undefined,
    style: {
      background: theme === 'dark' ? 'var(--thro-ink)' : 'var(--color-background-brand-subtle)',
      padding: 'var(--spacing-7) var(--space-screen-gutter)',
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-3)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexWrap: 'wrap',
      gap: 'var(--spacing-2)'
    }
  }, status ? /*#__PURE__*/React.createElement(__ds_scope.Tag, {
    tone: "brand"
  }, status) : null, strength ? /*#__PURE__*/React.createElement(__ds_scope.Tag, {
    tone: "neutral"
  }, strength) : null), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-label-default-size)',
      letterSpacing: '0.08em',
      textTransform: 'uppercase',
      fontWeight: 'var(--font-weight-semibold)',
      color: 'var(--color-text-secondary)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, date), /*#__PURE__*/React.createElement("h1", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-display-size)',
      lineHeight: 'var(--typography-display-line)',
      fontWeight: 'var(--font-weight-extrabold)',
      letterSpacing: 'var(--typography-display-tracking)',
      color: 'var(--color-text-primary)'
    }
  }, name), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-default-size)',
      color: 'var(--color-text-secondary)'
    }
  }, [venue, format, entry].filter(Boolean).join(' · ')), children ? /*#__PURE__*/React.createElement("div", {
    style: {
      paddingTop: 'var(--spacing-3)'
    }
  }, children) : null);
}
Object.assign(__ds_scope, { EventHero });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/identity/EventHero.jsx", error: String((e && e.message) || e) }); }
