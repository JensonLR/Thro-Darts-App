try { (() => {
function NumericInput({
  label,
  value = 0,
  min = 0,
  max = 180,
  step = 1,
  suffix,
  onChange
}) {
  const set = v => onChange && onChange(Math.min(max, Math.max(min, v)));
  const btn = {
    width: 56,
    height: 56,
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    background: 'var(--color-surface-secondary)',
    border: '1px solid var(--color-border-default)',
    borderRadius: 'var(--radius-control)',
    cursor: 'pointer',
    color: 'var(--color-text-primary)'
  };
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-2)'
    }
  }, label ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-strong-size)',
      fontWeight: 'var(--font-weight-semibold)',
      color: 'var(--color-text-secondary)'
    }
  }, label) : null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--spacing-3)'
    }
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    "aria-label": "Decrease",
    onClick: () => set(value - step),
    style: btn
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "minus",
    size: 20
  })), /*#__PURE__*/React.createElement("span", {
    role: "spinbutton",
    "aria-valuenow": value,
    "aria-valuemin": min,
    "aria-valuemax": max,
    style: {
      minWidth: 96,
      textAlign: 'center',
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-heading-1-size)',
      fontWeight: 'var(--font-weight-bold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, value, suffix || ''), /*#__PURE__*/React.createElement("button", {
    type: "button",
    "aria-label": "Increase",
    onClick: () => set(value + step),
    style: btn
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "plus",
    size: 20
  }))));
}
Object.assign(__ds_scope, { NumericInput });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/NumericInput.jsx", error: String((e && e.message) || e) }); }
