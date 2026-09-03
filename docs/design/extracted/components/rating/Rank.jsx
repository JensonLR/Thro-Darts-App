try { (() => {
function Rank({
  position,
  scope = 'UK',
  delta,
  size = 'medium'
}) {
  const fs = size === 'large' ? 'var(--typography-heading-2-size)' : 'var(--typography-heading-3-size)';
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: fs,
      fontWeight: 'var(--font-weight-bold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, "#", position, delta ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 'var(--typography-metadata-size)',
      fontWeight: 'var(--font-weight-medium)',
      color: 'var(--color-text-secondary)',
      marginLeft: 6
    }
  }, delta > 0 ? '+' : '', delta) : null), /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, scope));
}
Object.assign(__ds_scope, { Rank });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/rating/Rank.jsx", error: String((e && e.message) || e) }); }
