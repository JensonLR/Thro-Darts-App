try { (() => {
function SearchField({
  placeholder = 'Players, events, venues',
  value,
  onChange,
  onClear,
  scope
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--spacing-2)',
      minHeight: 48,
      padding: '0 var(--spacing-4)',
      background: 'var(--color-surface-secondary)',
      border: '1px solid var(--color-border-default)',
      borderRadius: 'var(--radius-field)'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "search",
    size: 18,
    color: "var(--color-text-secondary)"
  }), /*#__PURE__*/React.createElement("input", {
    value: value,
    placeholder: placeholder,
    onChange: e => onChange && onChange(e.target.value),
    "aria-label": scope ? `Search ${scope}` : 'Search',
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
  }), value ? /*#__PURE__*/React.createElement("button", {
    type: "button",
    "aria-label": "Clear search",
    onClick: onClear,
    style: {
      border: 0,
      background: 'none',
      cursor: 'pointer',
      color: 'var(--color-text-secondary)',
      display: 'flex'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "x",
    size: 18
  })) : null);
}
Object.assign(__ds_scope, { SearchField });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/SearchField.jsx", error: String((e && e.message) || e) }); }
