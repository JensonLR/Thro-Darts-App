try { (() => {
function IconButton({
  icon = 'ellipsis',
  label,
  size = 44,
  variant = 'ghost',
  onClick,
  disabled,
  selected
}) {
  const bg = variant === 'filled' ? 'var(--color-surface-secondary)' : 'transparent';
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onClick,
    disabled: disabled,
    "aria-label": label,
    "aria-pressed": selected,
    style: {
      width: size,
      height: size,
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      background: selected ? 'var(--color-background-brand-subtle)' : bg,
      border: variant === 'outlined' ? '1px solid var(--color-border-default)' : '1px solid transparent',
      borderRadius: 'var(--radius-control)',
      color: selected ? 'var(--color-text-brand)' : 'var(--color-text-primary)',
      opacity: disabled ? 0.38 : 1,
      cursor: disabled ? 'not-allowed' : 'pointer'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: Math.round(size * 0.45)
  }));
}
Object.assign(__ds_scope, { IconButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/IconButton.jsx", error: String((e && e.message) || e) }); }
