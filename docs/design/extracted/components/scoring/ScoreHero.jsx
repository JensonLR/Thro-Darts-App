try { (() => {
function ScoreHero({
  home = 5,
  away = 3,
  homeLabel = 'You',
  awayLabel = 'Opponent',
  unit = 'Legs',
  theme = 'dark'
}) {
  const num = {
    fontFamily: 'var(--font-sport)',
    fontSize: 'var(--typography-sport-hero-size)',
    lineHeight: 'var(--typography-sport-hero-line)',
    fontWeight: 'var(--font-weight-bold)',
    letterSpacing: 'var(--typography-sport-hero-tracking)',
    fontVariantNumeric: 'tabular-nums',
    color: 'var(--color-text-primary)'
  };
  return /*#__PURE__*/React.createElement("div", {
    "data-theme": theme === 'dark' ? 'dark' : undefined,
    style: {
      display: 'grid',
      gridTemplateColumns: '1fr auto 1fr',
      alignItems: 'center',
      gap: 'var(--spacing-4)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 4
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, homeLabel), /*#__PURE__*/React.createElement("span", {
    style: num
  }, home)), /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow",
    style: {
      textAlign: 'center'
    }
  }, unit), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 4,
      textAlign: 'right',
      alignItems: 'flex-end'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, awayLabel), /*#__PURE__*/React.createElement("span", {
    style: num
  }, away)));
}
Object.assign(__ds_scope, { ScoreHero });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/scoring/ScoreHero.jsx", error: String((e && e.message) || e) }); }
