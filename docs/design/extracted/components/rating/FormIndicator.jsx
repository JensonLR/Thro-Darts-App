try { (() => {
function FormIndicator({
  results = ['W', 'W', 'L', 'W', 'L'],
  form,
  label = 'Form'
}) {
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      flexDirection: 'column',
      gap: 6
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'baseline',
      gap: 'var(--spacing-2)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "thro-eyebrow"
  }, label), form != null ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontSize: 'var(--typography-heading-3-size)',
      fontWeight: 'var(--font-weight-bold)',
      fontVariantNumeric: 'tabular-nums',
      color: 'var(--color-text-primary)'
    }
  }, form.toLocaleString('en-GB')) : null), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      gap: 4
    },
    "aria-label": `Recent results ${results.join(', ')}`
  }, results.map((r, i) => /*#__PURE__*/React.createElement("span", {
    key: i,
    style: {
      width: 22,
      height: 22,
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      borderRadius: 'var(--radius-small)',
      fontFamily: 'var(--font-sport)',
      fontSize: 12,
      fontWeight: 'var(--font-weight-bold)',
      background: r === 'W' ? 'var(--color-background-brand)' : 'var(--color-surface-secondary)',
      color: r === 'W' ? 'var(--thro-chalk)' : 'var(--color-text-secondary)',
      border: r === 'W' ? '1px solid transparent' : '1px solid var(--color-border-default)'
    }
  }, r))));
}
Object.assign(__ds_scope, { FormIndicator });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/rating/FormIndicator.jsx", error: String((e && e.message) || e) }); }
