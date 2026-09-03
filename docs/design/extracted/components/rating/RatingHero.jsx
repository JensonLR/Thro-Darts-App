try { (() => {
function RatingHero({
  rating = 1847,
  status = 'established',
  delta,
  band,
  rankCountry,
  rankRegion,
  form,
  theme = 'light'
}) {
  const up = (delta || 0) > 0,
    prov = status === 'provisional';
  return /*#__PURE__*/React.createElement("section", {
    "data-theme": theme === 'dark' ? 'dark' : undefined,
    style: {
      background: 'var(--color-background-primary)',
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-3)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "thro-eyebrow"
  }, "THR\xD8 Rating"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'baseline',
      gap: 'var(--spacing-4)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-rating-hero-size)',
      lineHeight: 'var(--typography-rating-hero-line)',
      fontWeight: 'var(--font-weight-bold)',
      letterSpacing: 'var(--typography-rating-hero-tracking)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, prov ? '—' : rating.toLocaleString('en-GB')), delta != null && !prov ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 2,
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-heading-3-size)',
      fontWeight: 'var(--font-weight-semibold)',
      fontVariantNumeric: 'tabular-nums',
      color: up ? 'var(--color-status-success)' : 'var(--color-text-secondary)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: up ? 'arrow-up' : 'arrow-down',
    size: 16
  }), Math.abs(delta)) : null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--spacing-2)',
      flexWrap: 'wrap'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Tag, {
    tone: prov ? 'warning' : 'brand',
    icon: prov ? 'clock' : 'circle-check'
  }, prov ? 'Rating establishing' : 'Established'), band ? /*#__PURE__*/React.createElement(__ds_scope.Tag, {
    tone: "neutral"
  }, band) : null), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--spacing-6)',
      paddingTop: 'var(--spacing-2)'
    }
  }, [[rankCountry, 'UK rank'], [rankRegion, 'Regional rank'], [form != null ? form.toLocaleString('en-GB') : null, 'Recent form']].filter(x => x[0]).map(([v, l]) => /*#__PURE__*/React.createElement("span", {
    key: l,
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-heading-3-size)',
      fontWeight: 'var(--font-weight-semibold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, v), /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, l)))));
}
Object.assign(__ds_scope, { RatingHero });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/rating/RatingHero.jsx", error: String((e && e.message) || e) }); }
