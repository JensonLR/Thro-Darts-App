try { (() => {
function Progress({
  value = 0,
  max = 100,
  label,
  valueLabel,
  tone = 'brand',
  height = 6
}) {
  const pct = Math.max(0, Math.min(100, value / max * 100));
  const fill = tone === 'achievement' ? 'var(--color-text-achievement)' : tone === 'neutral' ? 'var(--color-text-secondary)' : 'var(--color-background-brand)';
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-2)'
    }
  }, label || valueLabel ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'baseline'
    }
  }, label ? /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, label) : null, valueLabel ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-label-default-size)',
      fontWeight: 'var(--font-weight-semibold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, valueLabel) : null) : null, /*#__PURE__*/React.createElement("div", {
    role: "progressbar",
    "aria-valuenow": value,
    "aria-valuemax": max,
    "aria-label": label,
    style: {
      height,
      background: 'var(--color-surface-secondary)',
      borderRadius: 1,
      overflow: 'hidden'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: pct + '%',
      height: '100%',
      background: fill,
      transition: 'width var(--motion-duration-emphasis) var(--motion-easing-impact)'
    }
  })));
}
Object.assign(__ds_scope, { Progress });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/state/Progress.jsx", error: String((e && e.message) || e) }); }
