try { (() => {
function Divider({
  inset = 0,
  strong,
  vertical,
  style
}) {
  if (vertical) return /*#__PURE__*/React.createElement("span", {
    style: {
      width: 1,
      alignSelf: 'stretch',
      background: strong ? 'var(--color-border-strong)' : 'var(--color-border-default)',
      ...style
    }
  });
  return /*#__PURE__*/React.createElement("hr", {
    style: {
      border: 0,
      height: 1,
      margin: 0,
      marginLeft: inset,
      background: strong ? 'var(--color-border-strong)' : 'var(--color-border-default)',
      ...style
    }
  });
}
Object.assign(__ds_scope, { Divider });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Divider.jsx", error: String((e && e.message) || e) }); }
