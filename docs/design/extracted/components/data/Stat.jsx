try { (() => {
function Stat({
  label,
  value,
  delta,
  unit,
  size = 'medium',
  align = 'left'
}) {
  const fs = size === 'large' ? 'var(--typography-heading-1-size)' : size === 'small' ? 'var(--typography-heading-3-size)' : 'var(--typography-heading-2-size)';
  const up = (delta || 0) > 0;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 2,
      alignItems: align === 'right' ? 'flex-end' : 'flex-start'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, label), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'baseline',
      gap: 6
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: fs,
      lineHeight: 1.05,
      fontWeight: 'var(--font-weight-bold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, value, unit ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: '0.6em',
      fontWeight: 'var(--font-weight-semibold)',
      color: 'var(--color-text-secondary)',
      marginLeft: 2
    }
  }, unit) : null), delta != null ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-metadata-size)',
      fontWeight: 'var(--font-weight-semibold)',
      fontVariantNumeric: 'tabular-nums',
      color: up ? 'var(--color-status-success)' : 'var(--color-text-secondary)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: up ? 'arrow-up' : 'arrow-down',
    size: 11
  }), Math.abs(delta)) : null));
}
Object.assign(__ds_scope, { Stat });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data/Stat.jsx", error: String((e && e.message) || e) }); }
