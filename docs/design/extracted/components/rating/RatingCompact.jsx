try { (() => {
function RatingCompact({
  rating,
  delta,
  label = 'Rating',
  provisional
}) {
  const up = (delta || 0) > 0;
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'baseline',
      gap: 'var(--spacing-2)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, label), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-heading-3-size)',
      fontWeight: 'var(--font-weight-bold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, provisional ? '—' : rating.toLocaleString('en-GB')), delta != null && !provisional ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-label-strong-size)',
      fontWeight: 'var(--font-weight-semibold)',
      fontVariantNumeric: 'tabular-nums',
      color: up ? 'var(--color-status-success)' : 'var(--color-text-secondary)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: up ? 'arrow-up' : 'arrow-down',
    size: 11
  }), Math.abs(delta)) : null);
}
Object.assign(__ds_scope, { RatingCompact });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/rating/RatingCompact.jsx", error: String((e && e.message) || e) }); }
