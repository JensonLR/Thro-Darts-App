try { (() => {
function FilterChip({
  children,
  selected,
  count,
  icon,
  onClick
}) {
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onClick,
    "aria-pressed": !!selected,
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 6,
      minHeight: 36,
      padding: '0 14px',
      borderRadius: 'var(--radius-status)',
      cursor: 'pointer',
      whiteSpace: 'nowrap',
      background: selected ? 'var(--color-background-inverse)' : 'transparent',
      color: selected ? 'var(--color-text-inverse)' : 'var(--color-text-primary)',
      border: `1px solid ${selected ? 'var(--color-background-inverse)' : 'var(--color-border-strong)'}`,
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-label-default-size)',
      fontWeight: 'var(--font-weight-semibold)'
    }
  }, icon ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 14
  }) : null, children, count != null ? /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-sport)',
      fontVariantNumeric: 'tabular-nums',
      opacity: 0.7
    }
  }, count) : null);
}
Object.assign(__ds_scope, { FilterChip });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/FilterChip.jsx", error: String((e && e.message) || e) }); }
