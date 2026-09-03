try { (() => {
function MatchSummary({
  result = 'win',
  score = '5–3',
  opponent,
  stats = [],
  theme = 'light'
}) {
  const won = result === 'win';
  return /*#__PURE__*/React.createElement("section", {
    "data-theme": theme === 'dark' ? 'dark' : undefined,
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-4)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-1)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-heading-2-size)',
      fontWeight: 'var(--font-weight-extrabold)',
      letterSpacing: '0.02em',
      textTransform: 'uppercase',
      color: won ? 'var(--color-text-brand)' : 'var(--color-text-primary)'
    }
  }, won ? 'You win' : 'You lose'), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-sport-hero-size)',
      lineHeight: 'var(--typography-sport-hero-line)',
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: 'var(--typography-sport-hero-tracking)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, score), opponent ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-default-size)',
      color: 'var(--color-text-secondary)'
    }
  }, opponent) : null), stats.length ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: 'repeat(2,1fr)',
      gap: 'var(--spacing-4) var(--spacing-6)',
      borderTop: '1px solid var(--color-border-default)',
      paddingTop: 'var(--spacing-4)'
    }
  }, stats.map(s => /*#__PURE__*/React.createElement("span", {
    key: s.label,
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, s.label), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-heading-2-size)',
      fontWeight: 'var(--font-weight-bold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, s.value)))) : null);
}
Object.assign(__ds_scope, { MatchSummary });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/scoring/MatchSummary.jsx", error: String((e && e.message) || e) }); }
