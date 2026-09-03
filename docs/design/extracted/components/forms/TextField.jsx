try { (() => {
function TextField({
  label,
  value,
  placeholder,
  helper,
  error,
  disabled,
  icon,
  type = 'text',
  onChange,
  id
}) {
  const fid = id || `tf-${label || 'field'}`.replace(/\s+/g, '-').toLowerCase();
  const borderColor = error ? 'var(--color-status-error)' : 'var(--color-border-strong)';
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--spacing-2)',
      opacity: disabled ? 0.4 : 1
    }
  }, label ? /*#__PURE__*/React.createElement("label", {
    htmlFor: fid,
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
      gap: 'var(--spacing-2)',
      minHeight: 52,
      padding: '0 var(--spacing-4)',
      background: 'var(--color-surface-primary)',
      border: `1px solid ${borderColor}`,
      borderRadius: 'var(--radius-field)'
    }
  }, icon ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: icon,
    size: 18,
    color: "var(--color-text-secondary)"
  }) : null, /*#__PURE__*/React.createElement("input", {
    id: fid,
    type: type,
    defaultValue: value,
    placeholder: placeholder,
    disabled: disabled,
    onChange: e => onChange && onChange(e.target.value),
    "aria-invalid": !!error,
    style: {
      flex: 1,
      minWidth: 0,
      border: 0,
      outline: 'none',
      background: 'transparent',
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-body-default-size)',
      color: 'var(--color-text-primary)'
    }
  })), error || helper ? /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--typography-metadata-size)',
      color: error ? 'var(--color-status-error)' : 'var(--color-text-secondary)'
    }
  }, error ? /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "circle-alert",
    size: 13
  }) : null, error || helper) : null);
}
Object.assign(__ds_scope, { TextField });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/TextField.jsx", error: String((e && e.message) || e) }); }
