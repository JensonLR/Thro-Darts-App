try { (() => {
const SIZES = {
  large: {
    h: 56,
    px: 24,
    fs: 'var(--typography-body-large-size)'
  },
  medium: {
    h: 48,
    px: 20,
    fs: 'var(--typography-body-default-size)'
  },
  small: {
    h: 44,
    px: 16,
    fs: 'var(--typography-label-default-size)'
  }
};
const VARIANTS = {
  primary: {
    background: 'var(--color-surface-brand)',
    color: 'var(--thro-chalk)',
    border: '2px solid transparent'
  },
  secondary: {
    background: 'transparent',
    color: 'var(--color-text-primary)',
    border: '2px solid var(--color-border-strong)'
  },
  ink: {
    background: 'var(--color-background-inverse)',
    color: 'var(--color-text-inverse)',
    border: '2px solid transparent'
  },
  ghost: {
    background: 'transparent',
    color: 'var(--color-text-primary)',
    border: '2px solid transparent'
  },
  destructive: {
    background: 'transparent',
    color: 'var(--color-status-error)',
    border: '2px solid var(--color-status-error)'
  }
};
function Button({
  children,
  variant = 'primary',
  size = 'medium',
  icon,
  iconAfter,
  fullWidth,
  disabled,
  loading,
  onClick,
  type = 'button',
  ariaLabel
}) {
  const s = SIZES[size] || SIZES.medium,
    v = VARIANTS[variant] || VARIANTS.primary;
  return /*#__PURE__*/React.createElement("button", {
    type: type,
    onClick: onClick,
    disabled: disabled || loading,
    "aria-label": ariaLabel,
    "aria-busy": loading || undefined,
    style: {
      ...v,
      minHeight: s.h,
      padding: `0 ${s.px}px`,
      width: fullWidth ? '100%' : 'auto',
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 'var(--spacing-2)',
      borderRadius: 'var(--radius-control)',
      fontFamily: 'var(--font-ui)',
      fontSize: s.fs,
      fontWeight: 'var(--font-weight-semibold)',
      letterSpacing: '0.005em',
      whiteSpace: 'nowrap',
      cursor: disabled ? 'not-allowed' : 'pointer',
      opacity: disabled ? 0.38 : 1,
      transition: 'transform var(--motion-duration-instant) var(--motion-easing-impact),opacity var(--motion-duration-fast) var(--motion-easing-resolve)'
    }
  }, loading ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "loader",
    size: 18
  }) : icon ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 18
  }) : null, /*#__PURE__*/React.createElement("span", {
    style: {
      whiteSpace: 'nowrap'
    }
  }, children), iconAfter ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: iconAfter,
    size: 18
  }) : null);
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Button.jsx", error: String((e && e.message) || e) }); }
