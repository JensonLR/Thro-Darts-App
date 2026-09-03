try { (() => {
function SegmentedControl({
  items = [],
  value,
  onChange,
  fullWidth = true
}) {
  return /*#__PURE__*/React.createElement("div", {
    role: "tablist",
    style: {
      display: 'inline-flex',
      width: fullWidth ? '100%' : 'auto',
      padding: 2,
      gap: 2,
      background: 'var(--color-surface-secondary)',
      border: '1px solid var(--color-border-default)',
      borderRadius: 'var(--radius-status)'
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
        flex: fullWidth ? 1 : '0 0 auto',
        minHeight: 40,
        padding: '0 16px',
        border: 0,
        borderRadius: 'var(--radius-status)',
        cursor: 'pointer',
        background: on ? 'var(--color-background-raised)' : 'transparent',
        boxShadow: on ? 'var(--elevation-2)' : 'none',
        fontFamily: 'var(--font-ui)',
        fontSize: 'var(--typography-label-default-size)',
        fontWeight: on ? 'var(--font-weight-bold)' : 'var(--font-weight-medium)',
        color: on ? 'var(--color-text-primary)' : 'var(--color-text-secondary)',
        whiteSpace: 'nowrap'
      }
    }, it.label || it);
  }));
}
Object.assign(__ds_scope, { SegmentedControl });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/SegmentedControl.jsx", error: String((e && e.message) || e) }); }
