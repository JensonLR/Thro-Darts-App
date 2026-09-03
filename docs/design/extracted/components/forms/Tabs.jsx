try { (() => {
function Tabs({
  items = [],
  value,
  onChange
}) {
  return /*#__PURE__*/React.createElement("div", {
    role: "tablist",
    style: {
      display: 'flex',
      gap: 'var(--spacing-6)',
      borderBottom: '1px solid var(--color-border-default)'
    }
  }, items.map(it => {
    const k = it.id || it,
      on = value === k;
    return /*#__PURE__*/React.createElement("button", {
      key: k,
      role: "tab",
      "aria-selected": on,
      onClick: () => onChange && onChange(k),
      style: {
        border: 0,
        background: 'none',
        padding: '0 0 12px',
        cursor: 'pointer',
        fontFamily: 'var(--font-ui)',
        fontSize: 'var(--typography-label-default-size)',
        fontWeight: on ? 'var(--font-weight-bold)' : 'var(--font-weight-medium)',
        color: on ? 'var(--color-text-primary)' : 'var(--color-text-secondary)',
        boxShadow: on ? 'inset 0 -2px 0 0 var(--color-text-primary)' : 'none'
      }
    }, it.label || it);
  }));
}
Object.assign(__ds_scope, { Tabs });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Tabs.jsx", error: String((e && e.message) || e) }); }
